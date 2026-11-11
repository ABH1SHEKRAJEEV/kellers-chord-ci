import test from 'node:test';
import assert from 'node:assert/strict';
import { parseManifest } from '../src/swift/manifest.mjs';

const REAL = `
// swift-tools-version: 6.0
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "KellersChord",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [
        .iOSApplication(
            name: "KellersChord",
            targets: ["AppModule"],
            bundleIdentifier: "com.srm.kellerschord",
            appIcon: .placeholder(icon: .waveform),
            capabilities: [
                .microphone(purposeString: "Analyze your voice."),
                .speechRecognition(purposeString: "Transcribe offline.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources",
            resources: [.process("Resources")]
        )
    ]
)
`;

test('manifest: reads name, tools version and platforms', () => {
  const m = parseManifest(REAL);
  assert.equal(m.name, 'KellersChord');
  assert.equal(m.toolsVersion, '6.0');
  assert.equal(m.platforms.iOS, '18.0');
  assert.equal(m.platforms.macOS, '15.0');
  assert.equal(m.ok, true);
});

test('manifest: reads the iOSApplication product', () => {
  const m = parseManifest(REAL);
  assert.equal(m.products.length, 1);
  const p = m.products[0];
  assert.equal(p.kind, 'iOSApplication');
  assert.equal(p.name, 'KellersChord');
  assert.equal(p.bundleIdentifier, 'com.srm.kellerschord');
  assert.equal(p.appIcon, 'placeholder');
  assert.deepEqual(p.targets, ['AppModule']);
});

test('manifest: reads capability purpose strings', () => {
  const m = parseManifest(REAL);
  const caps = m.products[0].capabilities;
  assert.equal(caps.length, 2);
  assert.equal(caps[0].name, 'microphone');
  assert.equal(caps[1].purpose, 'Transcribe offline.');
});

test('manifest: reads the executable target and its resources', () => {
  const m = parseManifest(REAL);
  assert.equal(m.targets.length, 1);
  assert.equal(m.targets[0].name, 'AppModule');
  assert.equal(m.targets[0].path, 'Sources');
  assert.deepEqual(m.targets[0].resources, ['Resources']);
});

test('manifest: a product pointing at an undeclared target warns', () => {
  const m = parseManifest(REAL.replace('"AppModule"]', '"Missing"]'));
  assert.ok(m.warnings.some((w) => w.includes('Missing')));
});

test('manifest: .iOSApplication without the import warns', () => {
  const m = parseManifest(REAL.replace('import AppleProductTypes', ''));
  assert.ok(m.warnings.some((w) => w.includes('AppleProductTypes')));
});

test('manifest: no Package() at all is a clean failure', () => {
  const m = parseManifest('print("hello")');
  assert.equal(m.ok, false);
  assert.ok(m.warnings.length > 0);
});

test('manifest: a manifest with no targets warns', () => {
  const m = parseManifest('let package = Package(name: "X", platforms: [], products: [], targets: [])');
  assert.ok(m.warnings.some((w) => w.includes('No target')));
});
