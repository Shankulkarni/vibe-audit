# npm Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish vibeAudit to npm as `vibeaudit` with a plain-JS CLI (`npx vibeaudit install|update|status|uninstall`) that installs the plugin into Claude Code, Cursor, Gemini CLI, and Codex.

**Architecture:** Single `cli.js` at repo root (ESM, no build step). Detects installed AI tools via known config dirs, copies manifests + skills files into each tool's plugin directory, falls back to `npx skills add` if nothing is detected. Tracks installed tools in `~/.vibeaudit-config.json`. Pre-commit hook updated to keep `package.json` and all four plugin manifests in version sync.

**Tech Stack:** Node.js >=18 (ESM, top-level await, `fs.cpSync`, global `fetch`), `@clack/prompts` for interactive UI, npm for publish.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `.cursor-plugin/plugin.json` | Create | Cursor plugin manifest |
| `package.json` | Create | npm package declaration, bin entry, files allowlist |
| `.npmignore` | Create | Belt-and-suspenders exclusions on top of `files` allowlist |
| `cli.js` | Create | Single CLI entrypoint — all four commands |
| `.git/hooks/pre-commit` | Modify | Extend version bump to cover all four manifests + `package.json` |

---

## Task 1: Create the Cursor plugin manifest

**Files:**
- Create: `.cursor-plugin/plugin.json`

- [ ] **Step 1: Create `.cursor-plugin/plugin.json`**

Read `.codex-plugin/plugin.json` first to confirm the current version number, then create:

```json
{
  "name": "vibeaudit",
  "version": "0.1.13",
  "description": "Audits AI-generated (vibecoded) apps for security, quality, performance, and compliance gaps — before they reach production.",
  "author": {
    "name": "Shan Kulkarni",
    "url": "https://github.com/shankulkarni"
  },
  "homepage": "https://github.com/Shankulkarni/vibe-audit",
  "repository": "https://github.com/Shankulkarni/vibe-audit",
  "license": "MIT",
  "keywords": ["security", "audit", "vibecode", "ai-generated", "owasp", "cursor"],
  "skills": "./skills/"
}
```

> Match the version number to whatever `.codex-plugin/plugin.json` currently shows — they must be identical.

- [ ] **Step 2: Verify the file**

```bash
cat .cursor-plugin/plugin.json
```

Expected: valid JSON with the correct version number.

- [ ] **Step 3: Commit**

```bash
git add .cursor-plugin/plugin.json
git commit -m "feat: add Cursor plugin manifest"
```

---

## Task 2: Create `package.json`, `.npmignore`, install deps

**Files:**
- Create: `package.json`
- Create: `.npmignore`

- [ ] **Step 1: Create `package.json`**

Read `.claude-plugin/plugin.json` to confirm the current version, then create `package.json` at the repo root with that same version:

```json
{
  "name": "vibeaudit",
  "version": "0.1.14",
  "description": "Audits AI-generated (vibecoded) apps for security, quality, performance, and compliance gaps — before they reach production.",
  "type": "module",
  "bin": {
    "vibeaudit": "./cli.js"
  },
  "files": [
    "cli.js",
    "skills/",
    "agents/",
    "commands/",
    "scripts/",
    ".claude-plugin/",
    ".codex-plugin/",
    ".cursor-plugin/",
    "gemini-extension/",
    "AGENTS.md",
    "sources.json"
  ],
  "engines": {
    "node": ">=18"
  },
  "dependencies": {
    "@clack/prompts": "^0.7.0"
  },
  "keywords": [
    "security", "audit", "vibecode", "ai-generated", "owasp",
    "claude", "cursor", "gemini", "codex"
  ],
  "license": "MIT",
  "homepage": "https://github.com/Shankulkarni/vibe-audit",
  "repository": {
    "type": "git",
    "url": "https://github.com/Shankulkarni/vibe-audit"
  },
  "author": {
    "name": "Shan Kulkarni",
    "url": "https://github.com/shankulkarni"
  }
}
```

> Set the version to whatever `.claude-plugin/plugin.json` currently shows after Task 1's commit bump. They must match.

- [ ] **Step 2: Create `.npmignore`**

```
docs/
upstream/
.idea/
*.png
req.md
.claude/
.git/
memory/
```

- [ ] **Step 3: Install `@clack/prompts`**

```bash
bun add @clack/prompts
```

Expected: `bun.lockb` updated, `node_modules/@clack/prompts` present, `package.json` dependency version filled in with the resolved version.

- [ ] **Step 4: Verify package.json is valid**

```bash
node -e "import('./package.json', { assert: { type: 'json' } }).then(m => console.log('OK', m.default.version))"
```

Expected: `OK 0.1.X` (current version).

- [ ] **Step 5: Commit**

```bash
git add package.json .npmignore bun.lockb
git commit -m "feat: add package.json and npmignore for npm distribution"
```

---

## Task 3: Update pre-commit hook to sync all manifests

**Files:**
- Modify: `.git/hooks/pre-commit`

The existing hook only bumps `.claude-plugin/plugin.json`. It must also write the new version to `.codex-plugin/plugin.json`, `.cursor-plugin/plugin.json`, and `package.json`.

- [ ] **Step 1: Replace `.git/hooks/pre-commit`**

Overwrite the file with the following (keep the same shebang and logic, extend the file list):

```bash
#!/usr/bin/env bash
# pre-commit hook: auto-bump plugin patch version on every commit
# Keeps all four manifests and package.json in sync.

set -euo pipefail

PLUGIN_JSON=".claude-plugin/plugin.json"
[[ -f "$PLUGIN_JSON" ]] || exit 0

CURRENT=$(grep -o '"version":\s*"[^"]*"' "$PLUGIN_JSON" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')

if [[ -z "$CURRENT" ]]; then
  echo "[vibeAudit] Could not parse version from $PLUGIN_JSON — skipping bump."
  exit 0
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"

SED_INPLACE=("sed" "-i")
[[ "$(uname)" == "Darwin" ]] && SED_INPLACE=("sed" "-i" "")

bump_file() {
  local file="$1"
  [[ -f "$file" ]] || return
  "${SED_INPLACE[@]}" "s/\"version\": \"${CURRENT}\"/\"version\": \"${NEW_VERSION}\"/" "$file"
  git add "$file"
}

bump_file ".claude-plugin/plugin.json"
bump_file ".codex-plugin/plugin.json"
bump_file ".cursor-plugin/plugin.json"
bump_file "package.json"

echo "[vibeAudit] Version bumped: ${CURRENT} → ${NEW_VERSION}"
```

- [ ] **Step 2: Make the hook executable**

```bash
chmod +x .git/hooks/pre-commit
```

- [ ] **Step 3: Verify the hook fires correctly**

```bash
git commit --allow-empty -m "test: verify version sync hook"
```

Expected: output includes `[vibeAudit] Version bumped: X.Y.Z → X.Y.(Z+1)`. Check all four files updated to the same new version:

```bash
grep '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json .cursor-plugin/plugin.json package.json
```

Expected: all four show the same version string.

---

## Task 4: Create `cli.js` — core helpers and path resolution

**Files:**
- Create: `cli.js`

- [ ] **Step 1: Create `cli.js` with shebang, imports, tool definitions, and helpers**

```js
#!/usr/bin/env node
import { intro, outro, multiselect, spinner, note, cancel, isCancel } from '@clack/prompts'
import { existsSync, mkdirSync, cpSync, rmSync, writeFileSync, readFileSync } from 'fs'
import { join, dirname } from 'path'
import { homedir, platform } from 'os'
import { spawnSync } from 'child_process'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const CONFIG_PATH = join(homedir(), '.vibeaudit-config.json')

function appdata() {
  return process.env.APPDATA ?? join(homedir(), 'AppData', 'Roaming')
}

function baseDir(unix, win) {
  return platform() === 'win32' ? join(appdata(), win) : join(homedir(), unix)
}

const TOOLS = [
  {
    value: 'claude',
    label: 'Claude Code',
    detectDir: baseDir('.claude', 'Claude'),
    installDir: () => join(baseDir('.claude', 'Claude'), 'plugins', 'vibeaudit'),
    sources: ['.claude-plugin', 'skills', 'agents', 'commands'],
    manifestPath: (dest) => join(dest, '.claude-plugin', 'plugin.json'),
  },
  {
    value: 'cursor',
    label: 'Cursor',
    detectDir: baseDir('.cursor', 'Cursor'),
    installDir: () => join(baseDir('.cursor', 'Cursor'), 'plugins', 'vibeaudit'),
    sources: ['.cursor-plugin', 'skills'],
    manifestPath: (dest) => join(dest, '.cursor-plugin', 'plugin.json'),
  },
  {
    value: 'gemini',
    label: 'Gemini CLI',
    detectDir: baseDir('.gemini', 'gemini'),
    installDir: () => join(baseDir('.gemini', 'gemini'), 'extensions', 'vibeaudit'),
    sources: ['gemini-extension', 'skills'],
    manifestPath: (dest) => join(dest, 'gemini-extension', 'gemini-extension.json'),
  },
  {
    value: 'codex',
    label: 'Codex',
    detectDir: baseDir('.codex', 'Codex'),
    installDir: () => join(baseDir('.codex', 'Codex'), 'plugins', 'vibeaudit'),
    sources: ['.codex-plugin', 'skills'],
    manifestPath: (dest) => join(dest, '.codex-plugin', 'plugin.json'),
  },
]

function readConfig() {
  if (!existsSync(CONFIG_PATH)) return { tools: [] }
  return JSON.parse(readFileSync(CONFIG_PATH, 'utf8'))
}

function writeConfig(data) {
  writeFileSync(CONFIG_PATH, JSON.stringify(data, null, 2))
}

function localVersion() {
  const p = join(__dirname, '.claude-plugin', 'plugin.json')
  return JSON.parse(readFileSync(p, 'utf8')).version
}

function detectedTools() {
  return TOOLS.filter(t => existsSync(t.detectDir)).map(t => t.value)
}

function copyFiles(tool, dest) {
  mkdirSync(dest, { recursive: true })
  for (const src of tool.sources) {
    const srcPath = join(__dirname, src)
    if (existsSync(srcPath)) {
      cpSync(srcPath, join(dest, src), { recursive: true })
    }
  }
}

async function install() {
  intro('vibeAudit — install')

  const detected = detectedTools()
  const options = [
    ...TOOLS.map(t => ({
      value: t.value,
      label: t.label,
      hint: detected.includes(t.value) ? 'detected' : undefined,
    })),
    { value: 'skills-cli', label: 'All tools via skills CLI (fallback)' },
  ]

  const selected = await multiselect({
    message: 'Which AI tools would you like to install vibeAudit for?',
    options,
    initialValues: detected.length ? detected : ['skills-cli'],
  })

  if (isCancel(selected)) { cancel('Installation cancelled.'); process.exit(0) }

  if (selected.includes('skills-cli')) {
    const s = spinner()
    s.start('Running: npx skills add Shankulkarni/vibe-audit --all')
    const result = spawnSync('npx', ['skills', 'add', 'Shankulkarni/vibe-audit', '--all'], { stdio: 'inherit' })
    s.stop(result.status === 0 ? 'skills CLI done.' : 'skills CLI failed — try installing manually.')
    outro('Done.')
    return
  }

  const installed = []
  for (const value of selected) {
    const tool = TOOLS.find(t => t.value === value)
    if (!tool) continue
    const dest = tool.installDir()
    const s = spinner()
    s.start(`Installing for ${tool.label}`)
    copyFiles(tool, dest)
    s.stop(`Installed to ${dest}`)
    installed.push(value)
  }

  writeConfig({ tools: installed, installedAt: new Date().toISOString() })
  const labels = installed.map(v => TOOLS.find(t => t.value === v)?.label).join(', ')
  outro(`vibeAudit installed for: ${labels}`)
}

async function uninstall() {
  intro('vibeAudit — uninstall')
  const config = readConfig()

  if (!config.tools?.length) {
    note('No tools found in ~/.vibeaudit-config.json.\nNothing to uninstall.', 'Info')
    outro('Done.')
    return
  }

  const options = config.tools.map(v => {
    const tool = TOOLS.find(t => t.value === v)
    return { value: v, label: tool?.label ?? v }
  })

  const selected = await multiselect({
    message: 'Which tools would you like to remove vibeAudit from?',
    options,
    initialValues: config.tools,
  })

  if (isCancel(selected)) { cancel('Uninstall cancelled.'); process.exit(0) }

  for (const value of selected) {
    const tool = TOOLS.find(t => t.value === value)
    if (!tool) continue
    const dest = tool.installDir()
    if (existsSync(dest)) {
      rmSync(dest, { recursive: true, force: true })
      console.log(`  Removed: ${dest}`)
    }
  }

  const remaining = config.tools.filter(v => !selected.includes(v))
  if (remaining.length === 0) {
    rmSync(CONFIG_PATH, { force: true })
  } else {
    writeConfig({ ...config, tools: remaining })
  }

  outro('Uninstalled.')
}

async function update() {
  intro('vibeAudit — update')
  const s = spinner()
  s.start('Fetching latest version from npm...')
  const result = spawnSync('npm', ['install', '-g', 'vibeaudit@latest'], { stdio: 'inherit' })
  s.stop(result.status === 0 ? 'npm updated.' : 'npm install failed — check your npm access.')

  const config = readConfig()
  if (!config.tools?.length) {
    outro('No tools configured. Run `npx vibeaudit install` first.')
    return
  }

  note(`Re-installing for: ${config.tools.join(', ')}`, 'Syncing plugin files')
  for (const value of config.tools) {
    const tool = TOOLS.find(t => t.value === value)
    if (!tool) continue
    const dest = tool.installDir()
    const s2 = spinner()
    s2.start(`Updating ${tool.label}`)
    copyFiles(tool, dest)
    s2.stop(`Updated: ${dest}`)
  }

  outro('vibeAudit is up to date.')
}

async function status() {
  const version = localVersion()

  let latestVersion = null
  try {
    const res = await fetch('https://registry.npmjs.org/vibeaudit/latest', {
      signal: AbortSignal.timeout(3000),
    })
    if (res.ok) latestVersion = (await res.json()).version
  } catch {}

  console.log(`\nvibeAudit v${version}\n`)

  for (const tool of TOOLS) {
    const dest = tool.installDir()
    const manifest = tool.manifestPath(dest)
    if (existsSync(manifest)) {
      let installedVer = '?'
      try { installedVer = JSON.parse(readFileSync(manifest, 'utf8')).version } catch {}
      const outdated = latestVersion && installedVer !== latestVersion ? '  (update available)' : ''
      console.log(`  ${tool.label.padEnd(14)} ✓ installed   v${installedVer}${outdated}`)
    } else {
      console.log(`  ${tool.label.padEnd(14)} ✗ not found`)
    }
  }
  console.log()
}

const HELP = `
Usage: vibeaudit <command>

Commands:
  install    Install vibeAudit into your AI coding tools
  uninstall  Remove vibeAudit from your AI coding tools
  update     Update vibeAudit to the latest version
  status     Show installation status across tools
`

const cmd = process.argv[2]
switch (cmd) {
  case 'install':   await install(); break
  case 'uninstall': await uninstall(); break
  case 'update':    await update(); break
  case 'status':    await status(); break
  default:          console.log(HELP)
}
```

- [ ] **Step 2: Make `cli.js` executable**

```bash
chmod +x cli.js
```

- [ ] **Step 3: Verify help output**

```bash
node cli.js
```

Expected: prints the `Usage: vibeaudit <command>` block with all four commands listed.

- [ ] **Step 4: Verify status runs without crashing**

```bash
node cli.js status
```

Expected: a table showing all four tools. Most will show `✗ not found`. Claude Code should show `✓ installed` if `~/.claude/` exists. No uncaught errors.

- [ ] **Step 5: Commit**

```bash
git add cli.js
git commit -m "feat: add vibeaudit CLI with install/uninstall/update/status commands"
```

---

## Task 5: Smoke-test all four commands

No code changes in this task — purely verifying the CLI works end-to-end before publishing.

- [ ] **Step 1: Test `install` (dry run against Claude Code)**

```bash
node cli.js install
```

Walk through the interactive prompt. Select only **Claude Code**. Expected:
- Multi-select appears with Claude Code pre-ticked if `~/.claude/` exists
- After confirming, prints `Installed to ~/.claude/plugins/vibeaudit/`
- `~/.vibeaudit-config.json` is created

Verify the files were copied:

```bash
ls ~/.claude/plugins/vibeaudit/
```

Expected: `.claude-plugin/`, `skills/`, `agents/`, `commands/` directories present.

- [ ] **Step 2: Test `status` shows installed**

```bash
node cli.js status
```

Expected: Claude Code shows `✓ installed   vX.Y.Z`. Other tools show `✗ not found`.

- [ ] **Step 3: Test `uninstall`**

```bash
node cli.js uninstall
```

Select Claude Code. Expected: prints `Removed: ~/.claude/plugins/vibeaudit/`. Verify:

```bash
ls ~/.claude/plugins/vibeaudit/ 2>&1
```

Expected: `No such file or directory`.

- [ ] **Step 4: Verify `~/.vibeaudit-config.json` cleaned up**

```bash
cat ~/.vibeaudit-config.json 2>&1
```

Expected: `No such file or directory` (all tools uninstalled, config removed).

- [ ] **Step 5: Re-install for final state**

```bash
node cli.js install
```

Select Claude Code again to restore a working install for ongoing development.

---

## Task 6: Publish prep and README update

- [ ] **Step 1: Verify npm pack output (dry run)**

```bash
npm pack --dry-run
```

Expected output lists only files from the `files` allowlist. Confirm it includes `cli.js`, `skills/`, `agents/`, `commands/`, `.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/`, `gemini-extension/`, `AGENTS.md`, `sources.json`. Confirm it does NOT include `docs/`, `upstream/`, `.idea/`, `*.png`, `.claude/`.

- [ ] **Step 2: Verify the bin entry is executable after pack**

```bash
npm pack
tar -tzf vibeaudit-*.tgz | grep cli.js
```

Expected: `package/cli.js` appears in the tarball.

```bash
rm vibeaudit-*.tgz
```

- [ ] **Step 3: Add npm install badge and install instructions to README.md**

Open `README.md` and add the following section after the existing install/usage intro (find the right place — typically after the first badge row or before the first `##` section):

```markdown
## Install via npm

```bash
npx vibeaudit install
```

Or install globally:

```bash
npm install -g vibeaudit
vibeaudit install
```

**Commands**

| Command | What it does |
|---------|-------------|
| `npx vibeaudit install` | Detect and install into Claude Code, Cursor, Gemini CLI, Codex |
| `npx vibeaudit status` | Show which tools have vibeAudit installed and their version |
| `npx vibeaudit update` | Pull latest from npm and re-sync plugin files |
| `npx vibeaudit uninstall` | Remove vibeAudit from selected tools |
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add npm install instructions to README"
```

- [ ] **Step 5: Publish to npm**

Make sure you are logged in:

```bash
npm whoami
```

If not logged in: `npm login` first.

```bash
npm publish --access public
```

Expected: `+ vibeaudit@X.Y.Z` confirmation. Verify:

```bash
npm info vibeaudit version
```

Expected: prints the published version.

---

## Self-Review Checklist

- [x] **Cursor manifest** — Task 1 creates `.cursor-plugin/plugin.json`
- [x] **package.json + .npmignore** — Task 2
- [x] **Version sync** — Task 3 updates pre-commit hook to cover all four manifests + `package.json`
- [x] **CLI: install** — Task 4, including `skills add` fallback and `~/.vibeaudit-config.json` write
- [x] **CLI: uninstall** — Task 4, with full cleanup of config when all tools removed
- [x] **CLI: update** — Task 4, re-copies files for previously configured tools
- [x] **CLI: status** — Task 4, reads installed manifest versions, checks npm registry
- [x] **Windows paths** — `baseDir()` helper in Task 4 uses `process.env.APPDATA` on win32
- [x] **Cross-platform detection table** — all four tools covered in `TOOLS` array
- [x] **npm pack dry run** — Task 6 Step 1 verifies allowlist
- [x] **README** — Task 6 Step 3 adds install section
- [x] **Publish** — Task 6 Step 5
