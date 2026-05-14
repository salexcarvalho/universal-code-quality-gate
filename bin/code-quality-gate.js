#!/usr/bin/env node

const { spawnSync } = require('node:child_process');
const { existsSync } = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..');
const scriptPath = path.join(repoRoot, 'scripts', 'code-quality-gate.sh');

if (!existsSync(scriptPath)) {
  console.error(`code-quality-gate: script not found at ${scriptPath}`);
  process.exit(1);
}

const shell = process.platform === 'win32' ? 'bash' : 'bash';
const result = spawnSync(shell, [scriptPath, ...process.argv.slice(2)], {
  cwd: process.cwd(),
  stdio: 'inherit',
  env: process.env,
});

if (result.error) {
  if (process.platform === 'win32') {
    console.error('code-quality-gate: bash is required on Windows. Use WSL or Git Bash.');
  } else {
    console.error(`code-quality-gate: failed to execute ${scriptPath}`);
  }
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 1);