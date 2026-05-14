# Agent Instructions: Universal Code Quality Gate

Before finishing any coding task, PR review, refactor, migration, bugfix, test update, or generated code response, run the project quality gate when possible.

## Required behavior

- Do not invent lint, test, build, coverage, or security results.
- Prefer project-local tools over global tools.
- Do not install dependencies unless the user explicitly asks.
- Run only commands that are available in the repository or environment.
- If a check cannot run, report it as `NOT CHECKED` and explain why.
- Treat lint errors, type errors, build failures, failing tests, leaked secrets, and high-confidence security issues as blocking.
- Treat code smells as warnings unless they create correctness, security, or maintainability risk.
- Default coverage target is 80%, unless the project defines a stricter threshold.

## Main command

Use this command for changed files:

```bash
./scripts/code-quality-gate.sh --changed
```

Use this command for a specific file:

```bash
./scripts/code-quality-gate.sh path/to/file.ext
```

Use this command for repository-level checks:

```bash
./scripts/code-quality-gate.sh --repo
```

## Final response format

```text
Code Quality Gate Report

Scope:
- Files checked: ...
- Stack detected: ...
- Mode: file / changed-files / repository / PR

Commands run:
- ...

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
