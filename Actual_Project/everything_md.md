# Everything.md — Master Engineering, Design & Audit Specification

## 1. Project Identity & Core Thesis
* **App Name:** Keller’s Chord
* **Target Competition:** Apple Swift Student Challenge (`.swiftpm` App Playground)
* **Target Platforms:** iPadOS 18.0+ and macOS 15.0+ (Universal Swift App Playground)
* **The Human Problem:** Standard closed captions strip away $65\%$ to $70\%$ of human conversational meaning—*prosody* (vocal pitch contour, harmonic warmth, volume envelope, and cadence). In flat white subtitles, *"I'm fine with that"* looks identical whether spoken with warm relief, quiet anxiety, or biting sarcasm. Furthermore, profoundly deaf and hard-of-hearing (HoH) students often experience severe anxiety speaking aloud in college vivas or interviews because they lack real-time feedback on whether their vocal tone sounds harsh, monotone, or overly loud for a quiet room.
* **The Neurological Solution (Cross-Modal Sensory Substitution):** Inspired by how Helen Keller read vocal emotion by placing three fingers on a speaker's throat and face (laryngeal pitch in the palm, nasal warmth in the middle finger, consonant airflow on the index finger), **Keller’s Chord** translates live acoustic prosody into **Living, Touchable Typography** (`SwiftUI TextRenderer` + `Canvas`) and **Continuous Tactile Resonance** (`CoreHaptics` on iOS/iPadOS + `NSHapticFeedbackManager` on macOS).

---

## 2. Multi-Agent Role Division (`AI` + `impeccable` + `ponytail`)

When executing this specification, the development workflow is divided into three strict authorities:

1. **`AI` (Core Systems & DSP Architect):**
   * Owns the `.swiftpm` package structure, `AVAudioEngine` pipeline, `Accelerate` (`vDSP`) Fast Fourier Transform (FFT) and autocorrelation math, offline `SFSpeechRecognizer` integration, the `VoiceNotes` bundle loader, and the procedural audio fallback synthesizer.
   * **Rule:** Never ask the user for missing assets, API keys, or architectural decisions. Every constant, threshold, file path, and fallback is defined in this document.
2. **`impeccable` (Visual, Typography & Spatial UX Authority):**
   * Owns all SwiftUI views, glyph-level `TextRenderer` shaders, `MeshGradient` emotional backdrops, SF Symbols 6 animations, spatial layout, and tactile choreography.
   * **Rule:** Enforce an Apple Design Award aesthetic—deep obsidian/ink surfaces (`#08090C`), kinetic variable typography, zero visual clutter (no generic multi-tab bars, no raw debugging oscilloscopes), and one clear focal point per screen.
3. **`ponytail` (Code Auditor, Concurrency & Compliance Gatekeeper):**
   * Audits every generated file before completion.
   * **Rule:** Verify strict Swift 6 / `@MainActor` thread safety (audio tap closures must *never* mutate `@MainActor` state directly), zero memory leaks or retain cycles in `AVAudioEngine` taps, `#if os(iOS)` / `#if os(macOS)` cross-platform compilation, full VoiceOver/Dynamic Type/Reduce Motion compliance, and zero external network calls.

---

## 3. Hard Technical Constraints & User Asset Protocol

### 3.1 Swift Student Challenge Rules
1. **Format:** Standalone `.swiftpm` bundle under $25\text{ MB}$ total when zipped (target under $3\text{ MB}$).
2. **100% Offline:** Zero `URLSession` calls, zero external Swift Package dependencies, zero cloud APIs.
3. **No Headphone Feedback Loops:** Unlike delayed-feedback apps, Keller’s Chord does **not** route live microphone audio back out through the speakers during live speech mode (Act III). Live mic input is analyzed silently for DSP metrics and transcription while outputting only haptics and visual typography.

### 3.2 The Empty Voice Notes Folder & Auto-Detection Contract
The AI **must** create an empty directory at `KellersChord.swiftpm/Sources/Resources/VoiceNotes/` containing an empty `.gitkeep` file so the folder exists on disk immediately.

The user will record and drop **3 voice notes** saying *"I'm fine with that"* into `Sources/Resources/VoiceNotes/` with these exact filenames:
1. `voice_warm_relief.m4a` (or `.wav`) — Spoken with genuine warm relief and empathy.
2. `voice_anxious_tremor.m4a` (or `.wav`) — Spoken with quiet anxiety and shaky hesitation.
3. `voice_sharp_sarcasm.m4a` (or `.wav`) — Spoken with sharp, biting sarcasm.

**Zero-Crash Fallback Rule:**
`AudioSampleLoader.swift` must check `Bundle.module.url(forResource: name, withExtension: ext)` for `.m4a`, `.wav`, and `.mp3` inside the module bundle first.
* **If the user's voice note file is present:** Load it into an `AVAudioPCMBuffer`, route it through `ProsodyDSPEngine` during playback in Act I and Act II, and extract live 60fps prosody frames from the real recording.
* **If the folder is still empty:** Automatically fall back to `ProceduralVoiceSynthesizer.swift` so the app compiles, runs, and demonstrates all three emotional contours out of the box even before the user drops in the `.m4a` files.

---

## 4. Exact `.swiftpm` File Tree

The AI must create and maintain this exact directory structure:

```text
KellersChord.swiftpm/
├── Package.swift
└── Sources/
    ├── KellersChordApp.swift                 # @main entry, global AppState container
    ├── Resources/
    │   └── VoiceNotes/
    │       └── .gitkeep                      # Empty directory where user drops the 3 voice notes
    ├── Models/
    │   ├── ProsodyFrame.swift                # 60fps Sendable struct holding F0, RMS, Centroid, Jitter
    │   ├── EmotionalProfile.swift            # Enum: .neutral, .warmRelief, .anxiousTremor, .sharpSarcasm
    │   └── ActStage.swift                    # State machine: .act1Blindspot, .act2TactileDecoder, .act3VocalMirror
    ├── Engine/
    │   ├── AudioSampleLoader.swift           # Loads user's 3 voice notes from Bundle.module or triggers fallback
    │   ├── ProsodyDSPEngine.swift            # AVAudioEngine + Accelerate vDSP pitch/centroid/RMS extractor
    │   ├── ProceduralVoiceSynthesizer.swift  # Pure-Swift formant synthesizer fallback if VoiceNotes/ is empty
    │   ├── OfflineSpeechManager.swift        # SFSpeechRecognizer (requiresOnDeviceRecognition = true)
    │   └── TactileHapticEngine.swift         # CoreHaptics (iOS/iPadOS) + NSHapticFeedbackManager (macOS)
    ├── DesignSystem/                         # Managed by impeccable
    │   ├── ThemeTokens.swift                 # Color palettes, spring constants, typography scales
    │   ├── ProsodyTextRenderer.swift         # iOS 18 / macOS 15 TextRenderer for per-glyph morphing
    │   └── EmotionalMeshBackground.swift     # Reactive 3x3 MeshGradient driven by ProsodyFrame
    └── Views/                                # Managed by impeccable, audited by ponytail
        ├── RootCoordinatorView.swift         # Top-level 3-Act container with glassmorphic progress pill
        ├── Act1CaptionBlindspotView.swift    # 0:00–0:45 — The flat caption guessing game & reveal
        ├── Act2TactileProsodyView.swift      # 0:45–1:45 — Interactive touchable living typography explorer
        ├── Act3VocalMirrorView.swift         # 1:45–3:00 — Live mic prosody mirror & viva cadence coach
        └── Components/
            ├── TactileFingerPadView.swift    # 3-finger Helen Keller throat/nasal/lip touch zone
            └── CadenceHorizonBar.swift       # Subtle breathing & vocal volume safe-zone indicator
```

---

## 5. Exact `Package.swift` Specification

Note that `resources: [.process("Resources")]` is mandatory so Xcode and Swift Playgrounds bundle the `Sources/Resources/VoiceNotes/` folder into `Bundle.module`.

```swift
// swift-tools-version: 6.0
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "KellersChord",
    platforms: [
        .iOS("18.0"),
        .macOS("15.0")
    ],
    products: [
        .iOSApplication(
            name: "KellersChord",
            targets: ["AppModule"],
            bundleIdentifier: "com.srm.kellerschord",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .waveform),
            accentColor: .presetColor(.amber),
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft
            ],
            capabilities: [
                .microphone(purposeString: "KellersChord analyzes your vocal pitch, warmth, and cadence on-device to render living emotional typography and tactile feedback."),
                .speechRecognition(purposeString: "KellersChord transcribes your speech 100% offline to synchronize words with your vocal prosody.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
```

---

## 6. Mathematical & DSP Engine Specifications (`Engine/`)

### 6.1 `ProsodyFrame.swift` (Data Contract)
Every $16.6\text{ ms}$ ($\approx 60\text{ fps}$), the DSP engine publishes an immutable `ProsodyFrame` struct (`Sendable`) to the UI:
* `rmsAmplitude: Float` — Normalized in $[0.0, 1.0]$ representing vocal loudness.
* `fundamentalPitchHz: Float` — Raw $F_0$ in $\text{Hz}$ ($80.0$ to $400.0$), plus `normalizedPitch: Float` in $[0.0, 1.0]$.
* `spectralCentroid: Float` — Normalized in $[0.0, 1.0]$ representing vocal brightness/sharpness vs. chest warmth.
* `pitchJitter: Float` — Normalized in $[0.0, 1.0]$ representing micro-tremor/instability over a 12-frame rolling window.
* `classifiedEmotion: EmotionalProfile` — Computed from the four metrics above.

### 6.2 `ProsodyDSPEngine.swift` (`Accelerate` / `vDSP` Math)
Install an `AVAudioEngine` tap on `inputNode` (for Act III) or `mainMixerNode` (for Act I & II sample playback) with `bufferSize: 1024` at sample rate $f_s = 44100\text{ Hz}$ (or hardware native sample rate):
1. **RMS Amplitude:**
   * Compute root-mean-square using `vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))`.
   * Convert to decibels: $\text{dB} = 20 \log_{10}(\max(\text{rms}, 10^{-6}))$, clamp to $[-55\text{ dB}, -5\text{ dB}]$, and normalize linearly to $[0.0, 1.0]$.
2. **Fundamental Pitch ($F_0$) via Autocorrelation:**
   * Apply a Hanning window (`vDSP_hann_window` + `vDSP_vmul`).
   * Compute autocorrelation over lags corresponding to $80\text{ Hz}$ ($\tau_{\max} = \lfloor f_s / 80 \rfloor$) down to $400\text{ Hz}$ ($\tau_{\min} = \lfloor f_s / 400 \rfloor$) using `vDSP_dotpr`.
   * Locate peak lag $\tau_{\text{peak}}$: $F_0 = f_s / \tau_{\text{peak}}$. Normalize $[85\text{ Hz}, 320\text{ Hz}] \rightarrow [0.0, 1.0]$.
3. **Spectral Centroid (Harmonic Warmth vs. Sharpness):**
   * Run a 1024-point real FFT (`vDSP_DFT_zop` or `vDSP_fft_zrip`) to obtain magnitude spectrum $M[k]$ (`vDSP_zvabs`).
   * Compute weighted sum $\sum (k \cdot M[k])$ using `vDSP_dotpr` with a ramp vector (`vDSP_vramp`) divided by total magnitude $\sum M[k]$ (`vDSP_sve`).
   * Low spectral centroid ($< 0.35$) indicates **Warm Chest Resonance**. High spectral centroid ($> 0.65$) indicates **Sharp/Sarcastic/Strained Overtones**.
4. **Pitch Jitter (Vocal Tremor):**
   * Maintain a 12-element circular buffer of recent $F_0$ values. Compute standard deviation divided by mean $F_0$. High jitter ($> 0.45$) indicates **Anxious Hesitation**.
5. **Smoothing Filter:**
   * Apply an exponential moving average ($\alpha = 0.22$) to all four normalized metrics before hopping to `@MainActor` so animations never flicker violently.

### 6.3 `AudioSampleLoader.swift` & `ProceduralVoiceSynthesizer.swift`
When playing Voice A, B, or C in Act I or Act II:
1. Check `Bundle.module` for `voice_warm_relief`, `voice_anxious_tremor`, and `voice_sharp_sarcasm` (checking `.m4a`, `.wav`, and `.mp3` extensions).
2. If found, read the file via `AVAudioFile` into an `AVAudioPCMBuffer` and schedule it on `AVAudioPlayerNode`.
3. If not found in `Bundle.module`, synthesize three $3.5\text{-second}$ formant-modulated acoustic buffers in memory:
   * **Sample A (`.warmRelief`):** Smooth downward pitch glide ($190\text{ Hz} \rightarrow 135\text{ Hz}$), rich low-harmonic fundamental + 2nd harmonic, soft cosine attack/decay envelope, low centroid ($0.22$), minimal jitter ($0.05$).
   * **Sample B (`.anxiousTremor`):** Elevated base pitch ($235\text{ Hz}$) modulated by a $6.5\text{ Hz}$ vibrato tremor ($\pm 18\text{ Hz}$), fragmented amplitude syllables with pauses, high jitter ($0.78$), medium centroid ($0.48$).
   * **Sample C (`.sharpSarcasm`):** Abrupt narrow-band spike on word 2 (*"FINE"* at $290\text{ Hz}$) followed by a flat drop ($115\text{ Hz}$), rich odd harmonics (3rd, 5th, 7th) creating a biting metallic spectral centroid ($0.84$), harsh transient attack.

---

## 7. Cross-Modal Design System (`impeccable` Specification)

### 7.1 Visual-Tactile Mapping Matrix
`impeccable` must map every `ProsodyFrame` to typography (`ProsodyTextRenderer`) and haptics (`TactileHapticEngine`) using this exact physical vocabulary:

| Emotional Prosody State | Acoustic Signature | `ProsodyTextRenderer` Glyph Transform | Color & `MeshGradient` Aura | Haptic Pattern (`CoreHaptics` / Trackpad) |
| :--- | :--- | :--- | :--- | :--- |
| **Flat / Muted Caption (Baseline)** | No prosody data | Monospace/Static Sans, uniform weight, zero offset, $70\%$ white opacity | Flat slate (`#16181D`) on obsidian (`#08090C`) | None (Dead silence) |
| **Warm Empathy / Relief** | Low centroid ($<0.35$), smooth falling $F_0$, steady RMS | Rounded serif/sans blend, gentle vertical sine swell (`yOffset = -6 * rms * sin(...)`), soft outer bloom (`blur(radius: 4)` background copy), $1.08\times$ horizontal breathing scale | Golden Amber (`#F59E0B`), Warm Coral (`#FB7185`), Deep Honey (`#78350F`) | Continuous haptic: `Intensity = 0.55`, `Sharpness = 0.15` (soft, warm low-frequency purr) |
| **Anxious Hesitation / Tremor** | High jitter ($>0.45$), rising $F_0$, fluctuating RMS | Per-glyph horizontal & vertical micro-shiver (`dx = sin(time * 38 + index) * jitter * 4.5`), compressed tracking, fading trailing opacity | Electric Cyan (`#38BDF8`), Pale Lavender (`#A78BFA`), Midnight Indigo (`#1E1B4B`) | Pulsed transient heartbeat at $6.5\text{ Hz}$: `Intensity = 0.45`, `Sharpness = 0.50` |
| **Sharp Sarcasm / Tension** | High centroid ($>0.65$), abrupt RMS spikes, steep pitch drop | High-contrast vertical stretch (`scaleY = 1.0 + centroid * 0.35`), italic shear transform (`xSkew = -0.18 * centroid`), razor-sharp unblurred edges | Acid Crimson (`#F43F5E`), Neon Magenta (`#D946EF`), Burnt Obsidian (`#270914`) | High-sharpness staccato snap: `Intensity = 0.90`, `Sharpness = 0.95` |

### 7.2 `ProsodyTextRenderer.swift` Implementation Rules
Conform to `SwiftUI.TextRenderer` and `Animatable`:
* Iterate over `for line in layout { for run in line { for (index, glyph) in run.enumerated() { ... } } }`.
* For every glyph, create a local copy `var copy = ctx`.
* Apply three layered transforms based on the active `ProsodyFrame` and `elapsedTime`:
  1. **Harmonic Warmth Bloom:** When `spectralCentroid < 0.4` and `rmsAmplitude > 0.15`, draw a secondary background pass of `glyph` with `copy.addFilter(.blur(radius: 6 * (1 - spectralCentroid)))` and `copy.opacity = Double(rmsAmplitude) * 0.6` before drawing the crisp foreground glyph.
  2. **Pitch Inflection Wave:** Translate `y` by `-Double(normalizedPitch - 0.5) * 18.0 * sin(Double(index) * 0.45 + elapsedTime * 4.0)`.
  3. **Tremor & Sarcasm Shear:** Apply `CGAffineTransform` around the glyph's center point (`glyph.typographicBounds.rect.center`) combining vertical scale (`1.0 + Double(rmsAmplitude) * 0.28`) and horizontal jitter (`Double(pitchJitter) * 4.0 * cos(elapsedTime * 42.0 + Double(index) * 1.7)`).
* **Accessibility Override:** If `@Environment(\.accessibilityReduceMotion)` is `true`, disable high-frequency positional jitter (`elapsedTime * 42.0`) and express emotion purely through smooth color gradient shifts, font weight transitions, and haptics.

---

## 8. The 3-Act Judge Experience (180-Second Choreography)

### Act I: *The Caption Blindspot* (0:00 – 0:45)
* **Goal:** Make the judge experience the emotional blindness of standard subtitles in 20 seconds.
* **Screen Layout:**
  * Minimal top pill: `"ACT I OF III • THE CAPTION BLINDSPOT"`.
  * Center stage: Three interactive playback cards labeled **Voice A**, **Voice B**, and **Voice C**. All three display the exact same flat, sterile white subtitle: `"I'm fine with that."`
  * Below the cards: Three emotion tags the judge must assign: **Warm Relief**, **Quiet Anxiety**, **Biting Sarcasm**.
* **Interaction Flow:**
  1. In **Stage 1 (Muted Prosody Mode)**, tapping Voice A, B, or C flashes the flat white text with zero audio and zero animation. The judge taps an emotion guess—and the app reveals that with standard captions, all three look $100\%$ identical, stripping away $70\%$ of human intent.
  2. A prominent glowing button appears: **"Unlock Keller’s Chord (Cross-Modal Prosody)"**.
  3. Tapping it replays Voice A (`voice_warm_relief`), Voice B (`voice_anxious_tremor`), and Voice C (`voice_sharp_sarcasm`) with the **Tactile Prosody Engine** active: the flat text erupts into Golden Amber breathing typography (Voice A), shivering Cyan micro-tremor typography (Voice B), and jagged Crimson sheared typography (Voice C), synchronized with distinct haptic textures and audio.
  4. A **"Continue to Tactile Explorer"** button unlocks at the bottom.

### Act II: *The Helen Keller Tactile Decoder* (0:45 – 1:45)
* **Goal:** Show the neuroscience of Helen Keller’s 3-finger speech-reading method (`TactileFingerPadView.swift`).
* **Screen Layout:**
  * Top half: Large interactive `ProsodyTextRenderer` stage displaying live morphing phrases (*"I'm fine with that."*, *"Yeah, great job on that presentation."*, *"Don't worry, we'll figure it out together."*).
  * Bottom half: **The 3-Finger Sensory Pad**—three glowing concentric touch pads modeled on Helen Keller's hand placement:
    1. **Thumb / Palm Zone (Laryngeal Pitch $F_0$):** Dragging or resting a finger here isolates fundamental frequency ($85\text{ Hz}$ to $320\text{ Hz}$) and vibrates low-frequency pitch sweeps.
    2. **Middle Finger Zone (Nasal & Chest Warmth / Spectral Centroid):** Controls harmonic warmth vs. metallic sharpness, morphing letter softness and bloom in real time.
    3. **Index Finger Zone (Consonant Airflow & Cadence / RMS + Jitter):** Controls syllabic burst intensity and vocal tremor.
* **Interaction Flow:**
  * The judge can either replay the 3 recorded voice notes while resting their fingers on the 3 zones **or** physically scrub their fingers across the 3-Finger Sensory Pad to sculpt the emotion of the sentence in real time and feel how typography and haptics fuse into a single language.

### Act III: *The Vocal Mirror & Viva Coach* (1:45 – 3:00)
* **Goal:** Empower a deaf or hard-of-hearing student to rehearse speaking out loud for a college viva or interview with real-time visual-tactile self-monitoring.
* **Screen Layout:**
  * Top Prompt Card: A selectable college viva prompt (e.g., *"Prompt 1: Introduce your project and why it matters in two sentences."*).
  * Center Hero: Live `OfflineSpeechManager` transcript rendered through `ProsodyTextRenderer`, morphing in real time to the user's own microphone input (with a **"Simulate Live Voice"** toggle for judges testing in a quiet office without speaking).
  * Bottom Instrument (`CadenceHorizonBar.swift`): Three intuitive, non-clinical visual guides:
    * **Volume Safe-Zone Pill:** Shows whether the speaker's voice is *Too Quiet*, *Conversational Sweet Spot*, or *Overly Loud for a Quiet Room*.
    * **Warmth & Inflection Mirror:** Shows whether their tone is flat/monotone or carrying natural rises and warm chest resonance.
    * **Tactile Pacing Pulse:** Emits a gentle rhythmic haptic heartbeat at $130\text{ words per minute}$ so the speaker can physically feel a calm, confident viva cadence while holding the device.

---

## 9. `ponytail` Code Audit Checklist (Mandatory Pre-Output Verification)

Before the AI finalizes any file, `ponytail` must verify all 7 rules below:

1. **Audio Thread Isolation (Zero `@MainActor` Crashes):**
   * `AVAudioEngine.inputNode.installTap` runs on a real-time CoreAudio thread. Never reference `@MainActor` properties inside the tap closure. Compute `ProsodyFrame` inside a non-isolated helper method and dispatch to `@MainActor` via `Task { @MainActor in self.currentFrame = frame }` throttled to $\approx 60\text{ Hz}$.
2. **Cross-Platform Compiler Directives (`#if os(iOS)` vs `#if os(macOS)`):**
   * Wrap `AVAudioSession.sharedInstance()` calls inside `#if os(iOS) ... #endif`.
   * Wrap `NSHapticFeedbackManager` inside `#if os(macOS) ... #endif` and `CHHapticEngine` inside `#if canImport(CoreHaptics)`.
3. **Graceful Permission & Offline Speech Handling:**
   * If microphone or speech recognition permission is denied—or if on-device speech models are unavailable—automatically activate the **"Simulated Live Prosody Stream"** fallback with a sleek non-blocking status badge so the judge never hits a dead-end error screen.
4. **Tap Cleanup & Engine Restart Safety:**
   * Always call `removeTap(onBus: 0)` before installing a new tap or switching between Act I/II (recorded/synthesized buffer playback) and Act III (live microphone analysis).
5. **SwiftUI 60fps Performance:**
   * Drive `ProsodyTextRenderer` elapsed time via `TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: isPaused))` rather than leaking `Timer.publish` instances.
6. **Accessibility Audit:**
   * Every interactive card, sensory pad, and button must include `.accessibilityLabel(...)`, `.accessibilityValue(...)`, and `.accessibilityHint(...)`.
   * Respect `@Environment(\.accessibilityReduceMotion)` across all `TextRenderer` and `MeshGradient` animations.
7. **Zero Warnings / Zero Placeholders:**
   * No `TODO`, no `// implement later`, no stubbed functions, and no unused variables. Every file must be $100\%$ complete and ready to compile in Xcode 16+ / Swift Playgrounds 4.5+.

---

## 10. Human Deliverable Checklist (What the User Provides)

Everything else is built by the AI. You only need to provide:
1. **Three 3-to-4 Second Voice Notes** placed inside `KellersChord.swiftpm/Sources/Resources/VoiceNotes/`:
   * `voice_warm_relief.m4a` — Saying *"I'm fine with that"* with warm relief.
   * `voice_anxious_tremor.m4a` — Saying *"I'm fine with that"* with quiet, shaky anxiety.
   * `voice_sharp_sarcasm.m4a` — Saying *"I'm fine with that"* with sharp, biting sarcasm.
   *(Tip: Record these using the Apple Voice Memos app in a quiet room and drag the `.m4a` files directly into `Sources/Resources/VoiceNotes/`. Keep each file under $150\text{ KB}$.)*
2. **Optional Custom App Icon (`1024x1024` PNG):** The AI sets `.placeholder(icon: .waveform)` in `Package.swift` so it compiles immediately, which you can optionally swap for a custom icon in Week 7.

---

## 11. Master Prompt (Copy & Paste This to Your AI)

```text
Read `Everything.md` in its entirety. It is the single source of truth for building **Keller’s Chord**, a standalone Apple Swift Student Challenge App Playground (`KellersChord.swiftpm`) targeting iOS/iPadOS 18.0+ and macOS 15.0+.

Do NOT ask me any clarifying questions—every architectural decision, DSP formula, file path, fallback mechanism, and UI transition is already specified in `Everything.md`.

Execute the build using our three-role pipeline:
1. **AI (Core Systems & DSP Architect):**
   - Build the complete `.swiftpm` package structure including the empty `Sources/Resources/VoiceNotes/.gitkeep` directory and `resources: [.process("Resources")]` in `Package.swift`.
   - Build `AudioSampleLoader.swift` to automatically load `voice_warm_relief.m4a`, `voice_anxious_tremor.m4a`, and `voice_sharp_sarcasm.m4a` from `Bundle.module`, falling back seamlessly to `ProceduralVoiceSynthesizer.swift` if the folder is empty.
   - Build `ProsodyDSPEngine.swift` using `Accelerate` (`vDSP`) for real-time 60fps fundamental pitch (autocorrelation), RMS amplitude, spectral centroid (FFT), and pitch jitter.
   - Build `TactileHapticEngine.swift` (`CoreHaptics` + `NSHapticFeedbackManager`) and `OfflineSpeechManager.swift` (`SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` and simulated fallback).
2. **impeccable (Design & Spatial UX Authority):**
   - Craft all SwiftUI views, `ThemeTokens`, the reactive 3x3 `EmotionalMeshBackground`, the custom `ProsodyTextRenderer` (`SwiftUI.TextRenderer` + `Animatable` with per-glyph harmonic bloom, pitch inflection wave, and tremor/sarcasm shear), the 3-Finger Helen Keller Sensory Pad, and the 3-Act judge choreography.
   - Enforce an Apple Design Award dark-mode aesthetic with fluid spring physics and zero visual clutter.
3. **ponytail (Code Auditor & Compliance Gatekeeper):**
   - Audit every file before outputting it to guarantee strict Swift 6 `@MainActor` audio-tap thread safety, `#if os(iOS)` / `#if os(macOS)` cross-platform compilation, safe tap removal on state transitions, full VoiceOver and Reduce Motion accessibility support, and zero `TODO`s or placeholder stubs.

Generate the complete, production-ready codebase now, starting with `Package.swift` and `Sources/Resources/VoiceNotes/.gitkeep`, followed by `Models/`, `Engine/`, `DesignSystem/`, `Views/`, and `KellersChordApp.swift`. Write out every file completely with zero omissions.
```