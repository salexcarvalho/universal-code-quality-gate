#!/usr/bin/env node

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const packageName = 'universal-code-quality-gate';
const repoRoot = path.resolve(__dirname, '..');
const copyEntries = ['AGENTS.md', 'README.md', 'SKILL.md', 'bin', 'package.json', 'references', 'scripts'];
const hookMatcher = 'Write|Edit|MultiEdit|str_replace_based_edit_tool';

function usage() {
  console.log(`Usage:
  universal-code-quality-gate-claude [--global|--local] [--dry-run] [--force] [--no-hooks]
  universal-code-quality-gate-claude --settings-file path/to/settings.json [--dry-run] [--force] [--no-hooks]

Options:
  --global             Install into ~/.claude
  --local              Install into ./.claude (default)
  --settings-file      Override the Claude settings file to update
  --dry-run            Print planned actions without writing files
  --force              Replace an existing installed skill directory
  --no-hooks           Install the skill but do not modify Claude settings
  -h, --help           Show this message
`);
}

function shellEscape(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function parseArgs(argv) {
  const options = {
    scope: 'local',
    dryRun: false,
    force: false,
    hooks: true,
    settingsFile: null,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case '--global':
        options.scope = 'global';
        break;
      case '--local':
        options.scope = 'local';
        break;
      case '--dry-run':
        options.dryRun = true;
        break;
      case '--force':
        options.force = true;
        break;
      case '--no-hooks':
        options.hooks = false;
        break;
      case '--settings-file':
        index += 1;
        if (!argv[index]) {
          throw new Error('--settings-file requires a path');
        }
        options.settingsFile = path.resolve(argv[index]);
        break;
      case '-h':
      case '--help':
        options.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return options;
}

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

function resolveSettingsPath(claudeRoot, overridePath) {
  if (overridePath) {
    return overridePath;
  }

  const localSettingsPath = path.join(claudeRoot, 'settings.local.json');
  if (fs.existsSync(localSettingsPath)) {
    return localSettingsPath;
  }

  return path.join(claudeRoot, 'settings.json');
}

function readJsonFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return {};
  }

  const raw = fs.readFileSync(filePath, 'utf8').trim();
  if (!raw) {
    return {};
  }

  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new Error(`Could not parse JSON at ${filePath}: ${error.message}`);
  }
}

function ensureDirectory(dirPath, dryRun) {
  if (dryRun) {
    return;
  }
  fs.mkdirSync(dirPath, { recursive: true });
}

function removeDirectory(dirPath, dryRun) {
  if (dryRun || !fs.existsSync(dirPath)) {
    return;
  }
  fs.rmSync(dirPath, { recursive: true, force: true });
}

function copyEntry(sourcePath, targetPath, dryRun) {
  if (dryRun) {
    return;
  }

  const stat = fs.statSync(sourcePath);
  if (stat.isDirectory()) {
    fs.cpSync(sourcePath, targetPath, { recursive: true, force: true });
    return;
  }

  fs.copyFileSync(sourcePath, targetPath);
}

function setExecutable(filePath, dryRun) {
  if (dryRun || !fs.existsSync(filePath)) {
    return;
  }
  fs.chmodSync(filePath, 0o755);
}

function upsertPostToolUseHook(settings, command) {
  const nextSettings = settings && typeof settings === 'object' ? settings : {};
  const hooks = nextSettings.hooks && typeof nextSettings.hooks === 'object' ? nextSettings.hooks : {};
  const postToolUse = Array.isArray(hooks.PostToolUse) ? hooks.PostToolUse : [];

  let matcherEntry = postToolUse.find((entry) => entry && entry.matcher === hookMatcher && Array.isArray(entry.hooks));

  if (!matcherEntry) {
    matcherEntry = {
      matcher: hookMatcher,
      hooks: [],
    };
    postToolUse.push(matcherEntry);
  }

  const hasCommand = matcherEntry.hooks.some(
    (hook) => hook && hook.type === 'command' && hook.command === command,
  );

  if (!hasCommand) {
    matcherEntry.hooks.push({
      type: 'command',
      command,
    });
  }

  nextSettings.hooks = hooks;
  nextSettings.hooks.PostToolUse = postToolUse;
  return nextSettings;
}

function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(`universal-code-quality-gate-claude: ${error.message}`);
    usage();
    process.exit(1);
  }

  if (options.help) {
    usage();
    process.exit(0);
  }

  const claudeRoot = options.scope === 'global'
    ? path.join(os.homedir(), '.claude')
    : path.join(process.cwd(), '.claude');

  const skillDir = path.join(claudeRoot, 'skills', packageName);
  const settingsPath = resolveSettingsPath(claudeRoot, options.settingsFile);
  const scriptPath = path.join(skillDir, 'scripts', 'code-quality-gate.sh');
  const localScriptPath = `./.claude/skills/${packageName}/scripts/code-quality-gate.sh`;
  const hookScriptPath = options.scope === 'global' ? shellEscape(scriptPath) : localScriptPath;
  const hookCommand = `${hookScriptPath} --advisory`;

  if (fs.existsSync(skillDir) && !options.force) {
    console.error(`universal-code-quality-gate-claude: skill already exists at ${skillDir}`);
    console.error('Re-run with --force to replace it.');
    process.exit(1);
  }

  const actions = [];
  actions.push(`Install scope: ${options.scope}`);
  actions.push(`Claude root: ${claudeRoot}`);
  actions.push(`Skill target: ${skillDir}`);
  actions.push(`Settings target: ${settingsPath}`);

  if (fs.existsSync(skillDir)) {
    actions.push(`Remove existing skill directory: ${skillDir}`);
  }

  for (const entry of copyEntries) {
    actions.push(`Copy ${path.join(repoRoot, entry)} -> ${path.join(skillDir, entry)}`);
  }

  if (options.hooks) {
    actions.push(`Merge PostToolUse hook into ${settingsPath}`);
    actions.push(`Hook command: ${hookCommand}`);
  } else {
    actions.push('Skip Claude settings hook update (--no-hooks)');
  }

  if (options.dryRun) {
    console.log('Claude Code install plan');
    console.log('');
    for (const action of actions) {
      console.log(`- ${action}`);
    }
    process.exit(0);
  }

  ensureDirectory(path.join(claudeRoot, 'skills'), false);
  removeDirectory(skillDir, false);
  ensureDirectory(skillDir, false);

  for (const entry of copyEntries) {
    copyEntry(path.join(repoRoot, entry), path.join(skillDir, entry), false);
  }

  setExecutable(path.join(skillDir, 'scripts', 'code-quality-gate.sh'), false);
  setExecutable(path.join(skillDir, 'bin', 'code-quality-gate.js'), false);
  setExecutable(path.join(repoRoot, 'bin', 'install-claude-code.js'), false);

  if (options.hooks) {
    ensureDirectory(path.dirname(settingsPath), false);

    if (fs.existsSync(settingsPath)) {
      const backupPath = `${settingsPath}.bak-${timestamp()}`;
      fs.copyFileSync(settingsPath, backupPath);
      console.log(`Backed up existing Claude settings to ${backupPath}`);
    }

    const currentSettings = readJsonFile(settingsPath);
    const nextSettings = upsertPostToolUseHook(currentSettings, hookCommand);
    fs.writeFileSync(settingsPath, `${JSON.stringify(nextSettings, null, 2)}\n`, 'utf8');
  }

  console.log(`Installed ${packageName} into ${skillDir}`);
  if (options.hooks) {
    console.log(`Updated Claude settings at ${settingsPath}`);
  } else {
    console.log('Skipped Claude hook configuration');
  }
}

main();