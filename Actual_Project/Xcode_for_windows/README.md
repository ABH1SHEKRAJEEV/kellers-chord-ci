# Xcode for Windows

An Xcode-shaped IDE for Swift packages, running natively on Windows.

Open a `.swiftpm` package and get a three-pane workspace: project navigator,
syntax-highlighted editor with a declaration jump bar, and a live issues panel.
Zero dependencies, zero network calls, zero install.

```bash
cd Xcode_for_windows
node src/server.mjs --root ../KellersChord.swiftpm
# → http://127.0.0.1:PORT/
```

Requires Node 20 or newer. Nothing else.

---

## What this is, and what it is not

This is the important part, so it comes before the features.

**What it is:** a real, working IDE for reading, navigating and editing Swift
source on Windows. It parses `Package.swift`, indexes every Swift declaration,
highlights Swift with a genuine lexer, and runs a static analyzer that reports
what it can actually prove.

**What it is not:** Xcode. There is no Swift compiler here, no iOS SDK, no
simulator, and no way to run a SwiftUI app. Those require macOS: they link
against Apple's private frameworks, ship the proprietary SDK, and the simulator
needs Apple's hypervisor entitlements. No amount of tooling on Windows changes
that, and this project does not pretend otherwise.

So there is one honest line between the two:

| | |
|---|---|
| ✅ Read, edit, navigate, index, analyse Swift | Works, today, fully offline |
| ❌ Compile, run, preview, simulate | Not possible on Windows |

When this tool says "no errors found", it means **no structural errors**, which
is a much weaker claim than "compiles". The distinction is enforced in the code:
findings are graded `error` / `warning` / `info` and only the first two are facts
the analyzer can establish by construction.

---

## Why not just use VS Code

You can. This exists because VS Code needs an extension ecosystem, a language
server, and a toolchain to be useful for Swift, and none of those are available
without a compiler. This instead does the work that *is* possible without one:
it understands the package structure, the declaration graph, and the specific
cross-platform and accessibility rules a Swift Student Challenge submission is
judged on.

---

## Features

### Project navigator
Reads the package tree, skips `.build` / `DerivedData` / `node_modules`, shows
file sizes, and renders the parsed manifest — product name, bundle identifier,
platforms, targets, and capability purpose strings — beneath the tree.

### Editor
- Swift lexer that is not fooled by `//` inside a string, `"` inside a comment,
  nested block comments, raw strings (`#"..."#`), or compiler directives.
- Declaration jump bar for top-level types and functions.
- Line gutter, live byte count, caret position, Tab-indents-four.
- Ctrl/Cmd+S saves; the title bar marks unsaved changes; closing warns.

### Issues panel
Static analysis across the whole package, filterable by severity, with click-to-
jump. Four families of check:

| Rule | What it reports | Severity |
|---|---|---|
| `structure` | Unbalanced `{}` `[]` `()`, unterminated strings, stray braces | error |
| `completeness` | `TODO`, `FIXME`, `XXX`, `HACK`, "implement later", `fatalError` stubs | warning |
| `cross-platform` | `AVAudioSession` outside `#if os(iOS)`, `NSHapticFeedbackManager` outside `#if os(macOS)`, `CHHapticEngine` outside `#if canImport(CoreHaptics)` | warning |
| `accessibility` | `Button` / `Toggle` / `.onTapGesture` with no `.accessibilityLabel` nearby | warning |
| `dead-code` | `private` member declared and never referenced | info |

Delimiters and platform APIs are matched **on code only** — comments and strings
are blanked first, so a platform API named in a doc comment does not warn.

### Package manifest reader
`Package.swift` is Swift code, not JSON, so this locates the `Package(...)` call
and its nested product and target declarations directly. It reports malformed or
incomplete manifests as warnings instead of failing to open.

---

## Verified behaviour

Run against `KellersChord.swiftpm` — 25 Swift files, 7,311 lines, 48 types,
170 functions, 308 KB:

```
structural errors  0
case findings      2   (both real: two Buttons with no accessibilityLabel)
```

All 38 unit tests pass (`npm test`). The two findings above were each confirmed
by reading the flagged source by hand.

---

## Layout

```
Xcode_for_windows/
├── package.json
├── README.md
├── src/
│   ├── server.mjs            HTTP server, loopback only, no deps
│   ├── workspace.mjs         path safety, file IO, mtime-cached analysis
│   └── swift/
│       ├── tokenizer.mjs     Swift lexer
│       ├── manifest.mjs      Package.swift reader
│       ├── indexer.mjs       declaration index
│       └── analyzer.mjs      static checks
├── public/
│   ├── index.html
│   ├── styles.css
│   └── app.js                client; mirrors the lexer for instant highlighting
└── tests/
    ├── tokenizer.test.mjs
    ├── manifest.test.mjs
    └── analyzer.test.mjs
```

---

## API

All endpoints are read-only except `PUT /api/file`.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/overview` | Manifest, counts, per-file stats |
| `GET` | `/api/tree` | File tree |
| `GET` | `/api/file?path=` | File contents |
| `PUT` | `/api/file?path=` | Save `{"content": "..."}` |
| `GET` | `/api/diagnostics` | Whole-package analysis |
| `GET` | `/api/symbols?path=` | Declarations in one file |
| `GET` | `/api/manifest` | Parsed manifest |

---

## Security

The server binds to `127.0.0.1` only. Every path supplied by the client is
resolved and then compared against the workspace root; anything escaping it
returns `403`. Verified against `../`, deep `../../..`, absolute `C:/Windows/...`,
and URL-encoded `%2e%2e` traversal. Static file serving applies the same rule.
Bodies are capped at 8 MB, edited files at 4 MB.

---

## Known limits

These are real and by design, not bugs to be filed:

- **No compiler, therefore no type checking.** An undefined symbol, a wrong
  argument label, or a bad SwiftUI overload will not be reported. Nothing here
  substitutes for running `swift build` on a Mac.
- **The indexer is a brace walker, not a parser.** Deeply nested generics,
  operator declarations, and result-builder DSLs may index imperfectly. It never
  crashes on them; it may simply miss a symbol.
- **The accessibility check is a 12-line heuristic.** It can miss a label applied
  further down a modifier chain, and it can miss controls built without
  `Button`/`Toggle`.
- **Client and server keep separate lexers.** The client copy exists so typing
  never waits on a round trip. They are kept in sync by hand and the test suite
  covers the server side; a divergence would show as a colour difference, not a
  data-loss bug.
- **No git integration, no rename refactor, no debugger.**

---

## Next steps that would actually add capability

In rough order of value per unit of work:

1. **A real `swift build` bridge.** If Apple's Windows toolchain is installed,
   shell out to it for command-line targets. This is the only change that would
   turn "no structural errors" into "it compiles".
2. **Cross-file symbol resolution.** Resolve `Type.member` references across files
   so the dead-code check stops being per-file only.
3. **Go-to-definition.** The index already holds every declaration with a line
   number; wiring a click-through is mostly UI work.
4. **A `.swiftpm` project template.** New package scaffolding, matching the
   structure `Package.swift` expects.
