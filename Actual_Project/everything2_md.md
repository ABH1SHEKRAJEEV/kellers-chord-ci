# Everything2.md — Phase 2 Expansion: "Cupertino Distinguished Winner & Live Stage Edition"

## 1. Purpose & Relationship to `Everything.md` and `HANDOFF.md`

* **Role of `Everything.md`:** Defines the Phase 1 baseline architecture (Batches 1–7) of **Keller’s Chord** (`KellersChord.swiftpm`).
* **Role of `Everything2.md` (This Document):** Defines the **Phase 2 Expansion (Batches 8–12)**—layering 13 high-impact neurological, acoustic, and tactile accessibility capabilities directly onto the Phase 1 codebase without breaking any existing APIs, exceeding the $25\text{ MB}$ `.swiftpm` limit, or cluttering the 3-minute judge flow.
* **Single Source of Truth Rule:** Together, `Everything.md`, `Everything2.md`, and `HANDOFF.md` contain every mathematical formula, struct property, view state, and fallback rule. The AI (`AI` + `impeccable` + `ponytail`) must **never** ask the user for clarification and must resolve all implementation details from these files.

---

## 2. How We Pack 13 Breakthrough Features Into a Clean 3-Minute Judge Flow

Apple judges penalize cluttered interfaces with 10 tabs. To make the judge feel overwhelmed with wonder—not overwhelmed by buttons—every new feature is woven natively into the existing **3-Act Progressive Storyline**:

| Act & Time Window | Baseline Experience (`Everything.md`) | Phase 2 Mind-Blowing Upgrades (`Everything2.md`) |
| :--- | :--- | :--- |
| **Act I: The Caption Blindspot** ($0\text{:}00 - 0\text{:}45$) | Flat white captions look identical across 3 emotions until Cross-Modal Prosody is unlocked. | **1. $280\text{ Hz}$ Cochlear Loss Audio Simulator:** Judge hears how profound sensorineural hearing loss turns speech into an indistinct muffled rumble—until haptics and living typography make their brain "hear" the missing emotion. |
| **Act II: The Helen Keller Tactile Decoder** ($0\text{:}45 - 1\text{:}45$) | 3-Finger Sensory Pad mapping Thumb ($F_0$), Middle (Warmth), and Index (Airflow/RMS). | **2. Cymatic Chladni Standing-Wave Canvas:** Real acoustic nodal geometry under the fingertips.<br>**3. High-Frequency Sibilance & Plosive "Consonant Spark" Detector ($4\text{ kHz} - 8\text{ kHz}$):** Solves unvoiced consonant blindness (`S`, `SH`, `CH`, `T`, `K`) with visual micro-sparks and Index-Finger ticks. |
| **Act III: The Vocal Mirror & Live Stage** ($1\text{:}45 - 3\text{:}00$) | Live microphone transcription + `ProsodyTextRenderer` + `CadenceHorizonBar`. | **4. "Vocal Braille" Slow-Motion Time-Scrubbing:** Drag a finger across spoken words to feel recorded vocal vibrations in slow motion.<br>**5. Tabletop $180^\circ$ Face-to-Face Duet Mode:** Split-screen across a desk for live two-person conversation.<br>**6. Magnetic "Ghost Inflection Rail":** Target pitch/warmth contour ribbon behind viva prompts.<br>**7. Hardware Voice Isolation + $1.5\text{ s}$ Room Calibration Gate:** Eliminates room fan/AC noise.<br>**8. Sub-$180\text{ ms}$ Partial Syllables + $60\text{ s}$ Rolling Speech Handover:** Zero timeout during live demos.<br>**9. $16\text{ ms}$ Acoustic Pre-Echo Ink Seed:** Instant zero-latency vocal orb before text resolves.<br>**10. "3-Take Live Stage Challenge" Deck:** Stack 3 live emotional takes side-by-side.<br>**11. "Lombard Effect" Room-Aware Volume Governor:** Adjusts vocal volume target to room ambience.<br>**12. Terminal Question vs. Statement Inflection Detector ($\Delta F_0$):** Detects rising question tails vs. grounded statement drops.<br>**13. "Vocal Prosody Passport" Summary Sheet:** 1-tap Apple Fitness+ style radial prosody signature at the $3\text{:}00$ mark. |

---

## 3. Expanded `.swiftpm` File Tree (Phase 1 + Phase 2 Complete)

Files marked with `[UPDATED]` are extended non-destructively; files marked with `[NEW]` are added in Batches 8–12:

```text
KellersChord.swiftpm/
├── Package.swift
├── Everything.md
├── Everything2.md
├── HANDOFF.md
└── Sources/
    ├── KellersChordApp.swift
    ├── Resources/
    │   └── VoiceNotes/
    │       └── .gitkeep
    ├── Models/
    │   ├── ProsodyFrame.swift                  # [UPDATED] Adds sibilanceEnergy, terminalPitchSlope, isCochlearFiltered
    │   ├── EmotionalProfile.swift
    │   ├── ActStage.swift
    │   └── WordProsodySnapshot.swift           # [NEW] Stores per-word ProsodyFrame slices for Vocal Braille scrubbing
    ├── Engine/
    │   ├── AudioSampleLoader.swift
    │   ├── ProsodyDSPEngine.swift              # [UPDATED] Adds 280Hz cochlear low-pass, 4-8kHz sibilance ZCR/FFT, room noise calibration, voice isolation
    │   ├── ProceduralVoiceSynthesizer.swift    # [UPDATED] Supports 280Hz cochlear muffled simulation pass
    │   ├── OfflineSpeechManager.swift          # [UPDATED] Adds 60s rolling pause handover + [WordProsodySnapshot] recorder
    │   └── TactileHapticEngine.swift           # [UPDATED] Adds Consonant Spark tick, Question Glide, Lombard Nudge, Braille Scrub playback
    ├── DesignSystem/
    │   ├── ThemeTokens.swift
    │   ├── ProsodyTextRenderer.swift           # [UPDATED] Adds 4-8kHz Consonant Spark diamonds + rising/falling terminal inflection tails
    │   ├── EmotionalMeshBackground.swift
    │   └── ChladniWaveCanvas.swift             # [NEW] 60fps pure-Swift cymatic standing-wave nodal field for Act II
    └── Views/
        ├── RootCoordinatorView.swift           # [UPDATED] Adds Quick Stage Switcher & Prosody Passport button
        ├── Act1CaptionBlindspotView.swift      # [UPDATED] Adds 280Hz Cochlear Loss Simulator toggle
        ├── Act2TactileProsodyView.swift
        ├── Act3VocalMirrorView.swift           # [UPDATED] Integrates Vocal Braille scrubbing, 16ms Pre-Echo Ink Seed, Duet & 3-Take toggles
        └── Components/
            ├── TactileFingerPadView.swift      # [UPDATED] Embeds ChladniWaveCanvas + Index-Finger Consonant Spark indicator
            ├── CadenceHorizonBar.swift         # [UPDATED] Adds Lombard Room-Aware Volume Governor + Terminal Inflection Badge
            ├── GhostInflectionRailView.swift   # [NEW] Magnetic target pitch/warmth contour ribbon behind prompts
            ├── TabletopDuetOverlay.swift       # [NEW] 180-degree split-screen face-to-face desk conversation view
            ├── LiveComparisonDeckView.swift    # [NEW] 3-Take Live Stage Challenge side-by-side comparison strip
            └── ProsodyPassportSheet.swift      # [NEW] End-of-tour radial Vocal Prosody Signature & judge reset card
```

---

## 4. Hyper-Detailed Technical Specifications for All 13 Upgrades

### 4.1 Expanded Data Contracts (`ProsodyFrame.swift` & `WordProsodySnapshot.swift`)

#### `ProsodyFrame.swift` Extensions
Ensure `ProsodyFrame` (`Sendable`, `Equatable`) includes these additional defaulted properties (using default values in `init` so zero existing call sites break):
* `sibilanceEnergy: Float = 0.0` — Normalized in $[0.0, 1.0]$ representing high-frequency ($4000\text{ Hz}$ to $8000\text{ Hz}$) fricative/plosive consonant energy (`S`, `SH`, `CH`, `T`, `K`).
* `terminalPitchSlope: Float = 0.0` — Normalized in $[-1.0, 1.0]$ representing the linear regression slope of $F_0$ over the trailing $350\text{ ms}$ ($\approx 20$ frames). Values $\gt +0.28$ indicate a **Rising Question Inflection ($\nearrow$)**; values $\lt -0.25$ indicate a **Grounded Statement Drop ($\searrow$)**.
* `ambientNoiseDB: Float = -50.0` — Current calibrated room noise floor in decibels for the Lombard Effect volume governor.

#### `WordProsodySnapshot.swift` (`[NEW]` Model for Vocal Braille & 3-Take Deck)
```swift
import Foundation

public struct WordProsodySnapshot: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let word: String
    public let timestampOffset: TimeInterval
    public let duration: TimeInterval
    public let frames: [ProsodyFrame]
    public let dominantFrame: ProsodyFrame
    public let hasConsonantSpark: Bool
    public let terminalInflection: TerminalInflectionType

    public enum TerminalInflectionType: String, Sendable, Equatable {
        case steady = "Steady"
        case risingQuestion = "Rising Question"
        case groundedDrop = "Statement Drop"
    }
}

public struct LiveChallengeTake: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let takeNumber: Int
    public let targetLabel: String
    public let transcript: String
    public let snapshots: [WordProsodySnapshot]
    public let averageFrame: ProsodyFrame
}
```

---

### 4.2 DSP Math & Audio Pipeline Upgrades (`ProsodyDSPEngine.swift` & `ProceduralVoiceSynthesizer.swift`)

#### Upgrade 1: $280\text{ Hz}$ Cochlear Sensorineural Loss Filter (Act I)
* **Clinical Basis:** Profound high-frequency sensorineural hearing loss preserves low-frequency vowel rumble below $280\text{ Hz}$ while stripping away upper formants ($F_2, F_3$) and harmonic overtones where vocal emotion and consonant clarity live.
* **Implementation:**
  * Add `public var isCochlearSimulationEnabled: Bool = false` on `ProsodyDSPEngine` (and `ProceduralVoiceSynthesizer`).
  * When `isCochlearSimulationEnabled == true` during Act I playback, pass the audio samples $x[n]$ through a cascaded 2-pole Butterworth or exponential low-pass filter with cutoff $f_c = 280\text{ Hz}$:
    $$\alpha_{\text{LP}} = \frac{\Delta t}{RC + \Delta t}, \quad RC = \frac{1}{2\pi \cdot 280}, \quad y[n] = y[n-1] + \alpha_{\text{LP}}(x[n] - y[n-1])$$
    Run two passes in series for a steep $-12\text{ dB}$ to $-24\text{ dB/octave}$ roll-off so the voice sounds authentically muffled like profound cochlear loss without clipping.

#### Upgrade 6: Hardware Voice Isolation & $1.5\text{ s}$ Room Noise Calibration Gate
* **Hardware Beamforming:** Before starting `AVAudioEngine` in live mic mode, call:
  ```swift
  #if os(iOS) || os(macOS)
  if #available(iOS 17.0, macOS 14.0, *) {
      try? engine.inputNode.setVoiceProcessingEnabled(true)
  }
  #endif
  ```
  *(Note: Only call `setVoiceProcessingEnabled` when the engine is stopped or before tap installation, wrapped in `try?` so simulator hardware never throws).*
* **Room Noise Calibration (`calibrateRoomNoise(duration: TimeInterval = 1.5)`):**
  * Samples live RMS over $1.5\text{ seconds}$ while the user is silent.
  * Computes mean ambient RMS ($\mu_{\text{noise}}$) and sets `ambientNoiseFloorRMS = min(max(meanRMS * 1.35, 0.002), 0.18)`.
  * Subtract `ambientNoiseFloorRMS` from raw RMS prior to normalizing `rmsAmplitude` and gate `pitchJitter` to `0.0` whenever raw RMS is below `ambientNoiseFloorRMS * 1.15` so ceiling fans or AC hum never trigger false anxiety tremors.

#### Upgrade 10: High-Frequency Sibilance & Plosive Detector ($4\text{ kHz} - 8\text{ kHz}$ "Consonant Spark")
* **Acoustic Formula:** Inside the existing 1024-point FFT (`f_s = 44100` or `48000`), bin index $k$ corresponds to frequency $f_k = k \cdot f_s / 1024$ ($\approx 43\text{ Hz}$ per bin).
  * Bins $k \in [90, 185]$ correspond to $3875\text{ Hz} - 7960\text{ Hz}$ (the sibilant/fricative band for `S`, `SH`, `CH`, `T`, `K`).
  * Compute high-band energy $E_{\text{high}} = \sum_{k=90}^{185} M[k]$ and low-band vowel energy $E_{\text{low}} = \sum_{k=2}^{40} M[k]$.
  * Also compute Zero-Crossing Rate (`ZCR`) across the 1024 time-domain samples: fraction of adjacent samples where $x[n] \cdot x[n-1] \lt 0$.
  * Normalize `sibilanceEnergy` to $[0.0, 1.0]$ when $\text{ZCR} \gt 0.22$ and $E_{\text{high}} / (E_{\text{low}} + 10^{-5}) \gt 0.45$.

#### Upgrade 12: Terminal Question vs. Statement Inflection Slope ($\Delta F_0$)
* Maintain a 20-frame ($\approx 330\text{ ms}$) ring buffer of voiced $F_0$ values (frames where `rmsAmplitude > 0.08` and `sibilanceEnergy < 0.6`).
* Compare the average of the newest 6 voiced frames ($\bar{F}_{\text{end}}$) against the oldest 6 voiced frames ($\bar{F}_{\text{start}}$) in the window:
  $$\Delta F_0 = \bar{F}_{\text{end}} - \bar{F}_{\text{start}}$$
* Normalize `terminalPitchSlope = clamp(deltaF0 / 55.0, -1.0, 1.0)`.
  * If `terminalPitchSlope > 0.28` ($\Delta F_0 \gt +15\text{ Hz}$ rising glide): classify as `.risingQuestion`.
  * If `terminalPitchSlope < -0.25` ($\Delta F_0 \lt -14\text{ Hz}$ falling glide): classify as `.groundedDrop`.

---

### 4.3 Live Speech Handover & "Vocal Braille" Recorder (`OfflineSpeechManager.swift`)

#### Upgrade 7: Sub-$180\text{ ms}$ Partial Syllables & $60\text{-Second}$ Seamless Pause Rollover
* Always set `recognitionRequest.shouldReportPartialResults = true`.
* Track `sessionStartTime: Date`. Apple's `SFSpeechRecognizer` terminates sessions at $60\text{ seconds}$.
* Whenever `Date().timeIntervalSince(sessionStartTime) > 38.0` **and** `ProsodyDSPEngine` reports $350\text{ ms}$ of silence (`rmsAmplitude < 0.05` for 20 consecutive frames):
  1. Commit the current recognized text into `committedTranscriptPrefix: String`.
  2. Cleanly finish the current `recognitionTask` and instantiate a fresh `SFSpeechAudioBufferRecognitionRequest` on the next audio buffer without stopping `AVAudioEngine`.
  3. Concatenate `committedTranscriptPrefix + " " + liveSegmentTranscript` so the user and judge experience an infinite, uninterrupted live transcript.

#### Upgrade 3: Recording `[WordProsodySnapshot]` for "Vocal Braille" Time-Scrubbing
* While live speech (or simulated speech) is active, maintain a rolling buffer of recent `ProsodyFrame` values over the last $1.5\text{ seconds}$.
* Whenever a new word appears in `SFTranscription.segments` (or in the simulated word emitter), package the `ProsodyFrame` slice from the last $350\text{ ms}$ into a `WordProsodySnapshot` and append it to `@MainActor public var wordSnapshots: [WordProsodySnapshot]`.
* Expose `@MainActor public func scrubWord(at index: Int)`:
  * When the user drags their finger across word $i$ in Act III, `scrubWord(at: i)` temporarily overrides the active display `ProsodyFrame` with `wordSnapshots[i].dominantFrame` and triggers `TactileHapticEngine.shared.playBrailleScrub(for: wordSnapshots[i])`.

---

### 4.4 Cymatic Physics & Visual-Tactile Shaders (`DesignSystem/`)

#### Upgrade 2: `ChladniWaveCanvas.swift` (`[NEW]` 60fps Cymatic Standing-Wave Field)
* Rendered inside `TactileFingerPadView` in Act II using pure SwiftUI `TimelineView(.animation(minimumInterval: 1.0 / 60.0))` and `Canvas`.
* Evaluates a $28 \times 28$ grid of resonant acoustic particles across normalized coordinates $(x, y) \in [-1.0, 1.0]^2$ using Chladni's biharmonic plate equation:
  $$C(x, y) = \cos(n \pi x)\cos(m \pi y) - \cos(m \pi x)\cos(n \pi y)$$
  where:
  * $n = 1.5 + \text{Double(frame.normalizedPitch)} \times 4.5$
  * $m = 2.0 + \text{Double(frame.spectralCentroid)} \times 5.0$
* Particles where $|C(x, y)| \lt 0.28$ lie along the **acoustic nodal lines** and glow brightly with radius proportional to `frame.rmsAmplitude`, shifting smoothly into geometric mandalas as pitch and harmonic warmth change.
* Respects `@Environment(\.accessibilityReduceMotion)`: if `true`, renders a static harmonic contour ring instead of oscillating particles.

#### Upgrade 10 & 12 Visual Additions in `ProsodyTextRenderer.swift`
* **Consonant Spark Micro-Diamonds:** When `frame.sibilanceEnergy > 0.55`, draw a tiny crisp 4-point star/diamond glyph accent $6\text{ pt}$ above uppercase or sibilant characters (`S`, `s`, `C`, `c`, `T`, `t`, `Z`, `z`, `K`, `k`) in high-contrast Ice White (`#F8FAFC`) so a deaf speaker gets immediate visual confirmation that their high-frequency consonant air-burst was sharp and audible.
* **Terminal Inflection Glide:** On the final 3 glyphs of a line, apply a subtle upward baseline curve (`-8pt` lift) when `frame.terminalPitchSlope > 0.28` (Question Inflection) or a grounded downward anchor (`+5pt` settle) when `frame.terminalPitchSlope < -0.25`.

---

### 4.5 Interactive Views & Live Stage Components (`Views/` & `Views/Components/`)

#### Upgrade 8: $16\text{ ms}$ "Acoustic Pre-Echo Ink Seed" (Inside `Act3VocalMirrorView.swift`)
* At the trailing edge of the live transcript in Act III, render an inline reactive orb (`VocalInkSeedView`) that wakes up within $16\text{ ms}$ whenever `frame.rmsAmplitude > 0.08`.
* Even before `SFSpeechRecognizer` finishes decoding the syllable ($150\text{ ms}$ later), the Ink Seed expands, shifts color according to `frame.classifiedEmotion`, and emits haptics so the speaker experiences **zero latency** between their vocal cords vibrating and the screen responding.

#### Upgrade 5: `GhostInflectionRailView.swift` (`[NEW]` Component)
* Displays behind the active Viva Prompt in Act III.
* Draws a smooth cubic Bezier ribbon showing the ideal vocal prosody trajectory for that sentence (e.g., rising warmth on key nouns, steady cadence in the middle, confident pitch settle at the period—or rising tail on a question prompt).
* Renders the user's live pitch/warmth cursor riding along the rail; when the delta between user pitch and target rail is $\le 0.16$, a glowing `"LOCKED IN CADENCE"` badge illuminates and triggers a gentle haptic click.

#### Upgrade 4: `TabletopDuetOverlay.swift` (`[NEW]` Component)
* Activated via a **"Tabletop Duet ($180^\circ$)"** pill in Act III.
* Splits the screen into two equal horizontal halves separated by a glowing acoustic divider:
  * **Top Half (Partner / Interviewer View — Rotated $180^\circ$ via `.rotationEffect(.degrees(180))`):** Displays the live morphing `ProsodyTextRenderer` caption, an emotion aura indicator, and a prompt inviting the person across the desk to speak naturally.
  * **Bottom Half (Deaf User View — $0^\circ$ Upright):** Displays the upright live morphing caption, the **Vocal Braille Scrubber**, the **Consonant Spark & Question Inflection Badges**, and 3 one-tap conversational cards (*"Could you repeat that slower?"*, *"I can feel your vocal tone on my screen"*, *"Let me answer that"*).

#### Upgrade 9: `LiveComparisonDeckView.swift` (`[NEW]` Component)
* Activated via a **"3-Take Live Stage"** pill in Act III.
* Presents 3 compact recording slots for the same phrase (*"Good luck with your application."*):
  * **Slot 1:** Speak with Warm Empathy
  * **Slot 2:** Speak with Quiet Anxiety
  * **Slot 3:** Speak with Biting Sarcasm
* As the tester records (or simulates) each 3-second take, all three sentences remain pinned vertically on screen rendered with their captured `ProsodyFrame` and `[WordProsodySnapshot]`. The tester can drag their finger across Take 1, Take 2, or Take 3 to feel the drastic difference in typography and haptics side-by-side.

#### Upgrade 11: "Lombard Effect" Room-Aware Volume Governor (Inside `CadenceHorizonBar.swift`)
* Displays the calibrated room environment badge (*"Quiet Room ($38\text{ dB}$) — Soft Voice Target"* vs. *"Noisy Hall ($64\text{ dB}$) — Project Voice Target"*).
* Dynamically shifts the green "Conversational Sweet Spot" bracket on the volume bar based on `frame.ambientNoiseDB` so a deaf speaker always knows whether their vocal loudness matches the room they are standing in.

#### Upgrade 13: `ProsodyPassportSheet.swift` (`[NEW]` Component)
* Accessible via a **"Vocal Signature"** button in `RootCoordinatorView` or at the end of Act III.
* Renders a sleek 4-ring radial summary card:
  1. **Pitch Expressiveness ($F_0$ Range)**
  2. **Harmonic Chest Warmth (Low Centroid Ratio)**
  3. **Consonant Spark Clarity ($4\text{–}8\text{ kHz}$ Articulation)**
  4. **Lombard Room-Volume Match**
* Includes a prominent **"Reset 3-Minute Judge Tour"** button that cleanly resets Act I, II, and III for the next reviewer.

---

## 5. Atomic 5-Batch Execution Schedule (Anti-Timeout Protocol)

To guarantee zero `ECONNRESET` socket timeouts on NVIDIA NIM or any OpenAI-compatible endpoint, the AI **must** execute Phase 2 in **5 strict batches (maximum 2–3 files touched per batch)** and update `HANDOFF.md` at the end of every single batch:

* **Batch 8 (Models & DSP Core Upgrades):**
  * Update `Sources/Models/ProsodyFrame.swift`
  * Create `Sources/Models/WordProsodySnapshot.swift`
  * Update `Sources/Engine/ProsodyDSPEngine.swift` & `Sources/Engine/ProceduralVoiceSynthesizer.swift` ($280\text{ Hz}$ cochlear filter, $4\text{–}8\text{ kHz}$ consonant sibilance ZCR/FFT, terminal pitch slope $\Delta F_0$, $1.5\text{ s}$ room noise calibration, hardware voice isolation).
* **Batch 9 (Speech Rollover, Vocal Braille Recorder & Haptic Vocabulary):**
  * Update `Sources/Engine/OfflineSpeechManager.swift` (sub-$180\text{ ms}$ partials, $60\text{ s}$ seamless pause handover, `[WordProsodySnapshot]` recorder & `scrubWord(at:)`).
  * Update `Sources/Engine/TactileHapticEngine.swift` (Consonant Spark $8\text{ ms}$ index-finger tick, rising/falling terminal inflection glide, Lombard room-volume double-tap nudge, Vocal Braille slow-motion scrub playback).
* **Batch 10 (Cymatic Physics & Typography Shaders):**
  * Create `Sources/DesignSystem/ChladniWaveCanvas.swift` ($60\text{ fps}$ Chladni standing-wave nodal field).
  * Update `Sources/DesignSystem/ProsodyTextRenderer.swift` ($4\text{–}8\text{ kHz}$ Consonant Spark micro-diamonds + terminal question/statement inflection tails).
  * Update `Sources/Views/Act1CaptionBlindspotView.swift` & `Sources/Views/Components/TactileFingerPadView.swift` (wire up $280\text{ Hz}$ Cochlear Loss Simulator toggle in Act I and embed `ChladniWaveCanvas` + Consonant Spark indicator in Act II).
* **Batch 11 (New Act III Interactive Stage Modules):**
  * Create `Sources/Views/Components/GhostInflectionRailView.swift` (Magnetic target prosody contour ribbon).
  * Create `Sources/Views/Components/TabletopDuetOverlay.swift` ($180^\circ$ split-screen face-to-face conversation mode).
  * Create `Sources/Views/Components/LiveComparisonDeckView.swift` (3-Take Live Stage Challenge side-by-side comparison deck).
* **Batch 12 (Act III Integration, Lombard Bar, Prosody Passport & Final `ponytail` Audit):**
  * Update `Sources/Views/Components/CadenceHorizonBar.swift` (Lombard room-aware volume governor + terminal question/statement inflection badge).
  * Create `Sources/Views/Components/ProsodyPassportSheet.swift` (4-ring radial Vocal Prosody Signature summary + 1-tap Judge Tour Reset).
  * Update `Sources/Views/Act3VocalMirrorView.swift` & `Sources/Views/RootCoordinatorView.swift` (integrate Vocal Braille word scrubbing, $16\text{ ms}$ Pre-Echo Ink Seed, Room Calibration button, and mode pills).