# MythosVox

MythosVox is a native SwiftUI voice-effects workspace for iPad and Mac. This
repository contains the first deliberately small product slice: live voice
processing, editable presets, system text-to-speech, and user-supplied looping
ambiance. It uses Apple frameworks only.

Voice cloning and generated ambiance are intentionally **not** part of this
slice. They should be evaluated only after the local audio workflow is useful
and stable.

## Current capabilities

- Live microphone monitoring through an `AVAudioEngine` effects graph.
- Pitch adjustment expressed in cents (`-1200...1200`).
- Distortion and reverb wet/dry controls.
- Editable, duplicable, and deletable voice presets.
- Preset and selection persistence with `UserDefaults`.
- Built-in text-to-speech through `AVSpeechSynthesizer`.
- User-selected audio imported into the sandbox and looped as ambiance.
- Independent voice, speech, ambiance, and master volume controls.
- One adaptive SwiftUI interface for native macOS and iPadOS.
- Microphone, sandbox, file-access, and privacy-manifest configuration.

## Requirements

- Xcode 26 or newer.
- macOS 15 or newer.
- iPadOS 18 or newer.

The target builds in Swift 6 language mode against the latest installed SDK.
There are no package-manager or third-party dependencies.

## Run

1. Open `MythosVox.xcodeproj`.
2. Select the shared `MythosVox` scheme.
3. Select a Mac, iPad simulator, or physical iPad.
4. Configure your Apple development team when deploying to a physical device.
5. Run, grant microphone permission, and use headphones while monitoring the
   microphone to avoid acoustic feedback.

Command-line build checks on a Mac:

```sh
xcodebuild \
  -project MythosVox.xcodeproj \
  -scheme MythosVox \
  -destination 'platform=macOS' \
  build

xcodebuild \
  -project MythosVox.xcodeproj \
  -scheme MythosVox \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Architecture

The code is organized by responsibility rather than framework:

```text
MythosVox/
├── App/
│   └── MythosVoxApp.swift          App and scene entry point
├── Audio/
│   └── AudioEngineController.swift Audio graph, playback, TTS, permissions
├── Models/
│   └── VoicePreset.swift           Codable domain model and seed presets
├── Services/
│   └── PresetStore.swift           Preset mutation and persistence
├── Views/
│   ├── ContentView.swift           Adaptive workspace and user actions
│   └── PresetEditorView.swift      Focused preset bindings and controls
├── MythosVox.entitlements          macOS sandbox/audio/file entitlements
└── PrivacyInfo.xcprivacy           Required-reason API declaration
```

### State ownership and data flow

`ContentView` owns exactly two long-lived observable objects:

- `PresetStore` is the source of truth for presets and the selected preset.
- `AudioEngineController` owns all AVFoundation objects and runtime audio
  state.

Views send user intent to those objects. They do not manipulate audio nodes or
serialize data directly. Preset edits are applied immediately to the audio
units and persisted. Both objects are `@MainActor`, keeping SwiftUI updates and
audio graph mutation serialized without introducing an actor layer before one
is needed.

### Audio topology

The live voice and ambiance paths join only at the engine's main mixer:

```text
Microphone input
      │
      ▼
AVAudioUnitTimePitch       pitch is set directly in cents
      │
      ▼
AVAudioUnitDistortion      wet/dry mix from the selected preset
      │
      ▼
AVAudioUnitReverb          wet/dry mix from the selected preset
      │
      ▼
Voice mixer ───────────────┐
                           ├──► Main mixer ──► System output
Ambiance player            │        ▲
      │                    │        │
      ▼                    │    master volume
Ambiance mixer ────────────┘
```

The graph is attached once and connected lazily after microphone permission is
granted. Voice and ambiance volume are applied at their dedicated mixer nodes;
master volume is applied at the main mixer.

Ambiance uses two queued copies of the selected file so callback latency does
not normally introduce a gap. A monotonically increasing loop generation
invalidates stale completion callbacks after stop, remove, or replacement.

### Text-to-speech boundary

Text-to-speech intentionally uses `AVSpeechSynthesizer` as a separate system
playback path. Speech volume is combined with the current master value when an
utterance starts. This keeps the first slice small, reliable, and able to use
installed system voices.

Consequences of that choice:

- Preset effects do not process synthesized speech.
- Changing speech or master volume does not alter an utterance already playing.

If processed TTS becomes a validated requirement, use
`AVSpeechSynthesizer.write(_:toBufferCallback:)`, schedule those PCM buffers on
an `AVAudioPlayerNode`, and mix that node into the graph before the pitch unit.
That change should also introduce explicit microphone and TTS pre-effect mixer
nodes so their levels remain independent.

### Persistence and file access

`PresetStore` encodes `[VoicePreset]` as JSON into `UserDefaults`; the selected
UUID is stored separately. Seed presets have stable UUIDs so selection remains
valid before the user first edits a preset.

The SwiftUI file importer returns a security-scoped URL. The controller opens
that scope only long enough to copy the audio into
`Application Support/MythosVox`, then plays the sandboxed copy. This avoids
retaining a security-scoped bookmark in the first slice.

The imported file is not restored into the UI after app relaunch yet. The copy
is durable, but loading its metadata on startup is a deliberate follow-up.

### Platform behavior

- iPadOS configures `AVAudioSession` as `.playAndRecord`, uses the default
  speaker, permits Bluetooth HFP, and mixes with other audio.
- macOS relies on the system audio route and requests capture access through
  `AVCaptureDevice`.
- The generated Info.plist contains the microphone usage message.
- macOS enables App Sandbox, microphone input, and read-only user-selected file
  access.
- The privacy manifest declares the app's own `UserDefaults` access.

## Deliberate first-slice constraints

- No voice cloning, model inference, cloud audio upload, accounts, or backend.
- No generated ambiance.
- No recording or export.
- No per-preset TTS voice, speaking rate, or language.
- No audio-session interruption or route-change recovery yet.
- No restoration of the imported ambiance selection after relaunch.
- No automated AVFoundation integration tests; audio behavior needs hardware or
  simulator/manual verification.

These are scope boundaries, not hidden extension points. Add them only when a
validated user workflow requires them.

## Recommended next steps

1. Build and manually exercise the project on a current Mac and iPad with wired,
   speaker, and Bluetooth routes.
2. Add audio interruption and route-change handling before distribution.
3. Persist and restore imported ambiance metadata.
4. Add unit tests around `PresetStore` using an isolated `UserDefaults` suite.
5. Add UI tests for preset editing, import errors, and engine start/stop states.
6. Decide from user feedback whether TTS should pass through the voice-effects
   graph before expanding the graph.
7. Add recording/export only after output routing and interruption behavior are
   stable.

## Verification status

The repository structure, source membership, XML, entitlements, privacy
manifest, and whitespace were validated in the Linux authoring environment.
That environment does not contain Xcode or Apple SDKs, so the macOS and iPadOS
build commands above remain the first required handoff check.
