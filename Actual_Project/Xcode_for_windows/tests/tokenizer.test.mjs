import test from 'node:test';
import assert from 'node:assert/strict';
import { tokenize } from '../src/swift/tokenizer.mjs';

const kinds = (src) => tokenize(src).map((t) => [t.kind, t.text]);

test('tokenizer: keywords and types are distinguished', () => {
  const out = kinds('let x: Int = 1');
  assert.deepEqual(out, [
    ['keyword', 'let'],
    ['identifier', 'x'],
    ['punctuation', ':'],
    ['type', 'Int'],
    ['operator', '='],
    ['number', '1']
  ]);
});

test('tokenizer: // inside a string is not a comment', () => {
  const out = kinds('let url = "https://example.com"');
  const stringTokens = out.filter(([k]) => k === 'string');
  assert.equal(stringTokens.length, 1);
  assert.equal(stringTokens[0][1], '"https://example.com"');
  assert.equal(out.filter(([k]) => k === 'comment').length, 0);
});

test('tokenizer: quote inside a comment does not open a string', () => {
  const out = kinds('// a " quote\nlet x = 1');
  assert.equal(out[0][0], 'comment');
  assert.equal(out[0][1], '// a " quote');
  assert.equal(out.filter(([k]) => k === 'string').length, 0);
});

test('tokenizer: multiline block comments nest', () => {
  const src = '/* outer /* inner */ still */ let y = 2';
  const out = kinds(src);
  assert.equal(out[0][0], 'comment');
  assert.ok(out[0][1].includes('still'), 'nested block comment should end at the outer terminator');
});

test('tokenizer: raw strings with hashes', () => {
  const out = kinds('let r = #"a \\" b"#');
  const s = out.find(([k]) => k === 'string');
  assert.ok(s, 'raw string should tokenize as a string');
  assert.ok(s[1].startsWith('#"'));
});

test('tokenizer: compiler directives are their own kind', () => {
  const out = kinds('#if os(iOS)\nlet a = 1\n#endif');
  assert.deepEqual(out[0], ['directive', '#if']);
  assert.ok(out.some(([k, t]) => k === 'directive' && t === '#endif'));
});

test('tokenizer: attributes', () => {
  const out = kinds('@MainActor struct X {}');
  assert.deepEqual(out[0], ['attribute', '@MainActor']);
});

test('tokenizer: a decimal point after a digit is not member access', () => {
  const out = kinds('let f = 1.5');
  const num = out.find(([k]) => k === 'number');
  assert.equal(num[1], '1.5');
});

test('tokenizer: 1.foo keeps the dot as member access', () => {
  const out = kinds('1.foo');
  const num = out[0];
  assert.equal(num[1], '1');
});

test('tokenizer: multi-character operators prefer the longest match', () => {
  const out = kinds('a ?? b');
  assert.ok(out.some(([k, t]) => k === 'operator' && t === '??'));
});

test('tokenizer: function names before "(" are marked', () => {
  const out = kinds('render(x)');
  assert.deepEqual(out[0], ['function', 'render']);
});

test('tokenizer: offsets map back to the exact source text', () => {
  const src = 'let greeting = "hi" // done';
  for (const t of tokenize(src)) {
    assert.equal(src.slice(t.start, t.end), t.text, `offset mismatch for ${t.kind}`);
  }
});
