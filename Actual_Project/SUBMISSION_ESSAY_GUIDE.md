# Swift Student Challenge — Written Response Guide

> **Purpose.** This is a reference bank, not a submission. Everything here is
> scaffolding for *you* to rewrite in your own voice. Judges are extremely good at
> spotting polished-but-generic prose, and the written response is scored. Use the
> bullets to decide what you mean; write the sentences yourself.
>
> **Verify first.** I could not reach Apple's site while writing this (search was
> down), so the prompt structure below follows the three parts you specified.
> **Confirm the exact prompts, word limits and character counts on Apple's live
> submission form before you paste anything in.** Word limits are hard limits.

---

## 0. Facts about this project you can rely on

Use only what is true. These are verified from the source:

| Claim | Verified how |
|---|---|
| 24 Swift files, ~7,500 lines | `Sources/` tree |
| Zero third-party dependencies | `Package.swift` has an empty dependency list |
| No network at all — no `URLSession`, no cloud | grep across `Sources/` |
| Works fully offline, including speech recognition | `requiresOnDeviceRecognition = true` |
| Runs on iPhone and iPad | `supportedDeviceFamilies: [.pad, .phone]` |
| Microphone + speech capabilities declared in the manifest | `capabilities: [.microphone, .speechRecognition]` |
| Gracefully simulates a voice when permissions are refused | `OfflineSpeechManager.beginSimulated` |

Frameworks actually imported (do not claim more than this):

- **SwiftUI** — including `TextRenderer`, `TimelineView`, `Canvas`, `MeshGradient`
- **AVFoundation** — `AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioUnitEQ`
- **Accelerate / vDSP** — `vDSP_fft_zrip`, `vDSP_dotpr`, `vDSP_rmsqv`, `vDSP_hann_window`, `vDSP_zvabs`
- **Speech** — `SFSpeechRecognizer`, `SFSpeechAudioBufferRecognitionRequest`
- **CoreHaptics** — `CHHapticEngine`, `CHHapticAdvancedPatternPlayer`, `CHHapticDynamicParameter`
- **Observation** — `@Observable`

Not used, so do not imply it: CoreML, ARKit, Vision, Metal, RealityKit, CreateML.

---

## (a) One-sentence problem & solution — max 50 words

### Outline
- **Problem:** captions carry the words and throw away the feeling. Deaf and
  hard-of-hearing readers get the transcript, not the intent.
- **Solution:** turn prosody into two senses that still work — sight (type that
  moves) and touch (haptics).
- **Name the mechanism in one clause:** FFT-derived pitch, warmth, tremor, cadence.
- Do **not** try to fit frameworks or your club into this sentence.

### Sample draft — 40 words (count it after you edit)

> Standard captions carry words but erase emotion, so Deaf and hard-of-hearing
> readers miss intent. Keller's Chord renders speech as living typography and
> haptic braille, letting you feel a sentence's warmth, anxiety, or sarcasm through
> sight and touch instead of hearing.

**Why it works:** one problem, one mechanism, one outcome, no adjectives that need
defending. If you rewrite it, re-count — 50 is a hard ceiling, not a target.

---

## (b) User experience, frameworks, and AI disclosure — max 500 words

This is the section that decides the technical score. Structure it as three moves:
**what the user does → why each framework → how the AI was directed.** Do not let it
become a feature list.

### Outline — User experience
- Open on Act I: three voices, one identical flat caption. Tap, guess, and be
  wrong — because with flat text all three really are the same.
- Reveal: the same three clips replay with type that breathes and haptics that
  pulse. Same words, different feelings.
- Act II: drag three fingers to sculpt pitch, brightness and airflow, and feel the
  result in the hand.
- Act III: speak and watch your own sentence react; scrub any word to re-feel it.
- Say plainly that **the acts are freely switchable** — a judge should not have to
  sit through a timer.

### Outline — Frameworks, each with a *reason*, not a name-drop
- **SwiftUI `TextRenderer`** — the only way to move individual glyphs from a
  live signal; this is why iOS 18 is the floor.
- **Accelerate / vDSP** — autocorrelation pitch detection and an FFT spectral
  centroid on the audio render thread; hand-rolled loops would not keep up at 60 Hz.
- **AVFoundation** — one `AVAudioEngine` with a *single* installed tap feeds both
  the analyser and the recognizer, so the mic is never opened twice.
- **AVAudioUnitEQ** — Act I's 280 Hz low-pass is an actual audio-graph stage, so the
  judge *hears* hearing loss rather than reading a label.
- **Speech** — `requiresOnDeviceRecognition` keeps everything offline and private.
- **CoreHaptics** — each emotion has its own transient/continuous pattern, so the
  difference is felt, not described.

### Outline — Agentic AI disclosure (be specific and honest)
- State the direction of work: you wrote the architectural specification; an AI
  coding agent implemented against it in reviewed batches.
- Name the artefact: the spec document, and that each batch was reviewed before the
  next began.
- Name what you did yourself: the concept, the choreography, the acceptance
  criteria, and the audit that found and fixed real defects.
- Say what you can explain unaided — and make sure that is true.
- **Never imply the code appeared without you.** Understating this is the fastest
  way to lose trust in a viva.

### Sample draft — ~390 words

> **What the user does.** Keller's Chord opens on a provocation. Three voices play
> the same flat caption — "I'm fine with that." — and you are asked which one is
> sarcastic. You cannot tell, because with flat text none of them are. The reveal
> replays the same three clips while the words themselves move: warm relief sits
> low and steady, anxiety trembles, sarcasm sharpens and rises. The same sentence,
> felt differently. Act II hands you the instrument: dragging three fingers sculpts
> pitch, brightness and breath, and the result arrives in your hand as haptics.
> Act III turns the microphone on you and turns your own sentence into type you can
> feel, with any word replayable by touch.
>
> **Frameworks, and why each one.** SwiftUI's `TextRenderer` is the reason this app
> needs iOS 18: it is the only supported way to transform individual glyphs from a
> live signal, which is the entire visual thesis. Accelerate's vDSP does the real
> work underneath — normalised autocorrelation for pitch and an FFT spectral
> centroid, computed on the audio thread fast enough for 60 Hz. AVFoundation runs a
> single `AVAudioEngine` with exactly one installed tap, so the microphone is
> opened once and its buffers feed both the analyser and the recognizer. When Act I
> simulates hearing loss, that is a genuine `AVAudioUnitEQ` low-pass stage in the
> graph, not an effect drawn on screen: what you hear and what the app measures are
> the same signal. Speech runs with `requiresOnDeviceRecognition`, so nothing
> leaves the device. CoreHaptics gives each emotion its own transient and
> continuous pattern, because the premise is that feeling can replace hearing.
>
> **How this was built.** I wrote the architectural specification first: the three
> acts, the prosody features, the acceptance criteria for each batch. An AI coding
> agent then implemented against that specification in twelve reviewed batches,
> and I audited the result line by line — that audit found two compile errors, a
> headline feature that produced no audible output, and a bug that duplicated every
> recorded word. I fixed those and can explain any file in the project, including
> the DSP maths and why the filter sits where it does.

---

## (c) SRM iOS Club & local impact — max 200 words

### Outline
- **Who you are:** member/lead of the SRM iOS Club — name the campus specifically.
- **What the club gave you:** peers who tested it, feedback sessions, the habit of
  demoing.
- **What you gave back:** a session you ran, or will run, on accessible design,
  DSP, or SwiftUI animation — be concrete about format and audience size.
- **Local impact:** who nearby would use it (a school for Deaf students, a campus
  accessibility office, a family member). Only claim a relationship you actually
  have.
- **Next step:** what you intend after the challenge — TestFlight, a club build
  night, translating the caption idea into another app.

### Sample draft — ~150 words

> I build with the SRM iOS Club, where the weekly build nights are the reason this
> project exists at all: I demoed the first Act I prototype to the club and watched
> people guess all three voices wrong, which is the moment the idea proved itself.
> Club members then tested each batch and told me, bluntly, when the typography
> moved too fast to read. In return I am running a session on accessible design in
> SwiftUI — building a caption that carries emotion rather than only words — so the
> techniques leave my project and enter other people's.
>
> Locally, the people this is for are close by: students at SRM who rely on captions
> in lectures and videos, and the campus accessibility staff I have spoken to about
> what subtitles still fail to convey. The next step is a TestFlight build for the
> club, so the feedback loop continues after the challenge rather than ending with
> it.

---

## Pre-submission checklist

- [ ] Re-count (a) at ≤50 words and (b) at ≤500 in the actual form.
- [ ] Every framework named is one you can point to in the source.
- [ ] Every claim about the club and local partners is true and specific.
- [ ] You can explain the DSP and the haptics without notes.
- [ ] The AI disclosure is present and does not overstate your role *or* hide it.
- [ ] Read it aloud once — that is what removes the "AI wrote this" register.
