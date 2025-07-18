//
//  ContentView.swift
//  orthoreader
//
//  Created by Matt Arthur on 7/17/25.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AVFoundation

struct ContentView: View {
    @State private var isPickerPresented = false
    @State private var extractedText: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSpeaking = false
    @State private var isPaused = false
    @State private var speechDelegate: SpeechDelegate? = nil
    private let synthesizer = AVSpeechSynthesizer()

    // Word and group indexing
    @State private var wordOffsets: [(start: Int, end: Int)] = []
    @State private var wordGroups: [[Int]] = [] // Each group is an array of word indices
    @State private var selectedGroup: Int? = nil
    @State private var spokenGroup: Int? = nil
    @State private var pendingGroupJump: Int? = nil
    @State private var pdfBookmarkKey: String? = nil
    @State private var savedBookmarkGroup: Int? = nil
    @State private var lastLoadedPDFKey: String? = nil
    @State private var scrollToGroup: Int? = nil

    var body: some View {
        ZStack {
            // Show background image only when no PDF is loaded
            if extractedText.isEmpty {
                Image("LaunchBackground")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }
            VStack {
                // Show PDF selection buttons only when not speaking
                if !isSpeaking {
                    Button(action: {
                        isPickerPresented = true
                    }) {
                        Label("Select PDF", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.top)

                    Button(action: {
                        loadSamplePDF()
                    }) {
                        Label("Load Sample PDF", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.bottom)
                } else {
                    Button(action: {
                        // Reset to home: stop TTS and clear PDF and state
                        stopSpeaking()
                        clearBookmark()
                        extractedText = ""
                        errorMessage = nil
                        wordOffsets = []
                        wordGroups = []
                        selectedGroup = nil
                        spokenGroup = nil
                        pendingGroupJump = nil
                        isPaused = false
                        isSpeaking = false
                    }) {
                        Label("Home", systemImage: "house")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.top)
                }

                if !extractedText.isEmpty {
                    // Prominently display currently spoken text when TTS is active
                    if isSpeaking, let groupIdx = spokenGroup, groupIdx < wordGroups.count {
                        let group = wordGroups[groupIdx]
                        let start = wordOffsets[group.first ?? 0].start
                        let end = wordOffsets[group.last ?? 0].end
                        let textRange = extractedText.index(extractedText.startIndex, offsetBy: start)..<extractedText.index(extractedText.startIndex, offsetBy: end)
                        let groupText = String(extractedText[textRange])
                        Text(groupText)
                            .padding()
                            .background(Color.yellow.opacity(0.4))
                            .cornerRadius(8)
                            .font(.title3.bold())
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                    // Resume button if bookmark exists and not currently speaking
                    if let savedGroup = savedBookmarkGroup, !isSpeaking {
                        Button(action: {
                            startSpeaking(fromGroup: savedGroup)
                        }) {
                            Label("Resume from last position", systemImage: "bookmark.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }
                    // Progress Indicator
                    if wordGroups.count > 0 {
                        let progress = spokenGroup != nil ? Double(spokenGroup! + 1) / Double(wordGroups.count) : 0.0
                        VStack(spacing: 4) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(.systemGray5))
                                        .frame(height: 12)
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: geo.size.width * progress, height: 12)
                                        .animation(.easeInOut(duration: 0.2), value: progress)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    let rel = location.x / geo.size.width
                                    let groupIdx = min(max(Int(rel * Double(wordGroups.count)), 0), wordGroups.count - 1)
                                    if isSpeaking {
                                        pendingGroupJump = groupIdx
                                        stopSpeaking()
                                    } else {
                                        startSpeaking(fromGroup: groupIdx)
                                    }
                                    // Scroll to the selected group
                                    scrollToGroup = groupIdx
                                }
                            }
                            .frame(height: 16)
                            Text("\(Int(progress * 100))% read")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(wordGroups.indices, id: \.self) { groupIdx in
                                    let group = wordGroups[groupIdx]
                                    let start = wordOffsets[group.first ?? 0].start
                                    let end = wordOffsets[group.last ?? 0].end
                                    let textRange = extractedText.index(extractedText.startIndex, offsetBy: start)..<extractedText.index(extractedText.startIndex, offsetBy: end)
                                    let groupText = String(extractedText[textRange])
                                    let isHighlighted = selectedGroup == groupIdx || spokenGroup == groupIdx
                                    Button(action: {
                                        selectedGroup = groupIdx
                                        if isSpeaking {
                                            pendingGroupJump = groupIdx
                                            stopSpeaking()
                                        } else {
                                            startSpeaking(fromGroup: groupIdx)
                                        }
                                        // Scroll to the selected group
                                        scrollToGroup = groupIdx
                                    }) {
                                        Text(groupText)
                                            .padding(4)
                                            .background(isHighlighted ? Color.yellow.opacity(0.3) : Color.clear)
                                            .cornerRadius(4)
                                    }
                                    .id(groupIdx)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: spokenGroup) { newGroup in
                            if let group = newGroup {
                                withAnimation {
                                    scrollProxy.scrollTo(group, anchor: .center)
                                }
                            }
                        }
                        .onChange(of: scrollToGroup) { group in
                            if let group = group {
                                withAnimation {
                                    scrollProxy.scrollTo(group, anchor: .center)
                                }
                                scrollToGroup = nil
                            }
                        }
                    }
                    // Move controls here so they are always visible
                    HStack {
                        if !isSpeaking {
                            Button(action: {
                                startSpeaking()
                            }) {
                                Label("Read Aloud", systemImage: "speaker.wave.2.fill")
                            }
                            .padding(.trailing)
                            .disabled(extractedText.isEmpty)
                        }
                        if isSpeaking {
                            Button(action: {
                                if isPaused {
                                    resumeSpeaking()
                                } else {
                                    pauseSpeaking()
                                }
                            }) {
                                Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                            }
                            Button(action: {
                                restartFromBeginning()
                            }) {
                                Label("Restart", systemImage: "arrow.counterclockwise")
                            }
                            .disabled(extractedText.isEmpty)
                        }
                    }
                    .padding(.bottom)
                } else {
                    Text("No PDF selected.")
                        .foregroundColor(.secondary)
                }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
            .sheet(isPresented: $isPickerPresented) {
                DocumentPicker { url in
                    if let url = url {
                        extractText(from: url)
                    }
                }
            }
        }
    }

    // MARK: - PDF and Text Extraction
    private func extractText(from url: URL) {
        guard let pdf = PDFDocument(url: url) else {
            errorMessage = "Failed to open PDF."
            return
        }
        var text = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        extractedText = text
        errorMessage = nil
        indexWordsAndGroups()
        // Set bookmark key based on file name
        let key = "bookmark_" + (url.lastPathComponent)
        pdfBookmarkKey = key
        lastLoadedPDFKey = key
        // Load bookmark
        if let saved = UserDefaults.standard.value(forKey: key) as? Int {
            savedBookmarkGroup = saved
        } else {
            savedBookmarkGroup = nil
        }
    }

    private func loadSamplePDF() {
        if let url = Bundle.main.url(forResource: "sample", withExtension: "pdf") {
            extractText(from: url)
        } else {
            errorMessage = "Sample PDF not found in app bundle."
        }
    }

    // Save bookmark when spokenGroup changes
    private func saveBookmark() {
        guard let key = pdfBookmarkKey, let group = spokenGroup else { return }
        UserDefaults.standard.setValue(group, forKey: key)
        savedBookmarkGroup = group
    }

    // Clear bookmark for previous PDF
    private func clearBookmark() {
        if let key = lastLoadedPDFKey {
            UserDefaults.standard.removeObject(forKey: key)
        }
        savedBookmarkGroup = nil
        pdfBookmarkKey = nil
        lastLoadedPDFKey = nil
    }

    // Index words and group them by 8
    private func indexWordsAndGroups() {
        wordOffsets = []
        wordGroups = []
        let nsText = extractedText as NSString
        let wordRegex = try! NSRegularExpression(pattern: "\\b\\w+\\b", options: [])
        let matches = wordRegex.matches(in: extractedText, options: [], range: NSRange(location: 0, length: nsText.length))
        for (i, match) in matches.enumerated() {
            let wordRange = (start: match.range.location, end: match.range.location + match.range.length)
            wordOffsets.append(wordRange)
        }
        // Group words by 8
        var group: [Int] = []
        for (i, _) in wordOffsets.enumerated() {
            group.append(i)
            if group.count == 8 {
                wordGroups.append(group)
                group = []
            }
        }
        if !group.isEmpty {
            wordGroups.append(group)
        }
    }

    // MARK: - Text-to-Speech
    private func startSpeaking() {
        startSpeaking(fromGroup: 0)
    }

    private func startSpeaking(fromGroup groupIdx: Int) {
        guard !extractedText.isEmpty else { return }
        isSpeaking = true // Set immediately so controls stay visible
        guard groupIdx < wordGroups.count else { return }
        let startWordIdx = wordGroups[groupIdx].first ?? 0
        let startChar = wordOffsets[startWordIdx].start
        let utterText = String(extractedText[extractedText.index(extractedText.startIndex, offsetBy: startChar)...])
        let utterance = AVSpeechUtterance(string: utterText)
        // Always use Daniel (en-GB)
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Daniel-compact") ?? AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        let delegate = SpeechDelegate(
            onFinish: {
                if let jumpGroup = pendingGroupJump {
                    pendingGroupJump = nil
                    startSpeaking(fromGroup: jumpGroup)
                } else {
                    isSpeaking = false
                    isPaused = false
                    spokenGroup = nil
                }
            },
            onPause: { isPaused = true },
            onContinue: { isPaused = false },
            onCharSpoken: { range in
                DispatchQueue.main.async {
                    // Find which group contains the start of the spoken range (offset by startChar)
                    let charIdx = range.location + startChar
                    if let wordIdx = wordOffsets.firstIndex(where: { $0.start <= charIdx && charIdx < $0.end }) {
                        if let groupIdx = wordGroups.firstIndex(where: { $0.contains(wordIdx) }) {
                            spokenGroup = groupIdx
                            saveBookmark()
                        }
                    }
                }
            }
        )
        self.speechDelegate = delegate
        synthesizer.delegate = delegate
        synthesizer.speak(utterance)
        isPaused = false
        spokenGroup = groupIdx
        saveBookmark()
    }

    private func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    private func resumeSpeaking() {
        synthesizer.continueSpeaking()
        isPaused = false
    }

    private func restartFromBeginning() {
        stopSpeaking()
        spokenGroup = nil
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pdf], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}

class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onFinish: () -> Void
    let onPause: () -> Void
    let onContinue: () -> Void
    let onCharSpoken: ((NSRange) -> Void)?

    init(onFinish: @escaping () -> Void, onPause: @escaping () -> Void, onContinue: @escaping () -> Void, onCharSpoken: ((NSRange) -> Void)? = nil) {
        self.onFinish = onFinish
        self.onPause = onPause
        self.onContinue = onContinue
        self.onCharSpoken = onCharSpoken
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        onPause()
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        onContinue()
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        onCharSpoken?(characterRange)
    }
}
