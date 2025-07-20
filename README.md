# OrthoReader 📚

An iOS app for reading and listening to early Christian texts and Orthodox literature with advanced text-to-speech capabilities. Also supports generic PDF to voice using native text-to-speech.

## Features ✨

### 📖 **Smart PDF Reading**
- **Organized Library**: Browse texts by author and century
- **Text-to-Speech**: High-quality British English narration
- **Word-Level Highlighting**: Follow along as text is read aloud
- **Progress Tracking**: Visual progress bar with tap-to-jump navigation
- **Automatic Bookmarking**: Resume reading from where you left off

### 🎧 **Audio Controls**
- **Play/Pause/Resume**: Full control over audio playback
- **Restart**: Begin reading from the beginning
- **Background Audio**: Continue listening while using other apps
- **Manual Navigation**: Tap any text section to jump to that position

### 📱 **Modern UI**
- **Three-Screen Navigation**: Home, Library, and Reading views
- **Responsive Design**: Optimized for iPhone and iPad
- **Visual Feedback**: Highlighted text during speech
- **Intuitive Controls**: Easy-to-use interface for all ages

## Library Contents 📚

The app includes a curated collection of early Christian texts:

- **First Century**: Early Christian writings
- **Second Century**: Patristic literature
- **Third Century**: Church Fathers
- **St John Chrysostom**: Homilies and teachings
- **St Isaac the Syrian**: Spiritual writings
- **St Gregory Nazianzen**: Theological works
- **St Basil the Great**: Church writings
- **St Ambrose**: Western Church Fathers
- **St Augustine**: Confessions and other works
- **St Jerome**: Biblical commentaries

## Installation 🚀

### Prerequisites
- macOS with Xcode 15.0 or later
- iOS 18.5 or later (for deployment)
- Apple Developer Account (for device testing)

### Setup
1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/orthoreader.git
   cd orthoreader
   ```

2. **Open in Xcode**
   ```bash
   open orthoreader/orthoreader.xcodeproj
   ```

3. **Build and Run**
   - Select your target device (iPhone/iPad or Simulator)
   - Press `Cmd + R` to build and run

### Device Installation
1. Connect your iPhone/iPad to your Mac
2. Select your device in Xcode's device picker
3. Sign the app with your Apple ID in "Signing & Capabilities"
4. Build and run - the app will install on your device

## Usage 📖

### Getting Started
1. **Launch the app** - You'll see the home screen with three main options
2. **Access Library** - Tap "Library" to browse available texts
3. **Select a Text** - Choose from the organized collection by author
4. **Start Reading** - Use "Read Aloud" to begin text-to-speech

### Reading Controls
- **Play/Pause**: Control audio playback
- **Progress Bar**: Tap to jump to any position
- **Text Selection**: Tap any paragraph to start reading from there
- **Navigation**: Use Library and Home buttons to switch views

### Bookmarking
- **Automatic**: Your position is saved as you read
- **Manual**: Tap text sections to bookmark specific positions
- **Resume**: Return to your last position when reopening a text

## Technical Details 🔧

### Architecture
- **SwiftUI**: Modern declarative UI framework
- **AVFoundation**: Text-to-speech and audio management
- **PDFKit**: PDF text extraction and processing
- **UserDefaults**: Bookmark persistence

### Key Components
- `ContentView.swift`: Main app interface and navigation
- `PDFReaderViewModel`: Text processing and speech management
- `PDFLibraryView`: Library browsing interface
- `SpeechDelegate`: Audio playback coordination

### Performance Optimizations
- **Text Processing**: Limited to first 100,000 characters for large PDFs
- **Word Grouping**: Text organized into 8-word groups for natural reading
- **Memory Management**: Efficient text extraction and storage

## Development Status 🚧

### ✅ Completed Features
- Core text-to-speech functionality
- PDF library organization
- Bookmark system
- Navigation between views
- Background audio support
- Progress tracking

### 🔄 In Progress
- UI refinements and responsiveness improvements
- Additional text processing optimizations

### 📋 Future Enhancements
- Custom voice selection
- Reading speed controls
- Text size adjustment
- Dark mode support
- Cloud sync for bookmarks

## Contributing 🤝

Contributions are welcome! Please feel free to submit issues and pull requests.

### Development Setup
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License 📄

This project is open source. Please check individual PDF files for their respective copyright status.

## Acknowledgments 🙏

- **Text Sources**: Early Christian texts from public domain sources
- **Icons**: Orthodox cross icon from [Wilcox Iconography](https://wilcoxiconography.pythonanywhere.com/)
- **Audio**: Apple's built-in text-to-speech engine

## Support 💬

If you encounter any issues or have questions or want to submit additional PDFs:
1. Check the existing issues in this repository
2. Create a new issue with detailed information
3. Include device model, iOS version, and steps to reproduce

---

**OrthoReader** - Bringing ancient wisdom to modern ears 📚🎧
