/**
 * Swift source tokenizer.
 *
 * Produces a flat token stream for syntax highlighting and structural analysis.
 * This is deliberately a lexer, not a parser: it understands the lexical rules of
 * Swift well enough to never be fooled by a `//` inside a string or a `"` inside a
 * comment, which is the failure mode that breaks naive regex highlighters.
 *
 * Token kinds are a closed vocabulary; every token carries a byte offset and a
 * length so the UI can map it onto the original text exactly.
 */

/** @typedef {'keyword'|'type'|'string'|'number'|'comment'|'attribute'|'directive'|'property'|'function'|'operator'|'punctuation'|'identifier'|'plain'} TokenKind */

/** Reserved words that read as control flow or declarations. */
const KEYWORDS = new Set([
  'actor', 'associatedtype', 'as', 'async', 'await', 'break', 'case', 'catch',
  'class', 'continue', 'convenience', 'defer', 'default', 'deinit', 'deinit',
  'didSet', 'do', 'dynamic', 'else', 'enum', 'extension', 'fallthrough', 'false',
  'fileprivate', 'final', 'for', 'func', 'get', 'guard', 'if', 'import', 'in',
  'indirect', 'init', 'inout', 'internal', 'is', 'lazy', 'let', 'mutating',
  'nil', 'nonisolated', 'open', 'operator', 'optional', 'override', 'private',
  'protocol', 'public', 'repeat', 'required', 'rethrows', 'return', 'self',
  'Self', 'set', 'some', 'static', 'struct', 'subscript', 'super', 'switch',
  'throws', 'throw', 'true', 'try', 'typealias', 'unowned', 'var', 'weak',
  'where', 'while', 'willSet', 'any', 'each', 'borrowing', 'consuming'
]);

/** Built-in types and protocol names highlighted distinctly from user types. */
const BUILTIN_TYPES = new Set([
  'Int', 'Double', 'Float', 'String', 'Bool', 'Character', 'Array', 'Dictionary',
  'Set', 'Optional', 'Void', 'Any', 'AnyObject', 'Error', 'Result', 'UUID',
  'Date', 'CGFloat', 'CGPoint', 'CGRect', 'CGSize', 'TimeInterval', 'Data',
  'URL', 'Task', 'Actor', 'Sendable', 'Codable', 'Equatable', 'Hashable',
  'Comparable', 'Identifiable', 'CaseIterable', 'AsyncSequence'
]);

/** SwiftUI / Apple framework types that deserve their own colour. */
const FRAMEWORK_TYPES = new Set([
  'View', 'Text', 'Color', 'Font', 'Image', 'Button', 'VStack', 'HStack', 'ZStack',
  'Canvas', 'Path', 'Shape', 'Circle', 'Rectangle', 'RoundedRectangle', 'Capsule',
  'Binding', 'State', 'Environment', 'Animation', 'Canvas', 'GraphicsContext',
  'TextRenderer', 'Animatable', 'StrokeStyle', 'GeometryReader', 'MeshGradient',
  'LinearGradient', 'TimelineView', 'DragGesture', 'TapGesture', 'AngularGradient'
]);

/** Two-character and longer operators, longest first so matching is greedy. */
const MULTI_CHAR_OPERATORS = [
  '===', '!==', '...', '..<', '->>', '->', '==', '!=', '<=', '>=', '&&', '||',
  '+=', '-=', '*=', '/=', '??', '?.', '<<', '>>', '=>'
];

/** Is the byte at `i` a decimal digit? */
function isDigit(ch) {
  return ch >= '0' && ch <= '9';
}

/** Is this character legal at the start of an identifier? */
function isIdentStart(ch) {
  return (ch >= 'a' && ch <= 'z')
    || (ch >= 'A' && ch <= 'Z')
    || ch === '_'
    || ch === '$';
}

/** Is this character legal inside an identifier? */
function isIdentPart(ch) {
  return isIdentStart(ch) || isDigit(ch);
}

/**
 * Tokenize Swift source text.
 *
 * @param {string} source
 * @returns {Array<{kind: TokenKind, start: number, end: number, text: string}>}
 */
export function tokenize(source) {
  /** @type {Array<{kind: TokenKind, start: number, end: number, text: string}>} */
  const tokens = [];
  const len = source.length;
  let i = 0;

  // Emit a token and advance.
  const push = (kind, start, end) => {
    tokens.push({ kind, start, end, text: source.slice(start, end) });
  };

  while (i < len) {
    const ch = source[i];
    const next = source[i + 1];

    // ── Line comments ──────────────────────────────────────────────────────
    if (ch === '/' && next === '/') {
      let end = i + 2;
      while (end < len && source[end] !== '\n') end += 1;
      push('comment', i, end);
      i = end;
      continue;
    }

    // ── Block comments (nestable in Swift) ─────────────────────────────────
    if (ch === '/' && next === '*') {
      let end = i + 2;
      let depth = 1;
      while (end < len && depth > 0) {
        if (source[end] === '/' && source[end + 1] === '*') {
          depth += 1;
          end += 2;
        } else if (source[end] === '*' && source[end + 1] === '/') {
          depth -= 1;
          end += 2;
        } else {
          end += 1;
        }
      }
      push('comment', i, end);
      i = end;
      continue;
    }

    // ── Raw strings: #"..."# and ##"..."## ─────────────────────────────────
    if (ch === '#') {
      let hashes = 0;
      let probe = i;
      while (source[probe] === '#') { hashes += 1; probe += 1; }

      if (source[probe] === '"') {
        const closer = '"' + '#'.repeat(hashes);
        let end = probe + 1;
        let multiline = false;
        if (source[probe + 1] === '"' && source[probe + 2] === '"') {
          multiline = true;
          end = probe + 3;
        }
        const terminator = multiline ? '"""' + '#'.repeat(hashes) : closer;
        while (end < len) {
          if (source.startsWith(terminator, end)) {
            end += terminator.length;
            break;
          }
          end += 1;
        }
        push('string', i, end);
        i = end;
        continue;
      }

      // Compiler directive: #if, #elseif, #else, #endif, #available ...
      let end = i + 1;
      while (end < len && isIdentPart(source[end])) end += 1;
      if (end > i + 1) {
        push('directive', i, end);
        i = end;
        continue;
      }

      // Attribute: #[...] is not Swift; treat a lone # as punctuation.
      push('punctuation', i, i + 1);
      i += 1;
      continue;
    }

    // ── String literals ────────────────────────────────────────────────────
    if (ch === '"') {
      const isMultiline = source.startsWith('"""', i);
      const quote = isMultiline ? '"""' : '"';
      let end = i + quote.length;
      let closed = false;
      while (end < len) {
        if (source[end] === '\\') { end += 2; continue; }
        if (source.startsWith(quote, end)) {
          end += quote.length;
          closed = true;
          break;
        }
        if (!isMultiline && source[end] === '\n') break;
        end += 1;
      }
      push('string', i, end);
      i = closed ? end : Math.min(end, len);
      continue;
    }

    // ── Attributes: @MainActor, @State, @escaping ... ──────────────────────
    if (ch === '@') {
      let end = i + 1;
      while (end < len && isIdentPart(source[end])) end += 1;
      if (end > i + 1) {
        push('attribute', i, end);
        i = end;
        continue;
      }
      push('punctuation', i, i + 1);
      i += 1;
      continue;
    }

    // ── Numbers ────────────────────────────────────────────────────────────
    if (isDigit(ch)) {
      let end = i;
      while (end < len && (isDigit(source[end]) || /[.xXa-fA-F_eEpP]/.test(source[end]))) {
        // Stop a trailing `.` that begins member access (e.g. `1.foo`).
        if (source[end] === '.' && !isDigit(source[end + 1] ?? '')) break;
        end += 1;
      }
      push('number', i, end);
      i = end;
      continue;
    }

    // ── Identifiers, keywords, types ───────────────────────────────────────
    if (isIdentStart(ch)) {
      let end = i;
      while (end < len && isIdentPart(source[end])) end += 1;
      const word = source.slice(i, end);

      let kind = /** @type {TokenKind} */ ('identifier');
      if (KEYWORDS.has(word)) {
        kind = 'keyword';
      } else if (BUILTIN_TYPES.has(word) || FRAMEWORK_TYPES.has(word)) {
        kind = 'type';
      } else if (word[0] >= 'A' && word[0] <= 'Z') {
        // User-defined type by Swift naming convention.
        kind = 'type';
      } else if (source[end] === '(') {
        kind = 'function';
      }

      push(kind, i, end);
      i = end;
      continue;
    }

    // ── Operators ──────────────────────────────────────────────────────────
    let matchedOp = null;
    for (const op of MULTI_CHAR_OPERATORS) {
      if (source.startsWith(op, i)) { matchedOp = op; break; }
    }
    if (matchedOp) {
      push('operator', i, i + matchedOp.length);
      i += matchedOp.length;
      continue;
    }

    // ── Whitespace is skipped so the token stream is dense ─────────────────
    if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
      i += 1;
      continue;
    }

    // ── Single-char operators vs. punctuation ──────────────────────────────
    if ('+-*/%<>=!&|^~?'.includes(ch)) {
      push('operator', i, i + 1);
      i += 1;
      continue;
    }

    push('punctuation', i, i + 1);
    i += 1;
  }

  return tokens;
}
