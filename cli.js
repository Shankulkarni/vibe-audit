#!/usr/bin/env node
import { intro, outro, multiselect, spinner, note, cancel, isCancel } from '@clack/prompts'
import { existsSync, mkdirSync, cpSync, rmSync, writeFileSync, readFileSync, readdirSync } from 'fs'
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
    commandsDest: () => join(baseDir('.claude', 'Claude'), 'commands'),
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
    // gemini-extension/ contains symlinks that npm doesn't follow — resolve them at install time
    resolveIntoExtension: ['AGENTS.md', 'skills'],
  },
  {
    value: 'codex',
    label: 'Codex',
    detectDir: baseDir('.codex', 'Codex'),
    installDir: () => join(baseDir('.codex', 'Codex'), 'plugins', 'vibeaudit'),
    sources: ['.codex-plugin', 'skills', 'AGENTS.md'],
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
  // For tools whose extension dirs use symlinks (not followed by npm), copy real files in
  if (tool.resolveIntoExtension) {
    const extDir = join(dest, 'gemini-extension')
    mkdirSync(extDir, { recursive: true })
    for (const name of tool.resolveIntoExtension) {
      const src = join(__dirname, name)
      if (existsSync(src)) {
        cpSync(src, join(extDir, name), { recursive: true })
      }
    }
  }
  if (tool.commandsDest) {
    const cmdSrc = join(__dirname, 'commands')
    const cmdDest = tool.commandsDest()
    if (existsSync(cmdSrc)) {
      mkdirSync(cmdDest, { recursive: true })
      for (const f of readdirSync(cmdSrc)) {
        cpSync(join(cmdSrc, f), join(cmdDest, f), { recursive: true })
      }
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
    writeConfig({ tools: ['skills-cli'], installedAt: new Date().toISOString() })
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
    if (tool.commandsDest && existsSync(dest)) {
      const pluginCmdDir = join(dest, 'commands')
      if (existsSync(pluginCmdDir)) {
        const cmdDest = tool.commandsDest()
        for (const f of readdirSync(pluginCmdDir)) {
          const fDest = join(cmdDest, f)
          if (existsSync(fDest)) rmSync(fDest, { recursive: true, force: true })
        }
      }
    }
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
  note('Running: npm install -g vibeaudit@latest', 'Updating')
  const result = spawnSync('npm', ['install', '-g', 'vibeaudit@latest'], { stdio: 'inherit' })
  if (result.status == null || result.status !== 0) {
    cancel('npm install failed — check your npm access.')
    process.exit(1)
  }

  const config = readConfig()
  if (!config.tools?.length) {
    outro('No tools configured. Run `npx vibeaudit install` first.')
    return
  }

  const syncableTools = config.tools.filter(v => v !== 'skills-cli')
  if (syncableTools.length === 0) {
    note('Installed via skills CLI — re-run `npx skills add Shankulkarni/vibe-audit --all` to update plugin files.', 'Note')
    outro('vibeAudit npm package updated.')
    return
  }
  note(`Re-installing for: ${syncableTools.join(', ')}`, 'Syncing plugin files')
  for (const value of syncableTools) {
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
try {
  switch (cmd) {
    case 'install':   await install(); break
    case 'uninstall': await uninstall(); break
    case 'update':    await update(); break
    case 'status':    await status(); break
    default:          console.log(HELP)
  }
} catch (err) {
  cancel(`Error: ${err.message}`)
  process.exit(1)
}
