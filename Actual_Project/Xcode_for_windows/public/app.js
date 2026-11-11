/**
 * Xcode for Windows — browser client.
 *
 * Talks to the local node server. All syntax colouring happens here so typing
 * never waits on a round trip; the server is consulted only for whole-file
 * analysis and indexing.
 */

// ── Element handles ────────────────────────────────────────────────────────
const $ = (id) => document.getElementById(id);

const els = {
  workspaceName: $('workspaceName'),
  manifestChip: $('manifestChip'),
  dirtyDot: $('dirtyDot'),
  saveBtn: $('saveBtn'),
  reindexBtn: $('reindexBtn'),
  tree: $('tree'),
  fileCount: $('fileCount'),
  packageInfo: $('packageInfo'),
  breadcrumb: $('breadcrumb'),
  editorMeta: $('editorMeta'),
  jumpbar: $('jumpbar'),
  gutter: $('gutter'),
  highlight: $('highlight'),
  editor: $('editor'),
  emptyState: $('emptyState'),
  issues: $('issues'),
  issueCount: $('issueCount'),
  statusMessage: $('statusMessage'),
  cursorPos: $('cursorPos'),
  issueSummary: $('issueSummary')
};

// ── State ──────────────────────────────────────────────────────────────────
const state = {
  activePath: null,
  activeContent: '',
  savedContent: '',
  diagnostics: [],
  severityFilter: 'all',
  openDirs: new Set(),
  tokenizer: null
};

/** Escape text for safe insertion as HTML. */
function escapeHtml(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

/** Set the status-bar message. */
function setStatus(message) {
  els.statusMessage.textContent = message;
}

/** Fetch JSON, surfacing server error text. */
async function getJson(url, options) {
  const res = await fetch(url, options);
  if (!res.ok) {
    let detail = `${res.status} ${res.statusText}`;
    try {
      const body = await res.json();
      if (body && body.error) detail = body.error;
    } catch { /* non-JSON error body, keep the status line */ }
    throw new Error(detail);
  }
  return res.json();
}

// ── Swift tokenizer (client-side mirror of src/swift/tokenizer.mjs) ─────────
/**
 * The server owns the authoritative tokenizer. The client keeps a compact copy
 * so highlighting is instant while typing; both must agree on token kinds, and
 * the golden tests assert the server side.
 */
const KEYWORDS = new Set([
  'actor', 'associatedtype', 'as', 'async', 'await', 'break', 'case', 'catch',
  'class', 'continue', 'convenience', 'defer', 'default', 'deinit', 'didSet',
  'do', 'dynamic', 'else', 'enum', 'extension', 'fallthrough', 'false',
  'fileprivate', 'final', 'for', 'func', 'get', 'guard', 'if', 'import', 'in',
  'indirect', 'init', 'inout', 'internal', 'is', 'lazy', 'let', 'mutating',
  'nil', 'nonisolated', 'open', 'operator', 'optional', 'override', 'private',
  'protocol', 'public', 'repeat', 'required', 'rethrows', 'return', 'self',
  'Self', 'set', 'some', 'static', 'struct', 'subscript', 'super', 'switch',
  'throws', 'throw', 'true', 'try', 'typealias', 'unowned', 'var', 'weak',
  'where', 'while', 'willSet', 'any', 'each', 'borrowing', 'consuming'
]);

const TYPES = new Set([
  'Int', 'Double', 'Float', 'String', 'Bool', 'Character', 'Array', 'Dictionary',
  'Set', 'Optional', 'Void', 'Any', 'AnyObject', 'Error', 'Result', 'UUID',
  'Date', 'CGFloat', 'CGPoint', 'CGRect', 'CGSize', 'TimeInterval', 'Data',
  'URL', 'Task', 'Actor', 'Sendable', 'Codable', 'Equatable', 'Hashable',
  'Comparable', 'Identifiable', 'CaseIterable', 'AsyncSequence', 'View', 'Text',
  'Color', 'Font', 'Image', 'Button', 'VStack', 'HStack', 'ZStack', 'Canvas',
  'Path', 'Shape', 'Circle', 'Rectangle', 'RoundedRectangle', 'Capsule',
  'Binding', 'State', 'Environment', 'Animation', 'GraphicsContext',
  'TextRenderer', 'Animatable', 'StrokeStyle', 'GeometryReader', 'MeshGradient',
  'LinearGradient', 'TimelineView', 'DragGesture', 'TapGesture', 'AngularGradient'
]);

const MULTI_OPS = [
  '===', '!==', '...', '..<', '->', '==', '!=', '<=', '>=', '&&', '||',
  '+=', '-=', '*=', '/=', '??', '?.', '<<', '>>'
];

/**
 * Convert Swift source to highlighted HTML.
 * @param {string} source
 * @returns {string}
 */
function highlightSwift(source) {
  let out = '';
  let i = 0;
  const len = source.length;

  const isIdentStart = (c) => /[A-Za-z_$]/.test(c);
  const isIdentPart = (c) => /[A-Za-z0-9_$]/.test(c);

  while (i < len) {
    const ch = source[i];
    const next = source[i + 1];

    // Line comment
    if (ch === '/' && next === '/') {
      let end = i + 2;
      while (end < len && source[end] !== '\n') end += 1;
      out += `<span class="t-comment">${escapeHtml(source.slice(i, end))}</span>`;
      i = end;
      continue;
    }

    // Block comment (nestable)
    if (ch === '/' && next === '*') {
      let end = i + 2;
      let depth = 1;
      while (end < len && depth > 0) {
        if (source[end] === '/' && source[end + 1] === '*') { depth += 1; end += 2; }
        else if (source[end] === '*' && source[end + 1] === '/') { depth -= 1; end += 2; }
        else end += 1;
      }
      out += `<span class="t-comment">${escapeHtml(source.slice(i, end))}</span>`;
      i = end;
      continue;
    }

    // Raw string
    if (ch === '#') {
      let hashes = 0;
      let probe = i;
      while (source[probe] === '#') { hashes += 1; probe += 1; }
      if (source[probe] === '"') {
        const closer = '"' + '#'.repeat(hashes);
        let end = probe + 1;
        while (end < len && !source.startsWith(closer, end)) {
          if (source[end] === '\\') end += 1;
          end += 1;
        }
        end = Math.min(end + closer.length, len);
        out += `<span class="t-string">${escapeHtml(source.slice(i, end))}</span>`;
        i = end;
        continue;
      }
      let end = i + 1;
      while (end < len && isIdentPart(source[end])) end += 1;
      if (end > i + 1) {
        out += `<span class="t-directive">${escapeHtml(source.slice(i, end))}</span>`;
        i = end;
        continue;
      }
      out += escapeHtml(ch);
      i += 1;
      continue;
    }

    // String literal
    if (ch === '"') {
      const multi = source.startsWith('"""', i);
      const quote = multi ? '"""' : '"';
      let end = i + quote.length;
      while (end < len) {
        if (source[end] === '\\') { end += 2; continue; }
        if (source.startsWith(quote, end)) { end += quote.length; break; }
        if (!multi && source[end] === '\n') break;
        end += 1;
      }
      out += `<span class="t-string">${escapeHtml(source.slice(i, end))}</span>`;
      i = end;
      continue;
    }

    // Attribute
    if (ch === '@') {
      let end = i + 1;
      while (end < len && isIdentPart(source[end])) end += 1;
      if (end > i + 1) {
        out += `<span class="t-attribute">${escapeHtml(source.slice(i, end))}</span>`;
        i = end;
        continue;
      }
    }

    // Number
    if (/[0-9]/.test(ch)) {
      let end = i;
      while (end < len && (/[0-9A-Fa-fxX_.eEpP]/.test(source[end]))) {
        if (source[end] === '.' && !/[0-9]/.test(source[end + 1] ?? '')) break;
        end += 1;
      }
      out += `<span class="t-number">${escapeHtml(source.slice(i, end))}</span>`;
      i = end;
      continue;
    }

    // Identifier / keyword / type
    if (isIdentStart(ch)) {
      let end = i;
      while (end < len && isIdentPart(source[end])) end += 1;
      const word = source.slice(i, end);
      let cls = 't-identifier';
      if (KEYWORDS.has(word)) cls = 't-keyword';
      else if (TYPES.has(word) || /^[A-Z]/.test(word)) cls = 't-type';
      else if (source[end] === '(') cls = 't-function';
      out += `<span class="${cls}">${escapeHtml(word)}</span>`;
      i = end;
      continue;
    }

    // Multi-char operator
    let op = null;
    for (const candidate of MULTI_OPS) {
      if (source.startsWith(candidate, i)) { op = candidate; break; }
    }
    if (op) {
      out += `<span class="t-operator">${escapeHtml(op)}</span>`;
      i += op.length;
      continue;
    }

    if ('+-*/%<>=!&|^~?'.includes(ch)) {
      out += `<span class="t-operator">${escapeHtml(ch)}</span>`;
      i += 1;
      continue;
    }

    out += escapeHtml(ch);
    i += 1;
  }

  return out;
}

// ── Rendering ──────────────────────────────────────────────────────────────

/** Format a byte count compactly. */
function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/** Render the file tree into the navigator. */
function renderTree(nodes, container, depth = 0) {
  container.innerHTML = '';

  for (const node of nodes) {
    if (node.type === 'directory') {
      const isOpen = state.openDirs.has(node.path);

      const row = document.createElement('button');
      row.className = 'tree-row';
      row.setAttribute('role', 'treeitem');
      row.setAttribute('aria-expanded', String(isOpen));
      row.style.paddingLeft = `${6 + depth * 12}px`;
      row.innerHTML = `
        <span class="tree-caret${isOpen ? ' is-open' : ''}" aria-hidden="true">▶</span>
        <span class="tree-label">${escapeHtml(node.name)}</span>`;

      const children = document.createElement('div');
      children.className = 'tree-children';
      children.hidden = !isOpen;

      row.addEventListener('click', () => {
        if (state.openDirs.has(node.path)) state.openDirs.delete(node.path);
        else state.openDirs.add(node.path);
        renderTree(nodes, container, depth);
      });

      container.appendChild(row);
      container.appendChild(children);
      if (isOpen) renderTree(node.children ?? [], children, depth + 1);
      continue;
    }

    const row = document.createElement('button');
    row.className = 'tree-row' + (node.path === state.activePath ? ' is-active' : '');
    row.setAttribute('role', 'treeitem');
    row.style.paddingLeft = `${6 + depth * 12}px`;
    row.innerHTML = `
      <span class="tree-caret" aria-hidden="true"></span>
      <span class="tree-label">${escapeHtml(node.name)}</span>
      <span class="tree-size">${node.size > 0 ? formatBytes(node.size) : ''}</span>`;
    row.addEventListener('click', () => openFile(node.path));
    container.appendChild(row);
  }
}

/** Render the package summary. */
function renderPackage(manifest) {
  const rows = [];

  if (manifest.name) rows.push(['name', manifest.name]);
  if (manifest.toolsVersion) rows.push(['tools', manifest.toolsVersion]);

  const platforms = Object.entries(manifest.platforms ?? {})
    .map(([k, v]) => `${k} ${v}`)
    .join(', ');
  if (platforms) rows.push(['platforms', platforms]);

  for (const product of manifest.products ?? []) {
    rows.push([product.kind, product.name]);
    if (product.bundleIdentifier) rows.push(['bundle', product.bundleIdentifier]);
    if (product.targets?.length) rows.push(['targets', product.targets.join(', ')]);
  }

  els.packageInfo.innerHTML = rows.map(([k, v]) =>
    `<div class="pkg-row"><span class="pkg-key">${escapeHtml(k)}</span><span class="pkg-val">${escapeHtml(String(v))}</span></div>`
  ).join('');

  for (const warn of manifest.warnings ?? []) {
    const div = document.createElement('div');
    div.className = 'pkg-warn';
    div.textContent = warn;
    els.packageInfo.appendChild(div);
  }

  if (manifest.ok && manifest.name) {
    els.manifestChip.hidden = false;
    els.manifestChip.textContent = `swift ${manifest.toolsVersion ?? ''}`.trim();
  }
}

/** Render the gutter line numbers to match the current line count. */
function renderGutter(lineCount) {
  els.gutter.textContent = Array.from({ length: lineCount }, (_, i) => i + 1).join('\n');
}

/** Repaint highlight layer, gutter and metadata from the current buffer. */
function repaint() {
  const text = els.editor.value;
  els.highlight.innerHTML = highlightSwift(text) + '\n';

  const lineCount = text.split('\n').length;
  renderGutter(lineCount);

  const bytes = new TextEncoder().encode(text).length;
  els.editorMeta.textContent = `${lineCount} lines · ${formatBytes(bytes)}`;

  const dirty = text !== state.savedContent;
  els.dirtyDot.hidden = !dirty;
  els.saveBtn.disabled = !dirty;
}

/** Report the caret position in the status bar. */
function updateCursor() {
  const upto = els.editor.value.slice(0, els.editor.selectionStart);
  const line = upto.split('\n').length;
  const column = upto.length - upto.lastIndexOf('\n');
  els.cursorPos.textContent = `Ln ${line}, Col ${column}`;
}

/** Render the diagnostics list honouring the active severity filter. */
function renderIssues() {
  const all = state.diagnostics;
  const shown = state.severityFilter === 'all'
    ? all
    : all.filter((d) => d.severity === state.severityFilter);

  els.issueCount.textContent = String(all.length);
  els.issues.innerHTML = '';

  // Group by file so a long list stays navigable.
  const byFile = new Map();
  for (const d of shown) {
    if (!byFile.has(d.file)) byFile.set(d.file, []);
    byFile.get(d.file).push(d);
  }

  if (shown.length === 0) {
    const div = document.createElement('div');
    div.className = 'issue-empty';
    div.textContent = all.length === 0
      ? 'No issues found in this package.'
      : `No ${state.severityFilter} issues. ${all.length} total.`;
    els.issues.appendChild(div);
    return;
  }

  for (const [file, items] of byFile) {
    for (const d of items) {
      const row = document.createElement('button');
      row.className = `issue-row sev-${d.severity}`;
      row.setAttribute('role', 'listitem');
      row.innerHTML = `
        <span class="issue-loc">${escapeHtml(file.split('/').pop())}:${d.line}</span>
        <span class="issue-msg">${escapeHtml(d.message)}</span>
        <span class="issue-rule">${escapeHtml(d.rule)}</span>`;
      row.addEventListener('click', async () => {
        if (state.activePath !== d.file) await openFile(d.file);
        gotoLine(d.line);
      });
      els.issues.appendChild(row);
    }
  }
}

/** Scroll the editor to a 1-based line and place the caret there. */
function gotoLine(line) {
  const lines = els.editor.value.split('\n');
  let offset = 0;
  for (let i = 0; i < Math.min(line - 1, lines.length); i += 1) {
    offset += lines[i].length + 1;
  }
  els.editor.focus();
  els.editor.setSelectionRange(offset, offset);

  // Approximate scroll: line height is 1.55 * 12.5px.
  const lineHeight = 12.5 * 1.55;
  els.editor.parentElement.scrollTop = Math.max(0, (line - 3) * lineHeight);
  updateCursor();
}

// ── Actions ────────────────────────────────────────────────────────────────

/** Load the file tree, manifest and diagnostics. */
async function refreshAll() {
  setStatus('Indexing…');
  try {
    const [tree, overview, diag] = await Promise.all([
      getJson('/api/tree'),
      getJson('/api/overview'),
      getJson('/api/diagnostics')
    ]);

    const name = overview.manifest?.name ?? tree.root.split(/[/\\]/).pop();
    els.workspaceName.textContent = name;
    document.title = `${name} — Xcode for Windows`;

    const files = (overview.perFile ?? []).length;
    els.fileCount.textContent = `${files} Swift`;

    renderTree(tree.tree, els.tree);
    renderPackage(overview.manifest);

    state.diagnostics = diag.diagnostics ?? [];
    renderIssues();

    const s = diag.summary ?? { errors: 0, warnings: 0, infos: 0 };
    els.issueSummary.textContent =
      `${s.errors} error${s.errors === 1 ? '' : 's'} · ${s.warnings} warning${s.warnings === 1 ? '' : 's'}`;

    setStatus(`Indexed ${files} Swift file${files === 1 ? '' : 's'}`);
  } catch (err) {
    setStatus(`Indexing failed: ${err.message}`);
  }
}

/** Open a file into the editor. */
async function openFile(path) {
  try {
    const file = await getJson(`/api/file?path=${encodeURIComponent(path)}`);
    state.activePath = path;
    state.activeContent = file.content;
    state.savedContent = file.content;

    els.editor.value = file.content;
    els.breadcrumb.textContent = path;
    els.emptyState.hidden = true;
    els.editor.disabled = false;

    repaint();
    updateCursor();
    await renderJumpbar(path);

    // Re-render the tree so the active row highlights.
    const tree = await getJson('/api/tree');
    renderTree(tree.tree, els.tree);

    // Reveal the file's own diagnostics.
    const scoped = state.diagnostics.filter((d) => d.file === path);
    setStatus(`${path} · ${scoped.length} issue${scoped.length === 1 ? '' : 's'}`);
  } catch (err) {
    setStatus(`Cannot open ${path}: ${err.message}`);
  }
}

/** Render the jump bar of top-level declarations for the open file. */
async function renderJumpbar(path) {
  try {
    const index = await getJson(`/api/symbols?path=${encodeURIComponent(path)}`);
    const top = (index.symbols ?? []).filter((s) =>
      ['struct', 'class', 'enum', 'actor', 'protocol', 'extension', 'func'].includes(s.kind)
    ).slice(0, 30);

    els.jumpbar.innerHTML = '';
    for (const sym of top) {
      const chip = document.createElement('button');
      chip.className = 'jump-chip';
      chip.textContent = sym.kind === 'func' ? `${sym.name}()` : sym.name;
      chip.title = `${sym.kind} ${sym.name} — line ${sym.line}`;
      chip.addEventListener('click', () => gotoLine(sym.line));
      els.jumpbar.appendChild(chip);
    }
  } catch {
    els.jumpbar.innerHTML = '';
  }
}

/** Save the current buffer. */
async function save() {
  if (!state.activePath) return;
  try {
    const content = els.editor.value;
    await getJson(`/api/file?path=${encodeURIComponent(state.activePath)}`, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ content })
    });
    state.savedContent = content;
    repaint();
    setStatus(`Saved ${state.activePath}`);
    await refreshAll();
  } catch (err) {
    setStatus(`Save failed: ${err.message}`);
  }
}

// ── Wiring ─────────────────────────────────────────────────────────────────

els.editor.addEventListener('input', repaint);
els.editor.addEventListener('keyup', updateCursor);
els.editor.addEventListener('click', updateCursor);
els.editor.addEventListener('scroll', () => {
  els.highlight.scrollTop = els.editor.scrollTop;
  els.highlight.scrollLeft = els.editor.scrollLeft;
});

// Tab inserts four spaces rather than moving focus.
els.editor.addEventListener('keydown', (event) => {
  if (event.key === 'Tab') {
    event.preventDefault();
    const start = els.editor.selectionStart;
    const end = els.editor.selectionEnd;
    els.editor.value =
      els.editor.value.slice(0, start) + '    ' + els.editor.value.slice(end);
    els.editor.selectionStart = els.editor.selectionEnd = start + 4;
    repaint();
    updateCursor();
    return;
  }

  // Ctrl/Cmd+S saves.
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
    event.preventDefault();
    save();
  }
});

els.editor.addEventListener('scroll', () => {
  els.gutter.scrollTop = els.editor.parentElement.scrollTop;
});

els.saveBtn.addEventListener('click', save);
els.reindexBtn.addEventListener('click', refreshAll);

for (const btn of document.querySelectorAll('.filter')) {
  btn.addEventListener('click', () => {
    for (const other of document.querySelectorAll('.filter')) other.classList.remove('is-on');
    btn.classList.add('is-on');
    state.severityFilter = btn.dataset.sev ?? 'all';
    renderIssues();
  });
}

// Warn before discarding unsaved work.
window.addEventListener('beforeunload', (event) => {
  if (els.editor.value !== state.savedContent) {
    event.preventDefault();
    event.returnValue = '';
  }
});

// ── Boot ───────────────────────────────────────────────────────────────────

els.editor.disabled = true;
repaint();
refreshAll();
