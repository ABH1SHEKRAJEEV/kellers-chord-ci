import test from 'node:test';
import assert from 'node:assert/strict';
import { analyzeFile } from '../src/swift/analyzer.mjs';

const codes = (src) => analyzeFile('test.swift', src).diagnostics.map((d) => d.code);

test('analyzer: balanced source produces no structural errors', () => {
  const src = `
struct A {
    func f(_ x: Int) -> Int {
        if x > 0 { return x }
        return 0
    }
}
`;
  const d = analyzeFile('test.swift', src).diagnostics;
  assert.equal(d.filter((x) => x.severity === 'error').length, 0);
});

test('analyzer: an unclosed brace is an error', () => {
  const d = analyzeFile('test.swift', 'struct A {\n  func f() {}\n').diagnostics;
  assert.ok(d.some((x) => x.code === 'syntax-balance' && x.severity === 'error'));
});

test('analyzer: a stray closing brace is an error', () => {
  const d = analyzeFile('test.swift', 'let a = 1\n}\n').diagnostics;
  assert.ok(d.some((x) => x.code === 'syntax-balance'));
});

test('analyzer: mismatched delimiters name the opener line', () => {
  const d = analyzeFile('test.swift', 'f(1, 2]\n').diagnostics;
  const hit = d.find((x) => x.code === 'syntax-balance');
  assert.ok(hit, 'should report a mismatch');
  assert.match(hit.message, /line 1/);
});

test('analyzer: brackets inside strings do not count', () => {
  const d = analyzeFile('test.swift', 'let s = "{{{ ((("\n').diagnostics;
  assert.equal(d.filter((x) => x.code === 'syntax-balance').length, 0);
});

test('analyzer: brackets inside comments do not count', () => {
  const d = analyzeFile('test.swift', '// {{{ (((\nlet a = 1\n').diagnostics;
  assert.equal(d.filter((x) => x.code === 'syntax-balance').length, 0);
});

test('analyzer: unbalanced delimiters inside a string do not hide the real error', () => {
  const d = analyzeFile('test.swift', 'let s = "ok"\nstruct A {\n').diagnostics;
  assert.ok(d.some((x) => x.code === 'syntax-balance'));
});

test('analyzer: TODO and FIXME are flagged', () => {
  const d = analyzeFile('test.swift', '// TODO: finish\n// FIXME: broken\n').diagnostics;
  assert.equal(d.filter((x) => x.code === 'placeholder').length, 2);
});

test('analyzer: a clean file has no placeholder findings', () => {
  const d = analyzeFile('test.swift', 'let a = 1\n').diagnostics;
  assert.equal(d.filter((x) => x.code === 'placeholder').length, 0);
});

test('analyzer: AVAudioSession outside #if os(iOS) warns', () => {
  const d = analyzeFile('test.swift', 'let s = AVAudioSession.sharedInstance()\n').diagnostics;
  const hit = d.find((x) => x.code === 'platform-guard');
  assert.ok(hit, 'should complain about an unguarded iOS API');
  assert.match(hit.message, /os\(iOS\)/);
});

test('analyzer: AVAudioSession inside #if os(iOS) is clean', () => {
  const src = '#if os(iOS)\nlet s = AVAudioSession.sharedInstance()\n#endif\n';
  const d = analyzeFile('test.swift', src).diagnostics;
  assert.equal(d.filter((x) => x.code === 'platform-guard').length, 0);
});

test('analyzer: NSHapticFeedbackManager requires the macOS guard', () => {
  const d = analyzeFile('test.swift', 'NSHapticFeedbackManager.defaultPerformer\n').diagnostics;
  assert.ok(d.some((x) => x.code === 'platform-guard' && /macOS/.test(x.message)));
});

test('analyzer: CHHapticEngine requires canImport(CoreHaptics)', () => {
  const d = analyzeFile('test.swift', 'let e = CHHapticEngine()\n').diagnostics;
  assert.ok(d.some((x) => x.code === 'platform-guard' && /CoreHaptics/.test(x.message)));
});

test('analyzer: an #else branch is not treated as guarded for the same API', () => {
  const src = '#if os(iOS)\nlet a = 1\n#else\nlet s = AVAudioSession.sharedInstance()\n#endif\n';
  const d = analyzeFile('test.swift', src).diagnostics;
  // The #else branch is still inside an #if region, so it is guarded.
  assert.equal(d.filter((x) => x.code === 'platform-guard').length, 0);
});

test('analyzer: a private member never referenced is reported as info', () => {
  const src = 'struct A {\n    private let unused = 1\n    let used = 2\n}\n';
  const d = analyzeFile('test.swift', src).diagnostics;
  const hit = d.find((x) => x.code === 'unused-private');
  assert.ok(hit);
  assert.equal(hit.severity, 'info');
  assert.match(hit.message, /unused/);
});

test('analyzer: a private member that is referenced is not reported', () => {
  const src = 'struct A {\n    private let v = 1\n    func f() -> Int { v }\n}\n';
  const d = analyzeFile('test.swift', src).diagnostics;
  assert.equal(d.filter((x) => x.code === 'unused-private').length, 0);
});

test('analyzer: stats count lines, symbols and severities', () => {
  const src = 'struct A {\n    func f() {}\n}\n';
  const { stats } = analyzeFile('test.swift', src);
  // A trailing newline adds a final empty element, matching how editors number lines.
  assert.equal(stats.lines, 4);
  assert.equal(stats.nonEmptyLines, 3);
  assert.equal(stats.types, 1);
  assert.equal(stats.functions, 1);
  assert.equal(stats.errors, 0);
});

test('analyzer: unterminated string is an error', () => {
  const d = analyzeFile('test.swift', 'let s = "oops\nlet t = 1\n').diagnostics;
  assert.ok(d.some((x) => x.code === 'syntax-string'));
});
