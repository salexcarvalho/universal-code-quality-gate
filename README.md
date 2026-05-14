# Universal Code Quality Gate Skill

A portable, publish-ready code audit skill for AI coding agents, PR workflows, code editors, and CI pipelines.

It is designed to act as the last mandatory gate before a task, review, or pull request is declared done.
The goal is simple: do not ship code without checking correctness, maintainability, coverage, and security.

## Recommended public name

**Universal Code Quality Gate**

Package/skill name:

```text
universal-code-quality-gate
```

## What it checks

- Lint
- Type checks
- Build/test readiness
- Unit/integration test execution when discoverable
- Coverage target, defaulting to 80%
- Security review, leaked secrets, dependency risk, and high-confidence unsafe patterns
- Code smells and maintainability risks
- PR readiness summary

## Why this skill is useful

- It is editor-agnostic and does not assume a specific agent platform.
- It only runs tools that already exist in the target repository or environment.
- It can be used as a standalone script, a reusable skill, a repository policy, or a CI step.
- It reports `NOT CHECKED` instead of inventing results.
- It treats security findings as blocking, not advisory.

## Works with

- Codex: use `AGENTS.md` plus the script.
- Claude Code: use `SKILL.md` plus optional `PostToolUse` hook.
- Crowd-style agent workspaces: use `SKILL.md` or `AGENTS.md` as shared team instructions.
- VS Code, Cursor, Windsurf, Zed, JetBrains, terminal workflows: run the script manually or through tasks.
- GitHub Actions: use the included workflow example.

## Install

### Option 0: run with NPX

After publishing to npm:

```bash
npx universal-code-quality-gate --changed
npx universal-code-quality-gate --repo
```

Before publishing to npm, you can still run it directly from the Git repository:

```bash
npx github:<owner>/<repo> --changed
npx github:<owner>/<repo> --repo
```

Or with a Git URL:

```bash
npx git+https://github.com/<owner>/<repo>.git --changed
```

This works because the repository exposes an npm `bin` entry through [package.json](package.json), pointing to [scripts/code-quality-gate.sh](scripts/code-quality-gate.sh).

The npm command is exposed through a Node wrapper in [bin/code-quality-gate.js](bin/code-quality-gate.js), which delegates to the shell gate script.

### Option 0A: install globally

If you want the command available everywhere on the machine:

```bash
npm install -g universal-code-quality-gate
universal-code-quality-gate --repo
```

You can also install globally from Git:

```bash
npm install -g git+https://github.com/<owner>/<repo>.git
universal-code-quality-gate --changed
```

### Option 0B: install per agent or per repository

If you want behavior similar to agent skill directories, keep the package local to one agent or one repository.

Examples:

Per repository:

```bash
npm install --save-dev universal-code-quality-gate
npx universal-code-quality-gate --changed
```

Per agent skill folder:

```text
<agent-skill-dir>/universal-code-quality-gate/
  SKILL.md
  AGENTS.md
  bin/
    code-quality-gate.js
  scripts/
    code-quality-gate.sh
  package.json
```

This mode is useful when one agent should always carry the skill, but you do not want a machine-wide install.

### Option 0C: install globally for one agent family

If you want the skill available to one agent globally, keep a dedicated copy in that agent's skill directory.

Examples:

Claude Code global skill:

```bash
mkdir -p ~/.claude/skills
git clone <repo-url> ~/.claude/skills/universal-code-quality-gate
chmod +x ~/.claude/skills/universal-code-quality-gate/scripts/code-quality-gate.sh
```

Claude Code project-local skill:

```bash
mkdir -p .claude/skills
git clone <repo-url> .claude/skills/universal-code-quality-gate
chmod +x .claude/skills/universal-code-quality-gate/scripts/code-quality-gate.sh
```

Codex or repository-scoped usage:

```bash
npm install --save-dev universal-code-quality-gate
cp AGENTS.md ./AGENTS.md
npx universal-code-quality-gate --changed
```

Shared internal agent folder:

```bash
git clone <repo-url> ~/agent-skills/universal-code-quality-gate
npm install -g ~/agent-skills/universal-code-quality-gate
universal-code-quality-gate --repo
```

### Option 1: install as a Git submodule

```bash
git submodule add <repo-url> tools/universal-code-quality-gate
chmod +x tools/universal-code-quality-gate/scripts/code-quality-gate.sh
```

Recommended when you want to keep the skill versioned and updatable from the source repository.

### Option 2: install with git subtree

```bash
git subtree add --prefix tools/universal-code-quality-gate <repo-url> main --squash
chmod +x tools/universal-code-quality-gate/scripts/code-quality-gate.sh
```

Recommended when you want a vendorized copy without submodule management.

### Option 3: copy into the target repository

Copy the folder into your repository:

```bash
cp -R universal-code-quality-gate-skill ./quality-gate
chmod +x ./quality-gate/scripts/code-quality-gate.sh
```

Or place the script at repository root:

```bash
mkdir -p scripts
cp universal-code-quality-gate-skill/scripts/code-quality-gate.sh scripts/
chmod +x scripts/code-quality-gate.sh
```

If you publish this repository, replace `<repo-url>` with the final public Git URL.
If you publish it to npm, the package name is already configured as `universal-code-quality-gate` in [package.json](package.json).

## Usage

Using NPX:

```bash
npx universal-code-quality-gate --changed
npx universal-code-quality-gate src/example.ts
npx universal-code-quality-gate --repo
```

Using a global install:

```bash
universal-code-quality-gate --changed
universal-code-quality-gate --repo
```

Using package scripts after local install:

```bash
npm run gate:changed
npm run gate:repo
```

Changed files:

```bash
./scripts/code-quality-gate.sh --changed
```

Single file:

```bash
./scripts/code-quality-gate.sh src/example.ts
```

Repository-level:

```bash
./scripts/code-quality-gate.sh --repo
```

Advisory mode, never exits with blocking status:

```bash
./scripts/code-quality-gate.sh --changed --advisory
```

## Security coverage

The gate is intended to catch security problems early, without pretending to be a full penetration test.

Current security coverage includes:

- leaked secrets and private keys;
- dangerous runtime APIs such as `eval`, HTML injection sinks, and similar unsafe primitives;
- Python static checks through `bandit` when available;
- Python dependency checks through `pip-audit` or `safety` when available;
- JavaScript and TypeScript dependency audits through the package manager when available;
- Go security checks through `gosec` when available;
- Rust dependency audits through `cargo-audit` when available;
- PHP dependency audits through `composer audit` when available;
- Terraform and IaC security checks through `tfsec` or `checkov` when available;
- Semgrep-based repository SAST when available.

If a security command is not available, the gate reports it as `NOT CHECKED`.

## Recommended repository layout

For reusable installation, keep one of these layouts:

```text
tools/
  universal-code-quality-gate/
    SKILL.md
    AGENTS.md
    scripts/
      code-quality-gate.sh
```

Or copy only the executable into the target repository root:

```text
scripts/
  code-quality-gate.sh
```

## Codex usage

Copy `AGENTS.md` to your repository root. The file tells the agent how to run and report the quality gate before completing work.

If you want Codex to use the npm package directly inside the repository:

```bash
npm install --save-dev universal-code-quality-gate
npx universal-code-quality-gate --changed
```

## Claude Code usage

Copy `SKILL.md` and `scripts/` as a skill folder. To run after file edits, register the script as a `PostToolUse` hook.

Recommended layouts:

Global:

```text
~/.claude/skills/universal-code-quality-gate/
```

Project-local:

```text
.claude/skills/universal-code-quality-gate/
```

Example hook fragment:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "./scripts/code-quality-gate.sh"
          }
        ]
      }
    ]
  }
}
```

## What makes a review blocking

The gate should stop completion when any of the following is found:

- lint, type, build, or test failures;
- measured coverage below the required threshold;
- leaked secrets or private keys;
- high-confidence security findings;
- destructive or unsafe code changes without safeguards;
- missing tests for critical new logic.

Warnings such as code smell, maintainability concerns, or partially unavailable tooling should still be reported, but are not blocking by default unless they create direct risk.

## Public release checklist

- Validate the script on Linux/macOS and Git Bash/WSL.
- Confirm the repository has a public Git URL and update install examples.
- Add npm metadata such as repository, homepage, and bugs URL before publish.
- Run `npm run pack:dry-run` before publishing.
- Publish with `npm publish --access public`.
- Keep private project names and internal paths out of the repository.
- Add stack-specific examples for at least JavaScript/TypeScript and Python.
- Keep the default behavior non-destructive.
- Ensure the workflow runs both changed-file and repository-level checks.
- Verify `SKILL.md`, `AGENTS.md`, and the script stay behaviorally aligned.
# universal-code-quality-gate
