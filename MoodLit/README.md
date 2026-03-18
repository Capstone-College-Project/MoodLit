# MoodLit — Swift File Setup Guide

## Folder Structure

Drop the following folders directly into your Xcode project:

```
MoodLit/
├── Models/
│   └── Models.swift            ← All data models (Book, Chapter, SceneTag, Playlist…)
├── Managers/
│   ├── LibraryManager.swift    ← Book storage, import, persistence
│   ├── MusicEngine.swift       ← Playback, crossfade, scene-driven track switching
│   └── LineTracker.swift       ← Marker position + reading progress tracking
├── Parsers/
│   ├── EpubParser.swift        ← Unzips & parses .epub files
│   └── OPFParser.swift         ← Reads OPF manifest XML (title, author, spine)
├── Views/
│   ├── Library.swift           ← Library screen + BookCard + file picker
│   └── BookReaderView.swift    ← Reader screen + MarkerView + LineView
└── Extensions/
    └── Colors.swift            ← All app color tokens + hex initializer
```

---

## Step 1 — Add ZIPFoundation

EpubParser requires ZIPFoundation to unzip .epub files.

1. In Xcode: **File → Add Package Dependencies**
2. Paste: `https://github.com/weichsel/ZIPFoundation`
3. Version rule: **Up to Next Major** from `0.9.0`
4. Add to your app target

---

## Step 2 — Register the ePub file type

In your `Info.plist` (or via the target editor), add:

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>ePub Document</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>org.idpf.epub-container</string>
        </array>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
    </dict>
</array>

<key>UTImportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>org.idpf.epub-container</string>
        <key>UTTypeDescription</key>
        <string>ePub Document</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.data</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>epub</string>
            </array>
        </dict>
    </dict>
</array>
```

---

## Step 3 — Create a placeholder GutenbergSearchView

The Library view references `GutenbergSearchView()`. Add a placeholder until you build it:

```swift
struct GutenbergSearchView: View {
    var body: some View {
        Text("Gutenberg Search — Coming Soon")
            .foregroundColor(Color.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bg.ignoresSafeArea())
    }
}
```

---

## Step 4 — Set your entry point

In your `App.swift`:

```swift
import SwiftUI

@main
struct MoodLitApp: App {
    var body: some Scene {
        WindowGroup {
            Library()
        }
    }
}
```

---

## Step 5 — Add music files (optional for now)

Place any `.mp3` or `.m4a` tracks in your Xcode project bundle.
The `MusicEngine` looks them up by file name using `Bundle.main.url(forResource:withExtension:)`.

Name them to match whatever `musicName` strings your AI backend returns in `SceneTag`.

---

## How It All Connects

```
User taps "Upload"
    → fileImporter opens iOS Files app
    → User picks .epub
    → EpubParser unzips + strips HTML → lines
    → OPFParser reads title, author, chapter order
    → Book saved to LibraryManager (persisted to disk)
    → BookCard appears in Library grid

User opens book
    → BookReaderView loads
    → Lines rendered in LazyVStack
    → MarkerView overlaid — gold line user can drag or auto-scroll
    → Each frame: LineTracker checks which line marker is over
    → On line change: MusicEngine checks SceneTags
    → Matching tag found → crossfade to correct track at correct intensity
    → On close: reading progress saved back to LibraryManager
```

---

## What's Left to Build

| Feature | File to create |
|---|---|
| Gutenberg search + download | `GutenbergSearchView.swift` |
| Scene Map visualization | `SceneMapView.swift` |
| Playlist editor | `PlaylistView.swift` + `EditPlaylistView.swift` |
| Settings screen | `SettingsView.swift` |
| AI scene tagging | Backend API + `SceneTaggingService.swift` |
| Playlist manager | `PlaylistManager.swift` (mirrors LibraryManager pattern) |
