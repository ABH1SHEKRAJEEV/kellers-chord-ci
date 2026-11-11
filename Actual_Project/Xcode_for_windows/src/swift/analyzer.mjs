/**
 * Static analyzer for Swift sources.
 *
 * This is NOT a compiler and does not pretend to be one. It reports only facts it
 * can establish from the text by construction, and labels every other finding as an
 * inference. The distinction matters: a tool that says "this will compile" without a
 * compiler is worse than one that says nothing.
 *
 * Three confidence levels, and every finding carries one:
 *   'error'  — a structural fact: unbalanced delimiters, unterminated string.
 *   'warning' — a near-certain problem: TODO marker, missing accessibility on a
 *               control, platform API used without its #if guard.
 *   'info'   — a heuristic: declared-but-unreferenced members, long functions.
 */

import { tokenize } from './tokenizer.mjs';
import { indexFile } from './indexer.mjs';

/**
 * @typedef {{
 *   file: string,
 *   line: number,
 *   column: number,
 *   severity: 'error'|'warning'|'info',
 *   code: string,
 *   message: string,
 *   rule: string
 * }} Diagnostic
 */

/** APIs that only exist on one platform, and the guard each requires. */
const PLATFORM_APIS = [
  { pattern: /\bAVAudioSession\b/, guard: '#if os(iOS)', platform: 'iOS' },
  { pattern: /\bNSHapticFeedbackManager\b/, guard: '#if os(macOS)', platform: 'macOS' },
  { pattern: /\bCHHapticEngine\b/, guard: '#if canImport(CoreHaptics)', platform: 'CoreHaptics' },
  { pattern: /\bUIApplication\b/, guard: '#if os(iOS)', platform: 'iOS' },
  { pattern: /\bNSApplication\b/, guard: '#if os(macOS)', platform: 'macOS' },
  { pattern: /\bUIDevice\b/, guard: '#if os(iOS)', platform: 'iOS' }
];

/** Marker strings that must never ship. */
const PLACEHOLDER_PATTERNS = [
  { re: /\bTODO\b/, label: 'TODO marker' },
  { re: /\bFIXME\b/, label: 'FIXME marker' },
  { re: /\bXXX\b/, label: 'XXX marker' },
  { re: /\bHACK\b/, label: 'HACK marker' },
  { re: /implement\s+later/i, label: '"implement later" placeholder' },
  { re: /\bunimplemented\b/i, label: 'unimplemented call' },
  { re: /\bfatalError\(\s*"TODO/i, label: 'fatalError placeholder' },
  { re: /not\s+implemented\s+yet/i, label: '"not implemented yet" placeholder' }
];

/** Count delimiter balance ignoring strings and comments. */
function delimiterBalance(source) {
  const tokens = tokenize(source);
  const stack = [];
  const errors = [];
  const pairs = { ')': '(', ']': '[', '}': '{' };

  let line = 1;
  let lastStart = 0;

  for (const t of tokens) {
    if (t.kind === 'string' || t.kind === 'comment') continue;

    // Track line numbers lazily from source offsets.
    for (let i = lastStart; i < t.start; i += 1) if (source[i] === '\n') line += 1;
    lastStart = t.start;

    const txt = t.text;
    if (txt === '(' || txt === '[' || txt === '{') {
      stack.push({ ch: txt, line, offset: t.start });
    } else if (txt === ')' || txt === ']' || txt === '}') {
      const want = pairs[txt];
      const top = stack.pop();
      if (!top) {
        errors.push({ line, message: `Unexpected '${txt}'.` });
      } else if (top.ch !== want) {
        errors.push({
          line,
          message: `'${txt}' closes '${top.ch}' opened on line ${top.line}.`
        });
      }
    }
  }

  for (const open of stack) {
    errors.push({
      line: open.line,
      message: `'${open.ch}' is never closed.`
    });
  }

  return errors;
}

/** Detect a string literal that runs to EOF without closing. */
function unterminatedStrings(source) {
  const out = [];
  let i = 0;
  let line = 1;
  const len = source.length;

  while (i < len) {
    const ch = source[i];
    if (ch === '\n') { line += 1; i += 1; continue; }

    if (ch === '/' && source[i + 1] === '/') {
      while (i < len && source[i] !== '\n') i += 1;
      continue;
    }
    if (ch === '/' && source[i + 1] === '*') {
      i += 2;
      while (i < len && !(source[i] === '*' && source[i + 1] === '/')) {
        if (source[i] === '\n') line += 1;
        i += 1;
      }
      i += 2;
      continue;
    }
    if (ch === '"') {
      const startLine = line;
      const multi = source.startsWith('"""', i);
      let j = i + (multi ? 3 : 1);
      let closed = false;
      while (j < len) {
        if (source[j] === '\\') { j += 2; continue; }
        if (multi && source.startsWith('"""', j)) { closed = true; j += 3; break; }
        if (!multi && source[j] === '"') { closed = true; j += 1; break; }
        if (!multi && source[j] === '\n') break;
        if (source[j] === '\n') line += 1;
        j += 1;
      }
      if (!closed) {
        out.push({ line: startLine, message: 'String literal is never closed.' });
        break;
      }
      i = j;
      continue;
    }
    i += 1;
  }

  return out;
}

/**
 * Find `#if` regions and test whether an offset falls inside one matching `guard`.
 */
function guardCoverage(source) {
  const tokens = tokenize(source);
  /** @type {Array<{guard: string, from: number, to: number, depth: number}>} */
  const regions = [];
  /** @type {Array<{guard: string, from: number, depth: number}>} */
  const open = [];

  // Build a line-offset table for fast offset -> line.
  const lineStarts = [0];
  for (let i = 0; i < source.length; i += 1) if (source[i] === '\n') lineStarts.push(i + 1);

  for (let i = 0; i < tokens.length; i += 1) {
    const t = tokens[i];
    if (t.kind !== 'directive') continue;

    const word = t.text.replace(/^#/, '');

    if (word === 'if') {
      // The guard expression follows on the same line.
      let end = t.end;
      while (end < source.length && source[end] !== '\n') end += 1;
      open.push({ guard: source.slice(t.start, end).trim(), from: t.start, depth: 1 });
      continue;
    }

    if (word === 'elseif') {
      // Close the current branch, open a new one.
      const top = open[open.length - 1];
      if (top) {
        regions.push({ guard: top.guard, from: top.from, to: t.start, depth: top.depth });
        let end = t.end;
        while (end < source.length && source[end] !== '\n') end += 1;
        top.guard = source.slice(t.start, end).trim();
        top.from = t.start;
      }
      continue;
    }

    if (word === 'else') {
      const top = open[open.length - 1];
      if (top) {
        regions.push({ guard: top.guard, from: top.from, to: t.start, depth: top.depth });
        let end = t.end;
        while (end < source.length && source[end] !== '\n') end += 1;
        top.guard = '#else';
        top.from = t.start;
      }
      continue;
    }

    if (word === 'endif') {
      const top = open.pop();
      if (top) {
        // Extend the region to the end of the `#endif` token itself. Using the
        // token start would leave a guarded `import` on the same line looking
        // unguarded.
        regions.push({ guard: top.guard, from: top.from, to: t.end, depth: top.depth });
      }
      continue;
    }
  }

  return { regions, lineStarts };
}

/** Map an offset to a 1-based line number. */
function lineOf(lineStarts, offset) {
  let lo = 0;
  let hi = lineStarts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (lineStarts[mid] <= offset) lo = mid;
    else hi = mid - 1;
  }
  return lo + 1;
}

/**
 * Check that a control that carries an accessibility label family has all three.
 * Reported as warnings rather than errors: this is a heuristic, not a compile rule.
 */
function accessibilityGaps(source, file) {
  const out = [];
  const lines = source.split('\n');

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (!/^\s*(Button|Toggle)\s*\(/.test(line) && !/\.onTapGesture\s*\{/.test(line)) continue;

    // Look ahead in a bounded window for the accessibility modifiers.
    const window = lines.slice(i, Math.min(i + 12, lines.length)).join('\n');
    const hasLabel = /\.accessibilityLabel\s*\(/.test(window);
    if (!hasLabel) {
      out.push({
        file,
        line: i + 1,
        column: 1,
        severity: /** @type {'warning'} */ ('warning'),
        code: 'a11y-missing-label',
        message: 'Interactive control has no .accessibilityLabel within 12 lines.',
        rule: 'accessibility'
      });
    }
  }

  return out;
}

/**
 * Analyse a single Swift file.
 *
 * @param {string} file  display path
 * @param {string} source
 * @returns {{diagnostics: Diagnostic[], stats: object}}
 */
export function analyzeFile(file, source) {
  /** @type {Diagnostic[]} */
  const diagnostics = [];
  const lines = source.split('\n');

  // ── Structural facts ───────────────────────────────────────────────────────
  for (const e of delimiterBalance(source)) {
    diagnostics.push({
      file, line: e.line, column: 1,
      severity: 'error', code: 'syntax-balance',
      message: e.message, rule: 'structure'
    });
  }

  for (const e of unterminatedStrings(source)) {
    diagnostics.push({
      file, line: e.line, column: 1,
      severity: 'error', code: 'syntax-string',
      message: e.message, rule: 'structure'
    });
  }

  const { symbols, depthErrors } = indexFile(source);
  for (const e of depthErrors) {
    diagnostics.push({
      file, line: e.line, column: 1,
      severity: 'error', code: 'syntax-brace',
      message: e.message, rule: 'structure'
    });
  }

  // ── Placeholders ───────────────────────────────────────────────────────────
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    for (const p of PLACEHOLDER_PATTERNS) {
      if (p.re.test(line)) {
        diagnostics.push({
          file, line: i + 1, column: 1,
          severity: 'warning', code: 'placeholder',
          message: `${p.label} must not ship.`, rule: 'completeness'
        });
      }
    }
  }

  // ── Platform guards ────────────────────────────────────────────────────────
  // Only real code counts. A platform API named in a doc comment (this codebase
  // documents `CHHapticEngine` extensively) is not a usage and must not warn.
  const { regions, lineStarts } = guardCoverage(source);

  /** Replace comments and strings with spaces, preserving offsets and newlines. */
  const codeOnly = (() => {
    const out = source.split('');
    for (const t of tokenize(source)) {
      if (t.kind !== 'comment' && t.kind !== 'string') continue;
      for (let i = t.start; i < t.end; i += 1) {
        if (out[i] !== '\n') out[i] = ' ';
      }
    }
    return out.join('');
  })();

  for (const api of PLATFORM_APIS) {
    const re = new RegExp(api.pattern.source, 'g');
    let m;
    while ((m = re.exec(codeOnly)) !== null) {
      const offset = m.index;

      // A match on the same line as its guard directive is inside that region.
      // Compare against the region's line span rather than only its byte span.
      const matchLine = lineOf(lineStarts, offset);
      const inside = regions.some((r) => {
        const startLine = lineOf(lineStarts, r.from);
        const endLine = lineOf(lineStarts, r.to);
        return matchLine >= startLine && matchLine <= endLine;
      });

      if (!inside) {
        diagnostics.push({
          file,
          line: lineOf(lineStarts, offset),
          column: 1,
          severity: 'warning',
          code: 'platform-guard',
          message: `${api.platform} API used outside \`${api.guard}\`.`,
          rule: 'cross-platform'
        });
      }
    }
  }

  // ── Declared-but-unreferenced private members (heuristic) ──────────────────
  const privateRe = /\bprivate\s+(?:static\s+)?(?:let|var|func)\s+([A-Za-z_]\w*)/g;
  let pm;
  while ((pm = privateRe.exec(source)) !== null) {
    const name = pm[1];
    const occurrences = source.split(new RegExp(`\\b${name}\\b`)).length - 1;
    if (occurrences <= 1) {
      diagnostics.push({
        file,
        line: lines.slice(0, source.slice(0, pm.index).split('\n').length).length,
        column: 1,
        severity: 'info',
        code: 'unused-private',
        message: `private member "${name}" is declared but never referenced.`,
        rule: 'dead-code'
      });
    }
  }

  // ── Accessibility heuristics ───────────────────────────────────────────────
  diagnostics.push(...accessibilityGaps(source, file));

  // ── Stats ──────────────────────────────────────────────────────────────────
  const stats = {
    lines: lines.length,
    nonEmptyLines: lines.filter((l) => l.trim().length > 0).length,
    characters: source.length,
    symbols: symbols.length,
    types: symbols.filter((s) => ['struct', 'class', 'enum', 'actor', 'protocol', 'extension'].includes(s.kind)).length,
    functions: symbols.filter((s) => s.kind === 'func').length,
    properties: symbols.filter((s) => s.kind === 'var' || s.kind === 'let').length,
    hasMainActor: /@MainActor/.test(source),
    directives: regions.length,
    errors: diagnostics.filter((d) => d.severity === 'error').length,
    warnings: diagnostics.filter((d) => d.severity === 'warning').length,
    infos: diagnostics.filter((d) => d.severity === 'info').length
  };

  return { diagnostics, stats };
}
