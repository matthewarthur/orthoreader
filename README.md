# OrthoReader iOS App

## Current Status: PAUSED DEVELOPMENT

### What's Working:
- ✅ PDF library with author/title organization
- ✅ Text-to-speech with play/pause/resume/restart
- ✅ Word-level highlighting during TTS
- ✅ Progress bar with tap-to-jump functionality
- ✅ Per-PDF bookmarking
- ✅ Background audio support
- ✅ Navigation between home, library, and reading views

### Known Issues:
- Large PDFs (>100,000 characters) are limited to first portion for performance
- Some UI responsiveness issues after navigation (partially fixed)

### File Structure:
```
orthoreader/
├── ContentView.swift (main app logic)
├── Assets.xcassets/
└── LibraryPDFs/ (PDF library)
    ├── St John Chrysostom/
    ├── St Isaac the Syrian/
    └── [other authors]/
```

### To Resume Development:
1. Open `orthoreader.xcodeproj` in Xcode
2. Build and run on iOS Simulator or device
3. Add PDFs to LibraryPDFs folder as blue folder references

### Last Updated: [Current Date]
