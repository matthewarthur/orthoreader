//
//  orthoreaderApp.swift
//  orthoreader
//
//  Created by Matt Arthur on 7/17/25.
//

import SwiftUI
import AVFoundation

@main
struct orthoreaderApp: App {
    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
