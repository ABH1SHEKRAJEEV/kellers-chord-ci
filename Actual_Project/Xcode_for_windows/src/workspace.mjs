/**
 * Workspace model: a `.swiftpm` package opened on disk.
 *
 * Owns path safety, file listing, and the cached index. Every path that arrives
 * from the network is resolved and then compared against the workspace root, so a
 * crafted `../` path cannot read outside the opened package. That check is the one
 * security boundary in this tool and it is enforced here rather than in the server.
 */

import fs from 'node:fs';
import path from 'node:path';
import { parseManifest } from './swift/manifest.mjs';
import { analyzeFile } from './swift/analyzer.mjs';
import { indexFile, buildSymbolTree } from './swift/indexer.mjs';

/** Directories never worth walking. */
const IGNORED_DIRS = new Set(['.git', '.build', 'node_modules', '.swiftpm', 'DerivedData']);

export class Workspace {
  /** @param {string} root absolute path to the .swiftpm package */
  constructor(root) {
    this.root = path.resolve(root);
    if (!fs.existsSync(this.root) || !fs.statSync(this.root).isDirectory()) {
      throw new Error(`Workspace root is not a directory: ${this.root}`);
    }
    /** @type {Map<string, {mtimeMs: number, result: ReturnType<typeof analyzeFile>}>} */
    this.cache = new Map();
  }

  /**
   * Resolve a client-supplied relative path against the root, refusing escapes.
   *
   * @param {string} relPath
   * @returns {string} absolute path
   */
  resolve(relPath) {
    const cleaned = String(relPath ?? '').replace(/^[/\\]+/, '');
    const abs = path.resolve(this.root, cleaned);
    const rel = path.relative(this.root, abs);

    if (rel === '..' || rel.startsWith(`..${path.sep}`) || path.isAbsolute(rel)) {
      const err = new Error('Path escapes the workspace root.');
      // @ts-expect-error - annotate for the server's error handler
      err.statusCode = 403;
      throw err;
    }
    return abs;
  }

  /** Convert an absolute path back to a forward-slash relative one. */
  relative(abs) {
    return path.relative(this.root, abs).split(path.sep).join('/');
  }

  /** Walk the tree, returning files and directories in stable order. */
  listTree(dir = this.root, depth = 0) {
    if (depth > 12) return [];

    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return [];
    }

    entries.sort((a, b) => {
      if (a.isDirectory() !== b.isDirectory()) return a.isDirectory() ? -1 : 1;
      return a.name.localeCompare(b.name);
    });

    /** @type {Array<any>} */
    const out = [];
    for (const entry of entries) {
      if (entry.name.startsWith('.') && entry.name !== '.gitkeep') continue;
      const abs = path.join(dir, entry.name);

      if (entry.isDirectory()) {
        if (IGNORED_DIRS.has(entry.name)) continue;
        out.push({
          type: 'directory',
          name: entry.name,
          path: this.relative(abs),
          children: this.listTree(abs, depth + 1)
        });
      } else {
        let size = 0;
        try { size = fs.statSync(abs).size; } catch { /* unreadable, report 0 */ }
        out.push({
          type: 'file',
          name: entry.name,
          path: this.relative(abs),
          size,
          language: entry.name.endsWith('.swift') ? 'swift' : 'text'
        });
      }
    }
    return out;
  }

  /** Read a file as UTF-8, refusing anything that is not a regular file. */
  readFile(relPath) {
    const abs = this.resolve(relPath);
    const stat = fs.statSync(abs);
    if (!stat.isFile()) {
      const err = new Error('Not a regular file.');
      // @ts-expect-error - annotate for the server's error handler
      err.statusCode = 400;
      throw err;
    }
    if (stat.size > 4 * 1024 * 1024) {
      const err = new Error('File is larger than the 4 MB editor limit.');
      // @ts-expect-error - annotate for the server's error handler
      err.statusCode = 413;
      throw err;
    }
    return fs.readFileSync(abs, 'utf8');
  }

  /** Write a file, creating parent directories as needed. */
  writeFile(relPath, content) {
    const abs = this.resolve(relPath);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, content, 'utf8');
    this.cache.delete(this.relative(abs));
    return { path: this.relative(abs), bytes: Buffer.byteLength(content, 'utf8') };
  }

  /** Parse the package manifest. */
  manifest() {
    const abs = path.join(this.root, 'Package.swift');
    if (!fs.existsSync(abs)) {
      return {
        ok: false,
        warnings: ['Package.swift not found at the workspace root.'],
        name: null,
        platforms: {},
        products: [],
        targets: [],
        toolsVersion: null,
        usesAppleProductTypes: false
      };
    }
    return parseManifest(fs.readFileSync(abs, 'utf8'));
  }

  /** Every Swift file path in the package. */
  swiftFiles() {
    const out = [];
    const walk = (dir) => {
      let entries;
      try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
      for (const e of entries) {
        const abs = path.join(dir, e.name);
        if (e.isDirectory()) {
          if (!IGNORED_DIRS.has(e.name)) walk(abs);
        } else if (e.name.endsWith('.swift')) {
          out.push(abs);
        }
      }
    };
    walk(this.root);
    return out.sort();
  }

  /** Analyse every Swift file, with an mtime cache. */
  diagnostics() {
    /** @type {any[]} */
    const all = [];
    let files = 0;
    let errors = 0;
    let warnings = 0;
    let infos = 0;

    for (const abs of this.swiftFiles()) {
      const rel = this.relative(abs);
      let stat;
      try { stat = fs.statSync(abs); } catch { continue; }

      const hit = this.cache.get(rel);
      if (hit && hit.mtimeMs === stat.mtimeMs) {
        all.push(...hit.result.diagnostics);
        files += 1;
        errors += hit.result.stats.errors;
        warnings += hit.result.stats.warnings;
        infos += hit.result.stats.infos;
        continue;
      }

      let source;
      try { source = fs.readFileSync(abs, 'utf8'); } catch { continue; }

      const result = analyzeFile(rel, source);
      this.cache.set(rel, { mtimeMs: stat.mtimeMs, result });
      all.push(...result.diagnostics);
      files += 1;
      errors += result.stats.errors;
      warnings += result.stats.warnings;
      infos += result.stats.infos;
    }

    return {
      files,
      summary: { errors, warnings, infos, total: all.length },
      diagnostics: all.sort((a, b) =>
        a.file.localeCompare(b.file) || a.line - b.line)
    };
  }

  /** Symbols for one file. */
  symbols(relPath) {
    const source = this.readFile(relPath);
    const { symbols } = indexFile(source);
    return { path: relPath, symbols, tree: buildSymbolTree(symbols) };
  }

  /** Aggregate stats for the whole package. */
  overview() {
    const manifest = this.manifest();
    const files = this.swiftFiles();

    let totalLines = 0;
    let totalBytes = 0;
    let typeCount = 0;
    let functionCount = 0;
    const perFile = [];

    for (const abs of files) {
      const rel = this.relative(abs);
      let source = '';
      try { source = fs.readFileSync(abs, 'utf8'); } catch { continue; }
      const { symbols } = indexFile(source);
      const lines = source.split('\n').length;
      totalLines += lines;
      totalBytes += Buffer.byteLength(source, 'utf8');
      const types = symbols.filter((s) => ['struct', 'class', 'enum', 'actor', 'protocol', 'extension'].includes(s.kind)).length;
      const funcs = symbols.filter((s) => s.kind === 'func').length;
      typeCount += types;
      functionCount += funcs;
      perFile.push({ path: rel, lines, bytes: Buffer.byteLength(source, 'utf8'), types, functions: funcs });
    }

    return {
      root: this.root,
      manifest,
      counts: {
        files: files.length,
        lines: totalLines,
        bytes: totalBytes,
        types: typeCount,
        functions: functionCount
      },
      perFile
    };
  }
}
