#!/usr/bin/env node

const { spawnSync } = require('node:child_process');
const { existsSync } = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..');
const scriptPath = path.join(repoRoot, 'scripts', 'code-quality-gate.sh');
const claudeInstallerPath = path.join(repoRoot, 'bin', 'install-claude-code.js');

function runNodeScript(targetPath, args) {
  const result = spawnSync(process.execPath, [targetPath, ...args], {
    cwd: process.cwd(),
    stdio: 'inherit',
    env: process.env,
  });

  if (result.error) {
    console.error(`code-quality-gate: failed to execute ${targetPath}`);
    console.error(result.error.message);
    process.exit(1);
  }

  process.exit(result.status ?? 1);
}

function runShellScript(targetPath, args) {
  const shell = process.platform === 'win32' ? 'bash' : 'bash';
  const result = spawnSync(shell, [targetPath, ...args], {
    cwd: process.cwd(),
    stdio: 'inherit',
    env: process.env,
  });

  if (result.error) {
    if (process.platform === 'win32') {
      console.error('code-quality-gate: bash is required on Windows. Use WSL or Git Bash.');
    } else {
      console.error(`code-quality-gate: failed to execute ${targetPath}`);
    }
    console.error(result.error.message);
    process.exit(1);
  }

  process.exit(result.status ?? 1);
}

const args = process.argv.slice(2);
const subcommand = args[0];

if (subcommand === 'claude' || subcommand === 'install-claude' || subcommand === 'claude-install') {
  if (!existsSync(claudeInstallerPath)) {
    console.error(`code-quality-gate: Claude installer not found at ${claudeInstallerPath}`);
    process.exit(1);
  }

  const installerArgs = args.slice(1).map((arg) => (arg === 'help' ? '--help' : arg));
  runNodeScript(claudeInstallerPath, installerArgs);
}

if (!existsSync(scriptPath)) {
  console.error(`code-quality-gate: script not found at ${scriptPath}`);
  process.exit(1);
}

runShellScript(scriptPath, args);