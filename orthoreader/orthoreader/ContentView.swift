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
                ScrollView {
                    Text(extractedText)
                        .padding()
                }
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
    }

    private func loadSamplePDF() {
        if let url = Bundle.main.url(forResource: "sample", withExtension: "pdf") {
            extractText(from: url)
        } else {
            errorMessage = "Sample PDF not found in app bundle."
        }
    }

    // MARK: - Text-to-Speech
    private func startSpeaking() {
        guard !synthesizer.isSpeaking, !extractedText.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: extractedText)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        let delegate = SpeechDelegate(
            onFinish: { isSpeaking = false; isPaused = false },
            onPause: { isPaused = true },
            onContinue: { isPaused = false },
            onCharSpoken: nil
        )
        self.speechDelegate = delegate
        synthesizer.delegate = delegate
        synthesizer.speak(utterance)
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

    private func restartFromBeginning() {
        stopSpeaking()
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
}
