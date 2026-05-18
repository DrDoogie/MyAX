# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**MyAX / MeetingRecorder** is a privacy-first, AI-powered meeting recorder written entirely in Swift with no external dependencies. It records audio, transcribes speech on-device using Apple's Speech framework, then sends the structured transcript to the Anthropic Claude API to produce organized meeting notes. Notes are stored locally and can be exported to Apple Notes.

Supported delivery formats: standalone macOS app (no Xcode GUI required), iOS/iPadOS Xcode project, Swift Playgrounds `.swiftpm`, and a two-file "EasyInstall" variant.

## Build Commands

### macOS (no Xcode required)
```bash
cd MeetingRecorder/App
./build.sh                      # Compiles, signs, and produces MeetingRecorder.app
./set-api-key.sh sk-ant-xxx     # Stores Anthropic API key in macOS Keychain
open MeetingRecorder.app
```

### iOS
Open `MeetingRecorder/iOS/MeetingRecorder.xcodeproj` in Xcode, set your development team, connect a device, and press ⌘R.

### Swift Package (library/tests)
```bash
cd MeetingRecorder
swift build
swift test
swift test --filter MeetingRecorderTests.SpecificTestName   # single test
```

### Swift Playgrounds / EasyInstall
Copy `MeetingRecorder/EasyInstall/FILE1.swift` and `FILE2.swift` into the target playground or project.

## Architecture

```
MeetingRecorder/
├── Sources/MeetingRecorder/      # Shared library (SPM target)
│   ├── App/                      # SwiftUI @main entry point
│   ├── Models/Meeting.swift      # All data structures
│   ├── Services/                 # Business logic & integrations
│   └── Views/                    # SwiftUI screens
├── App/                          # macOS standalone (build.sh)
├── iOS/                          # Xcode project
├── SwiftPlaygrounds/             # .swiftpm package
└── EasyInstall/                  # Two-file distro
```

### Data Flow

1. `RecordingView` → `MeetingViewModel` starts `AudioRecordingService` (records to M4A in `~/Library/Application Support/MeetingRecorder/Recordings/`)
2. On stop → `TranscriptionService` runs `SFSpeechRecognizer` **on-device** (`requiresOnDeviceRecognition = true`, falls back to network only if model unavailable)
3. Transcript → `ClaudeAPIService.structureMeetingNotes()` — sends text to `claude-sonnet-4-6`, receives structured JSON
4. Result parsed into `MeetingNotes` → `StorageService.shared` persists to `meetings.json`
5. Optionally exported to Apple Notes via `AppleNotesService` (AppleScript on macOS, share sheet on iOS)

### Key Types (`Models/Meeting.swift`)

- `Meeting` — core record: id, title, date, duration, transcript, notes, categories, `MeetingStatus`
- `MeetingNotes` — structured output: summary, `[TopicSummary]`, `[Directive]`, `[Suggestion]`, `[MindMapNode]`, `[GraphEdge]`
- `Directive` — action item with assignee, deadline, priority
- `MindMapNode` — tree node typed as root/topic/subtopic/action/decision
- `GraphEdge` — relationship between topics for the knowledge graph

### Services

| File | Responsibility |
|---|---|
| `AudioRecordingService.swift` | AVFoundation recording, audio-level metering |
| `TranscriptionService.swift` | SFSpeechRecognizer, on-device transcription, `ko-KR` locale |
| `ClaudeAPIService.swift` | Anthropic API calls, Keychain credential storage (`KeychainHelper`) |
| `StorageService.swift` | JSON persistence, full-text search, cross-meeting knowledge graph |
| `AppleNotesService.swift` | Export to Notes.app (AppleScript/macOS, share sheet/iOS) |

### Views

| File | Screen |
|---|---|
| `ContentView.swift` | Root `TabView`: Recording / Meeting List / Categories / Knowledge Graph |
| `RecordingView.swift` | Waveform UI + `MeetingViewModel` orchestrator |
| `MeetingDetailView.swift` | Tabbed detail: Summary / Topics / Directives / Mind Map |
| `GraphView.swift` | Force-directed Obsidian-style knowledge graph |
| `MindMapView.swift` | Hierarchical tree layout engine |

## Conventions

**Localization:** All UI labels, Claude prompt text, and date formatters use Korean (`ko-KR`). Keep this consistent when adding new strings or prompts.

**State management:** MVVM — `RecordingViewModel` (the main orchestrator) holds `@Published` state; `StorageService.shared` is an `@MainActor` singleton accessed via `@ObservedObject` or direct calls from view models.

**Privacy invariants:**
- Audio never leaves the device.
- Transcription is on-device by default (`requiresOnDeviceRecognition = true`).
- Only structured text (not audio) is sent to the Claude API.
- The Anthropic API key is stored in Keychain; never hardcode or log it.

**No external dependencies:** The package has zero third-party Swift packages. Use only system frameworks (Foundation, SwiftUI, AVFoundation, Speech, Security, AppKit/UIKit).

**Platform branching:** Use `#if os(iOS)` / `#if os(macOS)` for platform-specific code. iOS uses `AVAudioApplication`; macOS uses `AVCaptureDevice` for microphone permission.

**Storage paths:**
- Recordings: `~/Library/Application Support/MeetingRecorder/Recordings/`
- Notes backups: `~/Library/Application Support/MeetingRecorder/Notes/`
- Index: `meetings.json` and `categories.json` in the same Application Support directory

**Claude API model:** `claude-sonnet-4-6`. The prompt is written in Korean and expects a structured JSON response matching `RawMeetingNotesResponse` in `ClaudeAPIService.swift`.
