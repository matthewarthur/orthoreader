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
import MediaPlayer

struct ContentView: View {
    @State private var isPickerPresented = false
    @State private var extractedText: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSpeaking = false
    @State private var isPaused = false
    @State private var speechDelegate: SpeechDelegate? = nil
    @State private var currentPDFTitle: String = "Sample PDF"
    @State private var words: [String] = []
    @State private var currentWordIndex: Int = 0
    @State private var currentCharOffset: Int = 0
    @State private var paragraphs: [String] = []
    @State private var currentParagraphIndex: Int = 0
    @State private var lineStartOffsets: [Int] = []
    private let charProgressKeyPrefix = "PDFCharProgress_"
    
    private let synthesizer = AVSpeechSynthesizer()
    private let progressKeyPrefix = "PDFWordProgress_"
    
    var body: some View {
        VStack {
            Button(action: {
                isPickerPresented = true
            }) {
                Label("Select PDF", systemImage: "doc.text")
            }
            .padding()
            
            Button(action: {
                loadSamplePDF()
            }) {
                Label("Load Sample PDF", systemImage: "doc.richtext")
            }
            .padding(.bottom)
            
            if !extractedText.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(paragraphs.indices, id: \.self) { idx in
                                Text(paragraphs[idx])
                                    .padding(8)
                                    .background(idx == currentParagraphIndex ? Color.yellow.opacity(0.3) : Color.clear)
                                    .cornerRadius(8)
                                    .id(idx)
                            }
                        }
                        .padding()
                        .onChange(of: currentParagraphIndex) { newIdx in
                            DispatchQueue.main.async {
                                withAnimation {
                                    proxy.scrollTo(newIdx, anchor: .center)
                                }
                            }
                        }
                    }
                }
                HStack {
                    Button(action: {
                        if isSpeaking {
                            stopSpeaking()
                        } else {
                            startSpeaking()
                        }
                    }) {
                        Label(playButtonLabel, systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                    }
                    .padding(.trailing)
                    .disabled(extractedText.isEmpty)
                    
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
        // Set the PDF title for Now Playing info
        currentPDFTitle = url.deletingPathExtension().lastPathComponent
        // Load saved progress
        currentCharOffset = loadCharProgress(for: currentPDFTitle)
        // Split into lines (finer granularity for highlighting/scrolling)
        paragraphs = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        // Precompute line start offsets
        lineStartOffsets = []
        var offset = 0
        for para in paragraphs {
            lineStartOffsets.append(offset)
            offset += para.count + 1 // +1 for the newline
        }
        // Find the current paragraph index
        currentParagraphIndex = paragraphIndex(for: currentCharOffset)
    }
    
    private func loadSamplePDF() {
        if let url = Bundle.main.url(forResource: "sample", withExtension: "pdf") {
            extractText(from: url)
        } else {
            errorMessage = "Sample PDF not found in app bundle."
        }
    }
    
    // Computed property for play button label
    private var playButtonLabel: String {
        let wordsList = extractedText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let wordsHeard = extractedText.prefix(currentCharOffset).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        if !isSpeaking && wordsHeard >= 5 && currentCharOffset < extractedText.count {
            return "Resume"
        } else {
            return isSpeaking ? "Stop" : "Read Aloud"
        }
    }
    
    // MARK: - Text-to-Speech
    private func startSpeaking() {
        if currentCharOffset >= extractedText.count {
            currentCharOffset = 0
            saveCharProgress(for: currentPDFTitle, charOffset: 0)
        }
        guard !synthesizer.isSpeaking, currentCharOffset < extractedText.count else { return }
        let startIdx = extractedText.index(extractedText.startIndex, offsetBy: currentCharOffset)
        let textToSpeak = String(extractedText[startIdx...])
        let delegate = SpeechDelegate(
            onFinish: { isSpeaking = false; isPaused = false; if currentCharOffset >= extractedText.count { saveCharProgress(for: currentPDFTitle, charOffset: 0); currentCharOffset = 0; currentParagraphIndex = 0 } },
            onPause: { isPaused = true },
            onContinue: { isPaused = false },
            onCharSpoken: { range in
                let newOffset = currentCharOffset + range.location + range.length
                if newOffset <= extractedText.count {
                    currentCharOffset = newOffset
                    saveCharProgress(for: currentPDFTitle, charOffset: currentCharOffset)
                    // Find the line index for the start of the spoken range
                    let globalChar = currentCharOffset + range.location
                    if let idx = lineStartOffsets.lastIndex(where: { $0 <= globalChar }) {
                        if idx != currentParagraphIndex {
                            currentParagraphIndex = idx
                        }
                    }
                }
            }
        )
        self.speechDelegate = delegate
        synthesizer.delegate = delegate
        updateNowPlayingInfo(title: currentPDFTitle)
        synthesizer.speak(AVSpeechUtterance(string: textToSpeak))
        isSpeaking = true
        isPaused = false
    }
    
    private func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
    }
    
    private func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }
    
    private func resumeSpeaking() {
        synthesizer.continueSpeaking()
        isPaused = false
    }
    
    private func updateNowPlayingInfo(title: String, artist: String? = nil) {
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: title
        ]
        if let artist = artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func saveProgress(for pdfTitle: String, wordIndex: Int) {
        let key = progressKeyPrefix + pdfTitle
        UserDefaults.standard.set(wordIndex, forKey: key)
    }
    
    private func loadProgress(for pdfTitle: String) -> Int {
        let key = progressKeyPrefix + pdfTitle
        return UserDefaults.standard.integer(forKey: key)
    }
    
    private func saveCharProgress(for pdfTitle: String, charOffset: Int) {
        let key = charProgressKeyPrefix + pdfTitle
        UserDefaults.standard.set(charOffset, forKey: key)
    }
    
    private func loadCharProgress(for pdfTitle: String) -> Int {
        let key = charProgressKeyPrefix + pdfTitle
        return UserDefaults.standard.integer(forKey: key)
    }
    
    // Find the paragraph index for a given character offset
    private func paragraphIndex(for charOffset: Int) -> Int {
        var total = 0
        for (i, para) in paragraphs.enumerated() {
            total += para.count + 1 // +1 for the newline separator
            if charOffset < total {
                return i
            }
        }
        return max(0, paragraphs.count - 1)
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

// Add a speech delegate class to handle state updates
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

// #Preview {
//     ContentView()
// }
