/**
 * Swift Package manifest reader.
 *
 * `Package.swift` is real Swift code, not a data format, so this is not a full
 * evaluator. Instead it applies the same strategy Xcode uses for the common case:
 * locate the declarations by their nested-call shape and read the string literals
 * and enum cases out of them. Every recognised field is optional and every failure
 * is reported rather than thrown, because a manifest that a human forgot to finish
 * should still open in an editor.
 *
 * Observed shapes it understands (all from SwiftPM / AppleProductTypes):
 *   Package(name:, platforms:[.iOS("18.0"), .macOS("15.0")], products:, targets:)
 *   .iOSApplication(name:, targets:, bundleIdentifier:, ... capabilities:[...])
 *   .executableTarget(name:, path:, resources:[.process("Resources")])
 */

/** Extract every string literal from a source range, in order. */
function literals(text) {
  const out = [];
  const re = /"((?:[^"\\]|\\.)*)"/g;
  let m;
  while ((m = re.exec(text)) !== null) out.push(m[1]);
  return out;
}

/** Extract the argument list of the first `callee(...)` call in `text`. */
function callArgs(text, callee) {
  const idx = text.indexOf(callee);
  if (idx === -1) return null;

  // `callee` may or may not include its own `(`. Find the paren that belongs to
  // this call rather than the next unrelated one.
  const parenSearch = callee.endsWith('(') ? idx + callee.length - 1 : idx + callee.length;
  const open = text.indexOf('(', parenSearch);
  if (open === -1) return null;

  let depth = 0;
  for (let i = open; i < text.length; i += 1) {
    const ch = text[i];
    if (ch === '"' || ch === "'") {
      // Skip string literals so a paren inside a purpose string cannot unbalance.
      const quote = ch;
      i += 1;
      while (i < text.length) {
        if (text[i] === '\\') { i += 2; continue; }
        if (text[i] === quote) break;
        i += 1;
      }
      continue;
    }
    if (ch === '(') depth += 1;
    else if (ch === ')') {
      depth -= 1;
      if (depth === 0) return text.slice(open + 1, i);
    }
  }
  return text.slice(open + 1);
}

/** Extract the `[...]` block that follows `key:` in an argument list. */
function arrayArg(text, key) {
  if (!text) return null;
  const re = new RegExp(`\\b${key}\\s*:\\s*\\[`);
  const m = text.match(re);
  if (!m) return null;
  const open = m.index + m[0].length - 1;
  let depth = 0;
  for (let i = open; i < text.length; i += 1) {
    const ch = text[i];
    if (ch === '"') {
      i += 1;
      while (i < text.length) {
        if (text[i] === '\\') { i += 2; continue; }
        if (text[i] === '"') break;
        i += 1;
      }
      continue;
    }
    if (ch === '[') depth += 1;
    else if (ch === ']') {
      depth -= 1;
      if (depth === 0) return text.slice(open + 1, i);
    }
  }
  return null;
}

/** Read `key: "string"` style arguments. */
function stringArg(args, key) {
  if (!args) return null;
  const re = new RegExp(`\\b${key}\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = args.match(re);
  return m ? m[1] : null;
}

/** Read `key: .enumCase` style arguments. */
function enumArg(args, key) {
  if (!args) return null;
  const re = new RegExp(`\\b${key}\\s*:\\s*\\.(\\w+)`);
  const m = args.match(re);
  return m ? m[1] : null;
}

/** Read `platforms: [.iOS("18.0"), ...]` into a plain map. */
function parsePlatforms(args) {
  const out = {};
  if (!args) return out;

  // `platforms` is followed by `: [ ... ]`, not by a call, so locate the block
  // explicitly rather than going through `callArgs`.
  const m = args.match(/\bplatforms\s*:\s*\[([\s\S]*?)\]/);
  if (!m) return out;

  const re = /\.(iOS|macOS|watchOS|tvOS|visionOS|macCatalyst)\s*\(\s*"([^"]+)"\s*\)/g;
  let pm;
  while ((pm = re.exec(m[1])) !== null) out[pm[1]] = pm[2];
  return out;
}

/** Read `capabilities: [.microphone(purposeString: "..."), ...]`. */
function parseCapabilities(args) {
  const block = arrayArg(args ?? '', 'capabilities');
  if (!block) return [];
  const out = [];
  const re = /\.(\w+)\s*\(\s*purposeString\s*:\s*"((?:[^"\\]|\\.)*)"/g;
  let m;
  while ((m = re.exec(block)) !== null) out.push({ name: m[1], purpose: m[2] });
  return out;
}

/**
 * Parse a `Package.swift` source string.
 *
 * @param {string} source
 * @returns {{
 *   ok: boolean,
 *   warnings: string[],
 *   name: string|null,
 *   platforms: Record<string,string>,
 *   products: Array<{kind: string, name: string, targets: string[], bundleIdentifier: string|null, appIcon: string|null, capabilities: Array<{name: string, purpose: string}>, accentColor: string|null}>,
 *   targets: Array<{kind: string, name: string, path: string|null, resources: string[], dependencies: string[]}>,
 *   toolsVersion: string|null,
 *   usesAppleProductTypes: boolean
 * }}
 */
export function parseManifest(source) {
  const warnings = [];
  const result = {
    ok: true,
    warnings,
    name: null,
    platforms: {},
    products: [],
    targets: [],
    toolsVersion: null,
    usesAppleProductTypes: false
  };

  // `// swift-tools-version: 6.0`
  const tv = source.match(/swift-tools-version\s*:\s*([\d.]+)/);
  if (tv) result.toolsVersion = tv[1];

  result.usesAppleProductTypes = /import\s+AppleProductTypes/.test(source);

  // The outer `Package(...)` call.
  const pkgArgs = callArgs(source, 'Package(');
  if (pkgArgs === null) {
    warnings.push('No `Package(` declaration found; this may not be a SwiftPM manifest.');
    result.ok = false;
    return result;
  }

  result.name = stringArg(pkgArgs, 'name');
  result.platforms = parsePlatforms(pkgArgs);

  // ── Products ───────────────────────────────────────────────────────────────
  // Walk each product declaration by finding its leading `.kind(` marker.
  const productRe = /\.(iOSApplication|executable|library|macOSApplication)\s*\(/g;
  let pm;
  while ((pm = productRe.exec(pkgArgs)) !== null) {
    const kind = pm[1];
    const open = pm.index + pm[0].length - 1;
    let depth = 0;
    let close = open;
    for (let i = open; i < pkgArgs.length; i += 1) {
      if (pkgArgs[i] === '(') depth += 1;
      else if (pkgArgs[i] === ')') {
        depth -= 1;
        if (depth === 0) { close = i; break; }
      }
    }
    const args = pkgArgs.slice(open + 1, close);

    // `targets: ["AppModule"]`
    const targetBlock = arrayArg(args, 'targets');
    const targets = targetBlock ? literals(targetBlock) : [];

    result.products.push({
      kind,
      name: stringArg(args, 'name') ?? '(unnamed)',
      targets,
      bundleIdentifier: stringArg(args, 'bundleIdentifier'),
      appIcon: enumArg(args, 'appIcon'),
      accentColor: enumArg(args, 'accentColor'),
      capabilities: parseCapabilities(args)
    });
  }

  if (result.products.length === 0) {
    warnings.push('No product declarations found in the manifest.');
  }

  // ── Targets ────────────────────────────────────────────────────────────────
  const targetRe = /\.(executableTarget|target|testTarget|binaryTarget)\s*\(/g;
  let tm;
  while ((tm = targetRe.exec(pkgArgs)) !== null) {
    const kind = tm[1];
    const open = tm.index + tm[0].length - 1;
    let depth = 0;
    let close = open;
    for (let i = open; i < pkgArgs.length; i += 1) {
      if (pkgArgs[i] === '(') depth += 1;
      else if (pkgArgs[i] === ')') {
        depth -= 1;
        if (depth === 0) { close = i; break; }
      }
    }
    const args = pkgArgs.slice(open + 1, close);

    const resources = [];
    const resBlock = arrayArg(args, 'resources');
    if (resBlock) {
      const re = /\.(process|copy)\s*\(\s*"([^"]+)"/g;
      let rm;
      while ((rm = re.exec(resBlock)) !== null) {
        resources.push(rm[2]);
        if (rm[1] === 'copy') {
          warnings.push(`Target "${stringArg(args, 'name')}" uses .copy for "${rm[2]}"; .process is usually intended.`);
        }
      }
    }

    const depsBlock = arrayArg(args, 'dependencies');
    const dependencies = depsBlock ? literals(depsBlock) : [];

    result.targets.push({
      kind,
      name: stringArg(args, 'name') ?? '(unnamed)',
      path: stringArg(args, 'path'),
      resources,
      dependencies
    });
  }

  if (result.targets.length === 0) {
    warnings.push('No target declarations found; the package cannot build without at least one target.');
  }

  // Every product target must resolve to a declared target.
  const declared = new Set(result.targets.map((t) => t.name));
  for (const product of result.products) {
    for (const t of product.targets) {
      if (!declared.has(t)) {
        warnings.push(`Product "${product.name}" references target "${t}", which is not declared.`);
      }
    }
  }

  if (!result.usesAppleProductTypes && result.products.some((p) => p.kind === 'iOSApplication')) {
    warnings.push('.iOSApplication is used without `import AppleProductTypes`, which will not compile.');
  }

  return result;
}
