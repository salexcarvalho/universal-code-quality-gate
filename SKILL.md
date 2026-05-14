---
name: universal-code-quality-gate
description: >
  Universal final code audit skill for AI coding agents, PR reviews, and editor workflows.
  Use this skill after creating or changing code, before closing a task, before finalizing a pull request,
  or when asked to check lint, tests, coverage, security, dependency risk, code smells, maintainability, or PR readiness.
  It is intentionally editor-agnostic and can be used with Codex, Claude Code, Crowd-style agent workspaces,
  GitHub Actions, local terminals, and code editors that can run shell commands.
---

# Universal Code Quality Gate

## Purpose

Act as the final engineering quality gate after code has been generated, edited, reviewed, or prepared for a pull request.

This skill verifies that the change is safe, maintainable, testable, and ready to be shared with a team or merged.
It is language-aware but tool-agnostic: it only runs tools that already exist in the repository or environment.
It must treat security as a first-class gate, not as an optional afterthought.

## Compatibility model

This skill is designed to work in four modes:

1. **Agent Skill mode**: use this `SKILL.md` plus `scripts/code-quality-gate.sh` as a packaged skill.
2. **Codex / repository instruction mode**: copy the included `AGENTS.md` into the target repository.
3. **Claude Code hook mode**: register `scripts/code-quality-gate.sh` as a `PostToolUse` hook for write/edit tools.
4. **Editor / CI mode**: run the script manually, from task runners, or from GitHub Actions.

For public distribution, prefer packaging the repository so it can be installed with Git submodule or Git subtree.

Do not assume a specific editor, model, framework, package manager, operating system, or language.

## Non-negotiable rules

- Do not invent lint, test, coverage, security, or build results.
- Do not claim a check passed unless the relevant command actually ran and exited successfully.
- Do not install dependencies automatically unless the user explicitly asks.
- Prefer project-local tools over global tools.
- Prefer repository scripts and package-manager commands over hardcoded commands when they exist.
- If a required tool is missing, report it as **not checked**, not as passed.
- If the repository has a documented quality command, use it first.
- If the user changed only one file, scope checks to that file when possible, then run affected tests when discoverable.
- If multiple files changed, run repository-level checks when available.
- Security findings, dependency vulnerabilities, unsafe sinks, and leaked secrets are blocking.
- Lint/type/build/test failures are blocking unless the user explicitly requested advisory-only output.
- Code smell findings are advisory by default, but must be reported.
- Coverage target defaults to **80%** unless the repository defines a stricter threshold.

## When to run

Run this skill when any of these conditions apply:

- After generating code.
- After editing code.
- Before saying a feature, bugfix, refactor, migration, or test task is complete.
- Before finalizing a pull request review.
- After resolving review comments.
- Before merging or closing a PR.
- When the user asks for lint, tests, coverage, quality, code smell, security, maintainability, or readiness checks.

## Required workflow

### 1. Discover repository context

Collect only what is needed:

```bash
pwd
git rev-parse --show-toplevel 2>/dev/null || true
git status --short 2>/dev/null || true
find . -maxdepth 3 \
  -not -path '*/.git/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/vendor/*' \
  -not -path '*/dist/*' \
  -not -path '*/build/*' \
  -not -path '*/coverage/*' \
  -not -path '*/.venv/*' \
  -not -path '*/venv/*' \
  -not -path '*/__pycache__/*' \
  | sort | head -300
```

Detect manifests and quality tooling:

```bash
ls -1 \
  package.json pnpm-lock.yaml yarn.lock package-lock.json \
  pyproject.toml requirements.txt setup.cfg tox.ini noxfile.py \
  composer.json phpunit.xml phpstan.neon pint.json \
  go.mod Cargo.toml pom.xml build.gradle gradlew settings.gradle \
  *.sln *.csproj pubspec.yaml Package.swift \
  Makefile justfile Taskfile.yml .pre-commit-config.yaml \
  docker-compose.yml compose.yaml Dockerfile \
  2>/dev/null || true
```

### 2. Detect changed files

Prefer the current working tree. If the agent knows the modified files, use those. Otherwise:

```bash
git diff --name-only --diff-filter=ACMRTUXB HEAD 2>/dev/null || true
git diff --cached --name-only --diff-filter=ACMRTUXB 2>/dev/null || true
```

Ignore generated/vendor/build artifacts.

### 3. Run the portable quality gate

Use the included script whenever possible:

```bash
./scripts/code-quality-gate.sh --changed
```

For a specific file:

```bash
./scripts/code-quality-gate.sh path/to/file.ext
```

For CI or repository-wide checks:

```bash
./scripts/code-quality-gate.sh --repo
```

If the skill is installed as a vendored Git dependency, run the script from its installed location, for example:

```bash
./tools/universal-code-quality-gate/scripts/code-quality-gate.sh --changed
```

### 4. Language/tool matrix

Use the tools available in the repository. Do not install missing tools automatically.

| Ecosystem | Preferred checks |
|---|---|
| JavaScript / TypeScript | package scripts, ESLint, TypeScript, Jest, Vitest, Playwright, Prettier, package-manager audit |
| Python | Ruff, Flake8, MyPy, Pyright, Radon, Bandit, pip-audit or safety, Pytest, Coverage |
| PHP | PHP lint, Pint, PHPCS, PHPStan, Psalm, PHPUnit, Pest, composer audit |
| Go | gofmt, go vet, golangci-lint, gosec, go test, coverage |
| Java | Maven/Gradle test, Checkstyle, PMD, SpotBugs, dependency/security plugins when present |
| Kotlin | Gradle test/check, ktlint, detekt, dependency/security plugins when present |
| C# / .NET | dotnet format, dotnet build, dotnet test, security analyzers when present |
| Rust | cargo fmt, clippy, cargo test, cargo-audit |
| Ruby | RuboCop, RSpec, Minitest, brakeman, bundle-audit |
| Swift | swiftformat, swiftlint, swift test |
| Dart / Flutter | dart format/analyze/test, flutter test --coverage |
| C / C++ | clang-format, clang-tidy, cppcheck, CMake/CTest |
| Shell | shellcheck, shfmt |
| SQL | sqlfluff |
| Terraform / IaC | terraform fmt/validate, tflint, tfsec, checkov |
| Docker | hadolint, trivy when available |
| YAML / JSON / TOML / Markdown | parser validation, prettier, yamllint, markdownlint, taplo |

### 5. Manual code smell review

If automated tools are unavailable or incomplete, review the changed code manually for:

- oversized functions/classes/modules;
- duplicated logic;
- excessive nesting;
- weak names;
- hidden side effects;
- missing error handling;
- missing tests for new behavior;
- unsafe input handling;
- hardcoded credentials;
- dead code;
- debug statements;
- unresolved technical-debt markers that should not ship;
- unnecessary coupling;
- missing observability for critical paths.

### 5A. Manual security review

When automated security tooling is missing or incomplete, inspect the changed code manually for:

- command injection;
- SQL injection;
- path traversal;
- XSS and unsafe HTML rendering;
- SSRF-capable URL fetching without validation;
- insecure deserialization;
- unsafe shell execution;
- missing auth or authorization checks;
- secret material committed in source;
- insecure temporary-file or filesystem handling;
- unsafe dependency or supply-chain changes.

### 6. Coverage rule

Default threshold: **80% line coverage**.

If the repository already defines stricter coverage rules, follow the repository rule.
If coverage cannot be measured, clearly report why:

- coverage tool missing;
- no matching tests found;
- test command failed before coverage generation;
- repository has no test framework configured;
- project type does not have a reliable coverage command.

Never mark coverage as passed when it was not measured.

### 7. Blocking criteria

Block completion when any of these are found:

- syntax errors;
- build failure;
- typecheck failure;
- lint errors;
- failing tests;
- coverage below required threshold;
- secret/key/token committed in code;
- high-confidence security vulnerability;
- high-confidence dependency vulnerability in production-relevant scope;
- destructive migration or unsafe data operation without safeguards;
- missing test for new critical business logic.

### 8. Expected final response

Return a concise report:

```text
Code Quality Gate Report

Scope:
- Files checked: ...
- Stack detected: ...
- Mode: file / changed-files / repository / PR

Results:
- Lint: PASS / FAIL / NOT CHECKED
- Types: PASS / FAIL / NOT CHECKED
- Tests: PASS / FAIL / NOT CHECKED
- Coverage: PASS / FAIL / NOT MEASURED
- Security: PASS / FAIL
- Code smell: PASS / WARNINGS

Blocking issues:
1. ...

Warnings:
1. ...

Recommended next actions:
1. ...

Decision:
- READY TO MERGE / NOT READY / READY WITH WARNINGS
```

If commands were run, include the exact commands. If commands were not run, say why.

## Publication guidance

To make this skill installable via Git and reusable across repositories:

1. publish the repository at a stable Git URL;
2. keep `SKILL.md`, `AGENTS.md`, and `scripts/code-quality-gate.sh` at stable paths;
3. document both submodule and subtree installation flows;
4. avoid repository-internal absolute paths or local assumptions in examples;
5. keep the script executable and non-destructive by default.

## Claude Code hook usage

Register the script as a `PostToolUse` hook for write/edit tools.

Example `settings.json` fragment:

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

The script can read Claude Code hook JSON from stdin and will try to extract the edited file path automatically.

## Codex usage

For Codex, place the included `AGENTS.md` at the repository root. It instructs the agent to run the quality gate before completing coding tasks or PR work.

## Public sharing checklist

Before publishing this skill publicly:

- Keep all instructions in English.
- Keep the skill name stable and lowercase.
- Include a `README.md` with install examples.
- Include the executable script under `scripts/`.
- Include the tooling matrix under `references/`.
- Add a license file before public release.
- Do not include private project paths, domains, tokens, company names, or internal repository names.
