# Universal Code Quality Gate

Portable quality gate for AI coding agents, CI and editor workflows.

Use it as the last check before saying a task, review or PR is done.

Package name:

```text
universal-code-quality-gate
```

Repository:

```text
https://github.com/salexcarvalho/universal-code-quality-gate
```

## What it does

- runs lint, type, test and coverage checks when the project exposes them;
- audits security issues such as secrets, unsafe patterns and dependency risk;
- reports code smell and maintainability warnings;
- outputs `NOT CHECKED` instead of inventing results;
- treats security and broken quality checks as blocking.

Default coverage target: 80% unless the repository defines a stricter rule.

## Quick start

After publishing to npm:

```bash
npx universal-code-quality-gate --changed
npx universal-code-quality-gate --repo
```

Before publishing, run from GitHub:

```bash
npx github:salexcarvalho/universal-code-quality-gate --changed
npx git+https://github.com/salexcarvalho/universal-code-quality-gate.git --repo
```

Global install:

```bash
npm install -g universal-code-quality-gate
universal-code-quality-gate --repo
```

Local repository install:

```bash
npm install --save-dev universal-code-quality-gate
npx universal-code-quality-gate --changed
```

Direct script usage:

```bash
./scripts/code-quality-gate.sh --changed
./scripts/code-quality-gate.sh path/to/file.ext
./scripts/code-quality-gate.sh --repo
```

## Claude Code

Automatic install as skill + hook:

```bash
npx universal-code-quality-gate claude --global
# or
npx universal-code-quality-gate claude --local
```

If the package is not published yet:

```bash
npx github:salexcarvalho/universal-code-quality-gate claude --global
# or
npx git+https://github.com/salexcarvalho/universal-code-quality-gate.git claude --local
```

Useful flags:

```bash
npx universal-code-quality-gate claude --local --dry-run
npx universal-code-quality-gate claude --global --force
npx universal-code-quality-gate claude --local --no-hooks
```

The installer:

- copies the packaged skill into `~/.claude/skills` or `.claude/skills`;
- ensures the scripts stay executable;
- updates `settings.local.json` when present, otherwise `settings.json`;
- backs up the settings file before editing it.

## Codex and other agents

- For Codex, copy [AGENTS.md](AGENTS.md) into the target repository root.
- For Claude Code, use [SKILL.md](SKILL.md) or the automatic installer.
- For CI or editors, run the shell script or npm command directly.

## Security coverage

The gate is intentionally conservative. It tries to catch common, high-value issues early, including:

- leaked secrets and private keys;
- unsafe runtime patterns such as `eval` and risky HTML sinks;
- dependency audit findings when project tooling is available;
- Bandit, gosec, cargo-audit, composer audit, tfsec, checkov and Semgrep when installed.

If a tool is missing, the result is reported as `NOT CHECKED`.

## Blocking rules

The gate should block completion when it finds any of these:

- lint, type, build or test failures;
- coverage below the required threshold;
- leaked credentials or private keys;
- high-confidence security findings;
- unsafe destructive changes without safeguards;
- missing tests for critical new behavior.

Code smell and maintainability findings are warnings by default unless they introduce direct risk.

## Key files

- [scripts/code-quality-gate.sh](scripts/code-quality-gate.sh): portable core gate.
- [bin/code-quality-gate.js](bin/code-quality-gate.js): npm wrapper.
- [bin/install-claude-code.js](bin/install-claude-code.js): Claude Code installer.
- [SKILL.md](SKILL.md): Claude Code skill instructions.
- [AGENTS.md](AGENTS.md): repository instructions for Codex-style agents.

## Release checklist

- run `npm run pack:dry-run`;
- validate `--changed`, `--repo` and `claude --dry-run` flows;
- run the repository gate itself;
- publish with `npm publish --access public` when ready.

- Validate the script on Linux/macOS and Git Bash/WSL.
- Confirm the GitHub repository URL remains correct in the install examples.
- Confirm npm metadata in [package.json](package.json) stays aligned with the GitHub repository.
- Run `npm run pack:dry-run` before publishing.
- Publish with `npm publish --access public`.
- Keep private project names and internal paths out of the repository.
- Add stack-specific examples for at least JavaScript/TypeScript and Python.
- Keep the default behavior non-destructive.
- Ensure the workflow runs both changed-file and repository-level checks.
- Verify `SKILL.md`, `AGENTS.md`, and the script stay behaviorally aligned.
