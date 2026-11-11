/**
 * Swift symbol indexer.
 *
 * Extracts the declarations a navigator needs — types, functions, properties,
 * cases, extensions — with enough context to describe them in a jump bar. It is a
 * brace-depth walker over the token stream rather than a parser: Swift's grammar is
 * too large to fully implement here, but every declaration form starts with a
 * keyword that this walker recognises at a known nesting depth.
 *
 * The indexer is intentionally tolerant. A file in a half-finished state still
 * yields the symbols it does contain.
 */

import { tokenize } from './tokenizer.mjs';

/** Declaration keywords that introduce a named type. */
const TYPE_KEYWORDS = new Set(['struct', 'class', 'enum', 'actor', 'protocol', 'extension']);

/** Declaration keywords that introduce a member. */
const MEMBER_KEYWORDS = new Set(['func', 'var', 'let', 'init', 'deinit', 'subscript', 'typealias', 'case']);

/**
 * @typedef {{
 *   name: string,
 *   kind: 'struct'|'class'|'enum'|'actor'|'protocol'|'extension'|'func'|'var'|'let'|'init'|'deinit'|'subscript'|'typealias'|'case',
 *   line: number,
 *   column: number,
 *   depth: number,
 *   parent: string|null,
 *   signature: string
 * }} Symbol
 */

/** Convert a character offset into 0-based line/column. */
export function offsetToPosition(source, offset) {
  let line = 0;
  let lastBreak = -1;
  for (let i = 0; i < offset && i < source.length; i += 1) {
    if (source[i] === '\n') { line += 1; lastBreak = i; }
  }
  return { line, column: offset - lastBreak - 1 };
}

/**
 * Read the declaration signature text starting at a token index, ending at the
 * first `{` (for braced declarations) or newline.
 */
function signatureAt(source, tokens, startIdx) {
  let out = '';
  for (let i = startIdx; i < tokens.length && i < startIdx + 40; i += 1) {
    const t = tokens[i];
    if (t.text === '{') break;
    if (t.text === '\n') break;
    out += source.slice(t.start, t.end);
    const next = tokens[i + 1];
    if (next && next.start > t.end) out += ' ';
  }
  return out.replace(/\s+/g, ' ').trim();
}

/**
 * Index one Swift source file.
 *
 * @param {string} source
 * @returns {{symbols: Symbol[], depthErrors: Array<{line: number, message: string}>}}
 */
export function indexFile(source) {
  const tokens = tokenize(source);
  /** @type {Symbol[]} */
  const symbols = [];
  const depthErrors = [];

  // Track the open-brace stack and the type name at each depth.
  let depth = 0;
  /** @type {Array<string|null>} */
  const scopeNames = [null];

  for (let i = 0; i < tokens.length; i += 1) {
    const tok = tokens[i];

    if (tok.text === '}') {
      depth -= 1;
      if (depth < 0) {
        const pos = offsetToPosition(source, tok.start);
        depthErrors.push({ line: pos.line + 1, message: 'Unmatched closing brace.' });
        depth = 0;
        continue;
      }
      scopeNames.length = depth + 1;
      continue;
    }

    if (tok.text === '{') {
      depth += 1;
      // The name of the scope opened here is the last type declared at the
      // previous depth, which is already in scopeNames[depth - 1].
      scopeNames[depth] = scopeNames[depth] ?? null;
      continue;
    }

    if (tok.kind !== 'keyword') continue;

    // ── Type declarations ───────────────────────────────────────────────────
    if (TYPE_KEYWORDS.has(tok.text)) {
      const nameTok = tokens[i + 1];
      if (!nameTok || (nameTok.kind !== 'type' && nameTok.kind !== 'identifier')) continue;

      const pos = offsetToPosition(source, tok.start);
      const kind = /** @type {Symbol['kind']} */ (tok.text);

      symbols.push({
        name: nameTok.text,
        kind,
        line: pos.line + 1,
        column: pos.column + 1,
        depth,
        parent: depth > 0 ? scopeNames[depth] : null,
        signature: signatureAt(source, tokens, i)
      });

      // The next `{` opens this type's body; register the name for that depth.
      for (let j = i + 2; j < tokens.length; j += 1) {
        if (tokens[j].text === '{') { scopeNames[depth + 1] = nameTok.text; break; }
        if (tokens[j].text === '}' || tokens[j].text === ';') break;
      }
      continue;
    }

    // ── Members ─────────────────────────────────────────────────────────────
    if (MEMBER_KEYWORDS.has(tok.text)) {
      // `case` inside an enum has comma-separated names; record each.
      if (tok.text === 'case') {
        const pos = offsetToPosition(source, tok.start);
        let j = i + 1;
        let collected = [];
        while (j < tokens.length && tokens[j].text !== '\n' && tokens[j].text !== '{') {
          if (tokens[j].kind === 'type' || tokens[j].kind === 'identifier') {
            collected.push({ text: tokens[j].text, start: tokens[j].start });
          }
          j += 1;
        }
        for (const c of collected) {
          const cp = offsetToPosition(source, c.start);
          symbols.push({
            name: c.text,
            kind: 'case',
            line: cp.line + 1,
            column: cp.column + 1,
            depth,
            parent: depth > 0 ? scopeNames[depth] : null,
            signature: `case ${c.text}`
          });
        }
        if (collected.length === 0) {
          symbols.push({
            name: 'case',
            kind: 'case',
            line: pos.line + 1,
            column: pos.column + 1,
            depth,
            parent: depth > 0 ? scopeNames[depth] : null,
            signature: signatureAt(source, tokens, i)
          });
        }
        continue;
      }

      // `init` may be followed by `?`, `!`, or `(`.
      let nameIdx = i + 1;
      while (nameIdx < tokens.length && ['?', '!', '<'].includes(tokens[nameIdx].text)) {
        nameIdx += 1;
      }
      const nameTok = tokens[nameIdx];
      if (!nameTok) continue;

      const isInitLike = tok.text === 'init' || tok.text === 'deinit' || tok.text === 'subscript';
      if (!isInitLike && nameTok.kind !== 'type' && nameTok.kind !== 'identifier' && nameTok.kind !== 'function') {
        continue;
      }

      const pos = offsetToPosition(source, tok.start);
      symbols.push({
        name: isInitLike ? tok.text : nameTok.text,
        kind: /** @type {Symbol['kind']} */ (tok.text),
        line: pos.line + 1,
        column: pos.column + 1,
        depth,
        parent: depth > 0 ? scopeNames[depth] : null,
        signature: signatureAt(source, tokens, i)
      });
      continue;
    }
  }

  if (depth !== 0) {
    depthErrors.push({
      line: source.split('\n').length,
      message: `${depth} unclosed brace${depth === 1 ? '' : 's'} at end of file.`
    });
  }

  return { symbols, depthErrors };
}

/**
 * Group a flat symbol list into a tree by `parent`.
 *
 * @param {Symbol[]} symbols
 */
export function buildSymbolTree(symbols) {
  const roots = [];
  const byName = new Map();

  for (const s of symbols) {
    if (!byName.has(s.name)) byName.set(s.name, []);
    byName.get(s.name).push(s);
  }

  const typeKinds = new Set(['struct', 'class', 'enum', 'actor', 'protocol', 'extension']);
  for (const s of symbols) {
    if (s.parent && typeKinds.has(s.kind) === false) {
      // member: attach in a later pass
      continue;
    }
    if (typeKinds.has(s.kind) && !s.parent) roots.push({ ...s, children: [] });
  }

  for (const s of symbols) {
    if (!s.parent) continue;
    const candidates = roots.filter((r) => r.name === s.parent);
    if (candidates.length > 0) {
      candidates[candidates.length - 1].children.push({ ...s, children: [] });
    } else {
      roots.push({ ...s, children: [] });
    }
  }

  return roots;
}
