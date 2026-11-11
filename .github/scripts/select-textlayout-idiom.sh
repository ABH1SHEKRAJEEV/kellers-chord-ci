#!/usr/bin/env bash
#
# select-textlayout-idiom.sh — resolve `Text.Layout`'s per-slice drawing idiom by
# compiling, not by guessing.
#
# WHY THIS EXISTS
# ---------------
# CI run 4's only compile error was `'Glyph' is not a member type of struct
# 'SwiftUICore.Text.Layout'`: the element type of a `Text.Layout` run, and the way
# SwiftUI expects that element to be drawn, were both invented at authoring time.
# `TextRenderer` is an iOS 18 API with no on-Windows documentation available, so
# the honest fix is to let the SDK answer: rewrite the two marked lines of
# `ProsodyTextRenderer.swift`, typecheck, and keep the first pair that compiles.
#
# The winner is printed as an exact patch for a human (or the next agent) to
# commit permanently. The working tree copy is what the rest of the run builds,
# so a wrong first guess costs seconds, not a whole CI run.
#
# Usage: select-textlayout-idiom.sh <package-dir> <artifacts-dir> <shim.swift>
# Exit: 0 = an idiom compiled (file left patched), 1 = none did (file restored).

set -uo pipefail

PKG_DIR="${1:?package dir}"
ART="${2:?artifacts dir}"
SHIM="${3:?Bundle.module shim}"

SRC="$PKG_DIR/Sources/DesignSystem/ProsodyTextRenderer.swift"
LOG="$ART/04-textlayout-probe.log"
BACKUP="$ART/ProsodyTextRenderer.swift.before-probe"

if [ ! -f "$SRC" ]; then
  echo "::warning::ProsodyTextRenderer.swift not found; nothing to probe."
  exit 0
fi

mkdir -p "$ART"
cp "$SRC" "$BACKUP"
: > "$LOG"

echo "=== SwiftUICore Text.Layout surface (if the SDK ships an interface) ===" | tee -a "$LOG"
IFACE="$(find "${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}/Platforms/iPhoneSimulator.platform" \
  -name 'SwiftUICore.swiftinterface' 2>/dev/null | head -1)"
if [ -n "${IFACE:-}" ] && [ -f "$IFACE" ]; then
  echo "interface: $IFACE" | tee -a "$LOG"
  grep -nE 'struct (Layout|Line|Run|RunSlice|Glyph|TypographicBounds)|func draw' "$IFACE" \
    | grep -iE 'layout|run|glyph|slice|typographic|draw' | head -40 | tee -a "$LOG"
else
  echo "no SwiftUICore.swiftinterface found (expected under an .xcframework-style SDK)" | tee -a "$LOG"
fi

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
# The renderer only depends on the models plus ThemeTokens, so the probe compiles
# six files instead of all twenty-five — it has to run up to six times.
PROBE_FILES=$(find "$PKG_DIR/Sources/Models" -name '*.swift' | sort)
PROBE_FILES="$PROBE_FILES $PKG_DIR/Sources/DesignSystem/ThemeTokens.swift"
PROBE_FILES="$PROBE_FILES $PKG_DIR/Sources/DesignSystem/ProsodyTextRenderer.swift"

# Rewrites the line that follows each CI-SELECT marker.
patch_probe() {
  python3 - "$SRC" "$1" "$2" <<'PY'
import sys

path, typealias, draw = sys.argv[1], sys.argv[2], sys.argv[3]
# Binary read/write so the file's newline style survives: the Windows working copy
# is CRLF while the macOS runner's checkout is LF, and a probe must not rewrite
# every line of the file it touches.
with open(path, "rb") as handle:
    raw = handle.read()
newline = b"\r\n" if b"\r\n" in raw else b"\n"
lines = raw.split(newline)

out, pending = [], None
for line in lines:
    marker = line.strip()
    if marker.endswith(b"CI-SELECT(typealias)"):
        out.append(line)
        pending = "typealias"
        continue
    if marker.endswith(b"CI-SELECT(draw)"):
        out.append(line)
        pending = "draw"
        continue
    if pending == "typealias":
        out.append(b"    private typealias LayoutSlice = " + typealias.encode("utf-8"))
        pending = None
        continue
    if pending == "draw":
        out.append(b"        " + draw.encode("utf-8"))
        pending = None
        continue
    out.append(line)

with open(path, "wb") as handle:
    handle.write(newline.join(out))
PY
}

probe_compiles() {
  # shellcheck disable=SC2086
  xcrun --sdk iphonesimulator swiftc \
    -typecheck -parse-as-library -swift-version 5 -module-name AppModule \
    -sdk "$SDK" -target arm64-apple-ios18.0-simulator \
    $PROBE_FILES "$SHIM" >> "$LOG" 2>&1
}

# Ordered best-guess first: the nesting-derived type is name-agnostic, so it is
# tried before the spelled-out `RunSlice`; plain `draw(_:)` is tried before the
# forms that also need a point.
CANDIDATES='Text.Layout.Element.Element.Element|glyphContext.draw(glyph)
Text.Layout.Element.Element.Element|glyph.draw(in: &glyphContext)
Text.Layout.Element.Element.Element|glyphContext.draw(glyph, at: glyph.typographicBounds.origin)
Text.Layout.RunSlice|glyphContext.draw(glyph)
Text.Layout.RunSlice|glyph.draw(in: &glyphContext)
Text.Layout.RunSlice|glyphContext.draw(glyph, at: glyph.typographicBounds.origin)'

ATTEMPT=0
WINNER_TYPEALIAS=""
WINNER_DRAW=""

while IFS='|' read -r typealias_line draw_line; do
  [ -n "${typealias_line:-}" ] || continue
  ATTEMPT=$((ATTEMPT + 1))
  patch_probe "$typealias_line" "$draw_line"
  echo "" | tee -a "$LOG"
  echo "--- candidate $ATTEMPT ---" | tee -a "$LOG"
  echo "typealias: $typealias_line" | tee -a "$LOG"
  echo "draw:      $draw_line" | tee -a "$LOG"
  if probe_compiles; then
    WINNER_TYPEALIAS="$typealias_line"
    WINNER_DRAW="$draw_line"
    echo "RESULT: PASS" | tee -a "$LOG"
    break
  fi
  echo "RESULT: FAIL" | tee -a "$LOG"
done <<< "$CANDIDATES"

if [ -z "$WINNER_TYPEALIAS" ]; then
  echo "" | tee -a "$LOG"
  echo "=== no candidate compiled; restoring the pre-probe file ===" | tee -a "$LOG"
  cp "$BACKUP" "$SRC"
  tail -60 "$LOG"
  echo "::warning::No Text.Layout idiom compiled. See 04-textlayout-probe.log."
  exit 1
fi

{
  echo ""
  echo "## Text.Layout idiom selected by the compiler"
  echo '```swift'
  echo "private typealias LayoutSlice = $WINNER_TYPEALIAS"
  echo "$WINNER_DRAW"
  echo '```'
  if [ "$ATTEMPT" = "1" ]; then
    echo "The committed code already used this idiom."
  else
    echo "The committed code used a different idiom — apply the two lines above to"
    echo "\`Sources/DesignSystem/ProsodyTextRenderer.swift\` permanently."
  fi
} | tee -a "$LOG" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

echo "WINNER: $WINNER_TYPEALIAS | $WINNER_DRAW"
diff -u "$BACKUP" "$SRC" >> "$LOG" 2>&1 || true
exit 0
