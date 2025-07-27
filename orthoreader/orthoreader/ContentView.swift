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

// PDFInfo struct for library
struct PDFInfo: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let author: String
    let url: URL
}

// SheetID for robust sheet presentation
struct SheetID: Identifiable, Equatable {
    let id: UUID
}

enum AppScreen {
    case home
    case library
    case reading
}

class PDFReaderViewModel: ObservableObject {
    @Published var extractedText: String = ""
    @Published var errorMessage: String? = nil
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var wordOffsets: [(start: Int, end: Int)] = []
    @Published var wordGroups: [[Int]] = []
    @Published var selectedGroup: Int? = nil
    @Published var spokenGroup: Int? = nil
    @Published var pendingGroupJump: Int? = nil
    @Published var pdfBookmarkKey: String? = nil
    @Published var savedBookmarkGroup: Int? = nil
    @Published var lastLoadedPDFKey: String? = nil
    @Published var scrollToGroup: Int? = nil
    @Published var didLoadPDF: Bool = false
    private let synthesizer = AVSpeechSynthesizer()
    var speechDelegate: SpeechDelegate? = nil
    // Store current PDF metadata for Now Playing
    private(set) var currentPDFTitle: String = ""
    private(set) var currentPDFAuthor: String = ""

    init() {
        setupRemoteTransportControls()
    }

    func reset() {
        extractedText = ""
        errorMessage = nil
        isSpeaking = false
        isPaused = false
        wordOffsets = []
        wordGroups = []
        selectedGroup = nil
        spokenGroup = nil
        pendingGroupJump = nil
        pdfBookmarkKey = nil
        savedBookmarkGroup = nil
        lastLoadedPDFKey = nil
        scrollToGroup = nil
        didLoadPDF = false
    }

    func extractText(from url: URL) {
        print("=== extractText called for: \(url.lastPathComponent) ===")
        guard let pdf = PDFDocument(url: url) else {
            print("=== FAILED to open PDF: \(url.lastPathComponent) ===")
            errorMessage = "Failed to open PDF."
            return
        }
        print("=== Successfully opened PDF: \(url.lastPathComponent) ===")
        print("=== PDF page count: \(pdf.pageCount) ===")
        
        var text = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let pageText = page.string {
                text += pageText + "\n"
                print("=== Page \(i) text length: \(pageText.count) ===")
            } else {
                print("=== Page \(i) has no text ===")
            }
        }
        print("=== Total extracted text length: \(text.count) ===")
        extractedText = text
        
        // Set current PDF metadata for Now Playing
        currentPDFTitle = url.deletingPathExtension().lastPathComponent
        // Try to extract author from path if possible
        if let authorFolder = url.pathComponents.dropLast().last {
            currentPDFAuthor = authorFolder
        } else {
            currentPDFAuthor = ""
        }
        
        // Check if text is very large and show warning
        if text.count > 100000 {
            errorMessage = "Large PDF detected. Only the first portion will be processed for performance."
        } else {
            errorMessage = nil
        }
        
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
        didLoadPDF = true
        print("=== extractText completed for: \(url.lastPathComponent) ===")
    }

    func indexWordsAndGroups() {
        print("=== indexWordsAndGroups called ===")
        print("=== Text length: \(extractedText.count) ===")
        wordOffsets = []
        wordGroups = []
        
        // For very large texts, limit processing to first 100,000 characters to prevent freezing
        let maxTextLength = 100000
        let textToProcess = extractedText.count > maxTextLength ? String(extractedText.prefix(maxTextLength)) : extractedText
        print("=== Processing text of length: \(textToProcess.count) ===")
        
        let nsText = textToProcess as NSString
        let wordRegex = try! NSRegularExpression(pattern: "\\b\\w+\\b", options: [])
        let matches = wordRegex.matches(in: textToProcess, options: [], range: NSRange(location: 0, length: nsText.length))
        print("=== Found \(matches.count) word matches ===")
        
        // Limit to first 10,000 words to prevent memory issues
        let maxWords = 10000
        let wordsToProcess = min(matches.count, maxWords)
        print("=== Processing \(wordsToProcess) words ===")
        
        for i in 0..<wordsToProcess {
            let match = matches[i]
            let wordRange = (start: match.range.location, end: match.range.location + match.range.length)
            wordOffsets.append(wordRange)
        }
        print("=== Created \(wordOffsets.count) word offsets ===")
        
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
        print("=== Created \(wordGroups.count) word groups ===")
        print("=== indexWordsAndGroups completed ===")
    }

    func startSpeaking() {
        startSpeaking(fromGroup: 0)
    }

    func startSpeaking(fromGroup groupIdx: Int) {
        guard !extractedText.isEmpty else { return }
        isSpeaking = true
        guard groupIdx < wordGroups.count else { return }
        let startWordIdx = wordGroups[groupIdx].first ?? 0
        let startChar = wordOffsets[startWordIdx].start
        let utterText = String(extractedText[extractedText.index(extractedText.startIndex, offsetBy: startChar)...])
        let utterance = AVSpeechUtterance(string: utterText)
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Daniel-compact") ?? AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        let delegate = SpeechDelegate(
            onFinish: { [weak self] in
                guard let self = self else { return }
                if let jumpGroup = self.pendingGroupJump {
                    self.pendingGroupJump = nil
                    self.startSpeaking(fromGroup: jumpGroup)
                } else {
                    self.isSpeaking = false
                    self.isPaused = false
                    self.spokenGroup = nil
                }
            },
            onPause: { [weak self] in self?.isPaused = true },
            onContinue: { [weak self] in self?.isPaused = false },
            onCharSpoken: { [weak self] range in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    let charIdx = range.location + startChar
                    if let wordIdx = self.wordOffsets.firstIndex(where: { $0.start <= charIdx && charIdx < $0.end }) {
                        if let groupIdx = self.wordGroups.firstIndex(where: { $0.contains(wordIdx) }) {
                            self.spokenGroup = groupIdx
                            self.saveBookmark()
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
        // Update Now Playing Info
        updateNowPlayingInfo(title: currentPDFTitle, author: currentPDFAuthor, isPlaying: true)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
        // Update Now Playing Info
        updateNowPlayingInfo(title: currentPDFTitle, author: currentPDFAuthor, isPlaying: false)
    }

    func resumeSpeaking() {
        synthesizer.continueSpeaking()
        isPaused = false
        // Update Now Playing Info
        updateNowPlayingInfo(title: currentPDFTitle, author: currentPDFAuthor, isPlaying: true)
    }

    func restartFromBeginning() {
        stopSpeaking()
        spokenGroup = nil
    }

    func saveBookmark() {
        guard let key = pdfBookmarkKey, let group = spokenGroup else { return }
        UserDefaults.standard.setValue(group, forKey: key)
        savedBookmarkGroup = group
    }

    func clearBookmark() {
        if let key = lastLoadedPDFKey {
            UserDefaults.standard.removeObject(forKey: key)
        }
        savedBookmarkGroup = nil
        pdfBookmarkKey = nil
        lastLoadedPDFKey = nil
    }

    // MARK: - Now Playing Info & Remote Controls
    func updateNowPlayingInfo(title: String, author: String, isPlaying: Bool) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = author
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        // Add artwork (app icon)
        if let icon = UIImage(named: "NowPlayingIcon") {
            let artwork = MPMediaItemArtwork(boundsSize: icon.size) { _ in icon }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] event in
            self?.resumeSpeaking()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] event in
            self?.pauseSpeaking()
            return .success
        }
    }
}

struct ContentView: View {
    @State private var isPickerPresented = false
    @State private var showLibrary = false
    @State private var library: [String: [PDFInfo]] = [:]
    @State private var librarySheetID: SheetID? = nil
    @State private var selectedPDF: PDFInfo? = nil
    @State private var pdfSelectionCounter = 0
    @State private var showLibraryNav = false
    @State private var appScreen: AppScreen = .home
    @State private var libraryViewKey = UUID()
    @State private var currentPDFID: UUID? = nil
    @StateObject var readerVM = PDFReaderViewModel()
    
    // MARK: - Computed Views
    private var homeView: some View {
        ZStack {
            // Show background image only when no PDF is loaded
            if readerVM.extractedText.isEmpty {
                Image("LaunchBackground")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }
            VStack {
                Spacer().frame(height: 32)
                // Large, prominent Library button
                Button(action: {
                    print("Home: Library button tapped")
                    readerVM.reset()
                    libraryViewKey = UUID()
                    appScreen = .library
                }) {
                    Label("Library", systemImage: "books.vertical")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .disabled(library.isEmpty)

                Spacer()

                // Lower third: Select PDF and Load Sample PDF buttons side by side
                VStack(spacing: 20) {
                    Button(action: {
                        print("Home: Select PDF button tapped")
                        isPickerPresented = true
                    }) {
                        Label("Select PDF", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(readerVM.isSpeaking)

                    Button(action: {
                        print("Home: Load Sample PDF button tapped")
                        loadSamplePDF()
                    }) {
                        Label("Load Sample PDF", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(readerVM.isSpeaking)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)

                Spacer()

                // About This Icon button at the bottom
                Button(action: {
                    if let url = URL(string: "https://wilcoxiconography.pythonanywhere.com/") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("About This Icon")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .padding(.bottom, 16)
            }
        }
    }
    
    private var libraryView: some View {
        PDFLibraryView(library: library, selectedPDF: $selectedPDF, pdfSelectionCounter: $pdfSelectionCounter, currentPDFID: $currentPDFID, onHome: {
            print("Library: Home button tapped")
            // Reset all relevant state when going home
            readerVM.reset()
            selectedPDF = nil
            pdfSelectionCounter = 0
            currentPDFID = nil
            showLibrary = false
            showLibraryNav = false
            libraryViewKey = UUID()
            readerVM.isSpeaking = false
            readerVM.isPaused = false
            readerVM.pendingGroupJump = nil
            appScreen = .home
        })
        .id(libraryViewKey)
    }
    
    private var readingView: some View {
        VStack {
            // Prominently display currently spoken text when TTS is active
            if readerVM.isSpeaking, let groupIdx = readerVM.spokenGroup, groupIdx < readerVM.wordGroups.count {
                let group = readerVM.wordGroups[groupIdx]
                let start = readerVM.wordOffsets[group.first ?? 0].start
                let end = readerVM.wordOffsets[group.last ?? 0].end
                let textRange = readerVM.extractedText.index(readerVM.extractedText.startIndex, offsetBy: start)..<readerVM.extractedText.index(readerVM.extractedText.startIndex, offsetBy: end)
                let groupText = String(readerVM.extractedText[textRange])
                Text(groupText)
                    .padding()
                    .background(Color.yellow.opacity(0.4))
                    .cornerRadius(8)
                    .font(.title3.bold())
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            // Resume button if bookmark exists and not currently speaking
            if let savedGroup = readerVM.savedBookmarkGroup, !readerVM.isSpeaking {
                Button(action: {
                    print("Reading: Resume button tapped")
                    readerVM.startSpeaking(fromGroup: savedGroup)
                }) {
                    Label("Resume from last position", systemImage: "bookmark.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.top, 4)
            }
            // Progress Indicator
            if readerVM.wordGroups.count > 0 {
                let progress = readerVM.spokenGroup != nil ? Double(readerVM.spokenGroup! + 1) / Double(readerVM.wordGroups.count) : 0.0
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
                                print("Reading: Progress bar tapped")
                                let rel = location.x / geo.size.width
                                let groupIdx = min(max(Int(rel * Double(readerVM.wordGroups.count)), 0), readerVM.wordGroups.count - 1)
                                // Save bookmark when user jumps to a position via progress bar
                                readerVM.spokenGroup = groupIdx
                                readerVM.saveBookmark()
                                if readerVM.isSpeaking {
                                    readerVM.pendingGroupJump = groupIdx
                                    readerVM.stopSpeaking()
                                } else {
                                    readerVM.startSpeaking(fromGroup: groupIdx)
                                }
                                // Scroll to the selected group
                                readerVM.scrollToGroup = groupIdx
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
                        ForEach(readerVM.wordGroups.indices, id: \.self) { groupIdx in
                            let group = readerVM.wordGroups[groupIdx]
                            let start = readerVM.wordOffsets[group.first ?? 0].start
                            let end = readerVM.wordOffsets[group.last ?? 0].end
                            let textRange = readerVM.extractedText.index(readerVM.extractedText.startIndex, offsetBy: start)..<readerVM.extractedText.index(readerVM.extractedText.startIndex, offsetBy: end)
                            let groupText = String(readerVM.extractedText[textRange])
                            let isHighlighted = readerVM.selectedGroup == groupIdx || readerVM.spokenGroup == groupIdx
                                                            Button(action: {
                                    print("Reading: Text group button tapped: groupIdx=\(groupIdx)")
                                    readerVM.selectedGroup = groupIdx
                                    // Save bookmark when user manually selects a position
                                    readerVM.spokenGroup = groupIdx
                                    readerVM.saveBookmark()
                                    if readerVM.isSpeaking {
                                        readerVM.pendingGroupJump = groupIdx
                                        readerVM.stopSpeaking()
                                    } else {
                                        readerVM.startSpeaking(fromGroup: groupIdx)
                                    }
                                    // Scroll to the selected group
                                    readerVM.scrollToGroup = groupIdx
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
                .scrollIndicators(.visible, axes: .vertical)
                .onChange(of: readerVM.spokenGroup) { newGroup in
                    if let group = newGroup {
                        withAnimation {
                            scrollProxy.scrollTo(group, anchor: .center)
                        }
                    }
                }
                .onChange(of: readerVM.scrollToGroup) { group in
                    if let group = group {
                        withAnimation {
                            scrollProxy.scrollTo(group, anchor: .center)
                        }
                        readerVM.scrollToGroup = nil
                    }
                }
            }
            // Move controls here so they are always visible
            HStack {
                if !readerVM.isSpeaking {
                    Button(action: {
                        print("Reading: Read Aloud button tapped")
                        readerVM.startSpeaking()
                    }) {
                        Label("Read Aloud", systemImage: "speaker.wave.2.fill")
                    }
                    .padding(.trailing)
                    .disabled(readerVM.extractedText.isEmpty)
                }
                if readerVM.isSpeaking {
                    Button(action: {
                        print("Reading: Pause/Resume button tapped")
                        if readerVM.isPaused {
                            readerVM.resumeSpeaking()
                        } else {
                            readerVM.pauseSpeaking()
                        }
                    }) {
                        Label(readerVM.isPaused ? "Resume" : "Pause", systemImage: readerVM.isPaused ? "play.fill" : "pause.fill")
                    }
                    Button(action: {
                        print("Reading: Restart button tapped")
                        readerVM.restartFromBeginning()
                    }) {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(readerVM.extractedText.isEmpty)
                }
            }
            .padding(.bottom)
            HStack {
                Button(action: {
                    print("Reading: Library button tapped")
                    // Save current position before leaving
                    if let currentGroup = readerVM.spokenGroup ?? readerVM.selectedGroup {
                        readerVM.spokenGroup = currentGroup
                        readerVM.saveBookmark()
                    }
                    // Library button in reading view
                    readerVM.reset()
                    readerVM.stopSpeaking()
                    readerVM.clearBookmark()
                    readerVM.extractedText = ""
                    readerVM.errorMessage = nil
                    readerVM.wordOffsets = []
                    readerVM.wordGroups = []
                    readerVM.selectedGroup = nil
                    readerVM.spokenGroup = nil
                    readerVM.pendingGroupJump = nil
                    readerVM.isPaused = false
                    readerVM.isSpeaking = false
                    showLibrary = false
                    showLibraryNav = false
                    selectedPDF = nil
                    pdfSelectionCounter = 0
                    currentPDFID = nil
                    libraryViewKey = UUID()
                    appScreen = .library
                }) {
                    Label("Library", systemImage: "books.vertical")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: {
                    print("Reading: Home button tapped")
                    // Save current position before leaving
                    if let currentGroup = readerVM.spokenGroup ?? readerVM.selectedGroup {
                        readerVM.spokenGroup = currentGroup
                        readerVM.saveBookmark()
                    }
                    // Home button in reading view
                    readerVM.reset()
                    readerVM.stopSpeaking()
                    readerVM.clearBookmark()
                    readerVM.extractedText = ""
                    readerVM.errorMessage = nil
                    readerVM.wordOffsets = []
                    readerVM.wordGroups = []
                    readerVM.selectedGroup = nil
                    readerVM.spokenGroup = nil
                    readerVM.pendingGroupJump = nil
                    readerVM.isPaused = false
                    readerVM.isSpeaking = false
                    showLibrary = false
                    showLibraryNav = false
                    selectedPDF = nil
                    pdfSelectionCounter = 0
                    currentPDFID = nil
                    libraryViewKey = UUID()
                    appScreen = .home
                }) {
                    Label("Home", systemImage: "house")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    var body: some View {
        ZStack {
            if appScreen == .home {
                homeView
            } else if appScreen == .library {
                libraryView
            } else if appScreen == .reading {
                readingView
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            DocumentPicker { url in
                if let url = url {
                    readerVM.extractText(from: url)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Save bookmark when app goes to background
            if appScreen == .reading, let currentGroup = readerVM.spokenGroup ?? readerVM.selectedGroup {
                readerVM.spokenGroup = currentGroup
                readerVM.saveBookmark()
            }
        }
        .onChange(of: currentPDFID) { id in
            print("=== onChange currentPDFID triggered ===")
            print("currentPDFID: \(String(describing: id))")
            print("selectedPDF: \(String(describing: selectedPDF))")
            print("current appScreen: \(appScreen)")
            
            if let pdf = selectedPDF, id != nil {
                print("=== Starting PDF extraction ===")
                DispatchQueue.main.async {
                    print("=== Inside DispatchQueue.main.async ===")
                    // Reset reader state before loading new PDF
                    readerVM.extractedText = ""
                    readerVM.errorMessage = nil
                    readerVM.wordOffsets = []
                    readerVM.wordGroups = []
                    readerVM.selectedGroup = nil
                    readerVM.spokenGroup = nil
                    readerVM.pendingGroupJump = nil
                    readerVM.isPaused = false
                    readerVM.isSpeaking = false
                    showLibrary = false
                    showLibraryNav = false
                    libraryViewKey = UUID()
                    print("=== About to extract text from: \(pdf.url) ===")
                    readerVM.extractText(from: pdf.url)
                    selectedPDF = nil
                    // Directly navigate to reading view
                    print("=== Setting appScreen to .reading ===")
                    appScreen = .reading
                    print("=== appScreen set to .reading (after currentPDFID change) ===")
                }
            } else {
                print("=== No PDF selected or no ID ===")
            }
        }
        .onAppear {
            library = loadLibraryPDFs()
            // Debug: print all PDF resource paths in the bundle
            for resource in Bundle.main.paths(forResourcesOfType: "pdf", inDirectory: nil) {
                print("Bundle resource: \(resource)")
            }
            // Debug: print actual contents of the app bundle
            if let bundlePath = Bundle.main.resourcePath {
                print("Bundle resourcePath: \(bundlePath)")
                let fm = FileManager.default
                if let items = try? fm.contentsOfDirectory(atPath: bundlePath) {
                    for item in items {
                        print("Bundle item: \(item)")
                    }
                }
                // Check for LibraryPDFs folder
                let libraryPath = bundlePath + "/LibraryPDFs"
                if let authorFolders = try? fm.contentsOfDirectory(atPath: libraryPath) {
                    for author in authorFolders {
                        print("Author folder: \(author)")
                        let authorPath = libraryPath + "/\(author)"
                        if let pdfs = try? fm.contentsOfDirectory(atPath: authorPath) {
                            for pdf in pdfs {
                                print("PDF in \(author): \(pdf)")
                            }
                        }
                    }
                } else {
                    print("LibraryPDFs folder not found in bundle at runtime.")
                }
            }
            print("Library loaded: \(library)")
        }
    }
    
    // MARK: - PDF and Text Extraction
    private func loadSamplePDF() {
        if let url = Bundle.main.url(forResource: "sample", withExtension: "pdf") {
            readerVM.extractText(from: url)
        } else {
            readerVM.errorMessage = "Sample PDF not found in app bundle."
        }
    }
    
    // MARK: - PDF Library Loading
    private func loadLibraryPDFs() -> [String: [PDFInfo]] {
        var result: [String: [PDFInfo]] = [:]
        guard let bundlePath = Bundle.main.resourcePath else { return result }
        let libraryPath = bundlePath + "/LibraryPDFs"
        let fm = FileManager.default
        guard let authorFolders = try? fm.contentsOfDirectory(atPath: libraryPath) else {
            print("LibraryPDFs folder not found in bundle at runtime.")
            return result
        }
        for author in authorFolders {
            let authorPath = libraryPath + "/\(author)"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: authorPath, isDirectory: &isDir), isDir.boolValue {
                if let pdfs = try? fm.contentsOfDirectory(atPath: authorPath) {
                    for pdf in pdfs where pdf.hasSuffix(".pdf") {
                        let pdfPath = authorPath + "/\(pdf)"
                        let url = URL(fileURLWithPath: pdfPath)
                        let title = pdf.replacingOccurrences(of: ".pdf", with: "")
                        print("Parsed author: \(author), title: \(title), url: \(url)")
                        let info = PDFInfo(title: title, author: author, url: url)
                        result[author, default: []].append(info)
                    }
                }
            }
        }
        // Sort PDFs by title for each author
        for author in result.keys {
            result[author]?.sort { $0.title < $1.title }
        }
        return result
    }
    
    private func extractTextAndShow(pdf: PDFInfo) {
        readerVM.extractText(from: pdf.url)
        appScreen = .reading
        print("appScreen set to .reading (after extractText)")
    }
}

// Move helper types outside ContentView
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

struct PDFLibraryView: View {
    let library: [String: [PDFInfo]]
    @Binding var selectedPDF: PDFInfo?
    @Binding var pdfSelectionCounter: Int
    @Binding var currentPDFID: UUID?
    let onHome: () -> Void
    var body: some View {
        NavigationView {
            List {
                ForEach(library.keys.sorted(), id: \.self) { author in
                    Section(header: Text(author)) {
                        ForEach(library[author] ?? []) { pdf in
                            Button(pdf.title) {
                                print("=== PDF tapped in library ===")
                                print("PDF title: \(pdf.title)")
                                print("PDF ID: \(pdf.id)")
                                print("Before setting - selectedPDF: \(String(describing: selectedPDF))")
                                print("Before setting - currentPDFID: \(String(describing: currentPDFID))")
                                selectedPDF = pdf
                                pdfSelectionCounter += 1
                                currentPDFID = pdf.id
                                print("After setting - selectedPDF: \(String(describing: selectedPDF))")
                                print("After setting - currentPDFID: \(String(describing: currentPDFID))")
                            }
                        }
                    }
                }
            }
            .navigationTitle("PDF Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { onHome() }) {
                        Label("Home", systemImage: "house")
                    }
                }
            }
            .onAppear {
                print("PDFLibraryView received library: \(library)")
            }
        }
    }
}
