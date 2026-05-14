#!/usr/bin/env bash
# Universal Code Quality Gate
# Portable final audit for AI-generated code, PR reviews, and editor workflows.
# It runs only tools already available in the repository/environment.

set -uo pipefail

MODE="files"
ADVISORY=0
FILES=()
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
COMMANDS_RUN=()
PASS=()
WARN=()
FAIL=()
NOT_CHECKED=()
STACK=()
REPO_SECURITY_DONE=0

usage() {
  cat <<'USAGE'
Usage:
  code-quality-gate.sh --changed [--advisory]
  code-quality-gate.sh --repo [--advisory]
  code-quality-gate.sh path/to/file [path/to/other-file] [--advisory]

Modes:
  --changed   Check changed files detected from git.
  --repo      Run repository-level checks when available.
  --advisory  Report blocking issues but exit 0.
USAGE
}

log_cmd() { COMMANDS_RUN+=("$*"); }
run_capture() {
  log_cmd "$*"
  "$@" 2>&1
}
add_pass() { PASS+=("$1"); }
add_warn() { WARN+=("$1"); }
add_fail() { FAIL+=("$1"); }
add_na() { NOT_CHECKED+=("$1"); }
has() { command -v "$1" >/dev/null 2>&1; }

run_capture_in_root() {
  log_cmd "(cd $ROOT && $*)"
  (
    cd "$ROOT" && "$@"
  ) 2>&1
}

find_bin() {
  local name="$1"
  local dir="$ROOT"
  if [[ -n "${2:-}" && -e "${2:-}" ]]; then
    dir="$(cd "$(dirname "$2")" 2>/dev/null && pwd || echo "$ROOT")"
  fi
  while [[ "$dir" != "/" ]]; do
    if [[ -x "$dir/node_modules/.bin/$name" ]]; then echo "$dir/node_modules/.bin/$name"; return 0; fi
    dir="$(dirname "$dir")"
  done
  if [[ -x "$ROOT/node_modules/.bin/$name" ]]; then echo "$ROOT/node_modules/.bin/$name"; return 0; fi
  command -v "$name" 2>/dev/null || true
}

find_python() {
  for c in "$ROOT/.venv/bin/python3" "$ROOT/venv/bin/python3" "$ROOT/.python/bin/python3" "$(command -v python3 2>/dev/null || true)"; do
    [[ -n "$c" && -x "$c" ]] && { echo "$c"; return 0; }
  done
  echo "python3"
}

py_has() { local py="$1" mod="$2"; "$py" -m "$mod" --version >/dev/null 2>&1 || "$py" -m "$mod" -h >/dev/null 2>&1; }

json_hook_file_from_stdin() {
  if [ -t 0 ]; then return 1; fi
  local input
  input="$(cat 2>/dev/null || true)"
  [[ -z "$input" ]] && return 1
  python3 - <<PY 2>/dev/null || true
import json
raw = '''$input'''
try:
    data = json.loads(raw)
except Exception:
    raise SystemExit(0)
tool = data.get('tool_name') or data.get('tool') or ''
if tool and tool not in {'Write','Edit','MultiEdit','str_replace_based_edit_tool'}:
    raise SystemExit(0)
tool_input = data.get('tool_input') or {}
path = tool_input.get('path') or tool_input.get('file_path') or tool_input.get('file') or ''
if path:
    print(path)
PY
}

is_ignored_file() {
  local f="$1"
  [[ "$f" =~ (^|/)(node_modules|vendor|dist|build|coverage|target|.git|.venv|venv|__pycache__)/ ]] && return 0
  [[ "$f" =~ \.(min\.js|map|lock|png|jpg|jpeg|gif|webp|svg|ico|pdf|zip|gz|tar|7z|exe|dll|so|dylib)$ ]] && return 0
  return 1
}

changed_files() {
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    {
      git -C "$ROOT" diff --name-only --diff-filter=ACMRTUXB HEAD 2>/dev/null || true
      git -C "$ROOT" diff --cached --name-only --diff-filter=ACMRTUXB 2>/dev/null || true
      git -C "$ROOT" status --short 2>/dev/null | awk '$1 == "??" { print $2 }' || true
    }
  else
    find "$ROOT" -maxdepth 4 -type f \
      -not -path '*/.git/*' \
      -not -path '*/node_modules/*' \
      -not -path '*/vendor/*' \
      -not -path '*/dist/*' \
      -not -path '*/build/*' \
      -not -path '*/coverage/*' \
      -not -path '*/.venv/*' \
      -not -path '*/venv/*' \
      -not -path '*/__pycache__/*' \
      \( \
        -name '*.sh' -o -name '*.bash' -o -name '*.zsh' -o -name '*.py' -o \
        -name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.jsx' -o \
        -name '*.php' -o -name '*.go' -o -name '*.rs' -o -name '*.tf' -o \
        -name '*.sql' -o -name '*.json' -o -name '*.yml' -o -name '*.yaml' -o \
        -name '*.toml' -o -name '*.md' -o -name 'Dockerfile' \
      \) \
      | sed "s#^$ROOT/##"
  fi | sort -u | while read -r f; do
    [[ -f "$f" ]] || continue
    is_ignored_file "$f" && continue
    echo "$f"
  done
}

repo_has() { [[ -e "$ROOT/$1" ]]; }

record_stack() {
  repo_has package.json && STACK+=("Node/JavaScript/TypeScript")
  { repo_has pyproject.toml || repo_has requirements.txt; } && STACK+=("Python")
  repo_has composer.json && STACK+=("PHP")
  repo_has go.mod && STACK+=("Go")
  repo_has Cargo.toml && STACK+=("Rust")
  { repo_has pom.xml || repo_has build.gradle || repo_has gradlew; } && STACK+=("Java/Kotlin")
  find "$ROOT" -maxdepth 2 \( -name '*.sln' -o -name '*.csproj' \) -print -quit 2>/dev/null | grep -q . && STACK+=(".NET/C#")
  repo_has pubspec.yaml && STACK+=("Dart/Flutter")
  repo_has Package.swift && STACK+=("Swift")
  find "$ROOT" -maxdepth 4 -type f \
    \( -name '*.sh' -o -name '*.bash' -o -name '*.zsh' \) \
    -print -quit 2>/dev/null | grep -q . && STACK+=("Shell")
  find "$ROOT" -maxdepth 4 -type f -name '*.md' -print -quit 2>/dev/null | grep -q . && STACK+=("Documentation")
}

check_universal_text() {
  local f="$1"
  local secrets debug debt long_lines insecure_assignments crypto_smells secret_regex
  secret_regex='(AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}'\
'|sk-[A-Za-z0-9_-]{32,}|xox[baprs]-[0-9A-Za-z-]{10,}'\
'|-----BEGIN [A-Z ]*PRIVATE KEY|AIza[0-9A-Za-z\-_]{35}'\
'|ssh-rsa [A-Za-z0-9+/=]+)'
  secrets=$(
    grep -nEo \
      "$secret_regex" \
      "$f" 2>/dev/null | head -5 || true
  )
  [[ -n "$secrets" ]] && add_fail "Security: possible secret/private key in $f
$secrets"

  insecure_assignments=$(
    grep -nEi \
      "(password|passwd|secret|api[_-]?key|token|client[_-]?secret)\\s*[:=]\\s*['\"][^'\"]{6,}['\"]" \
      "$f" 2>/dev/null | head -5 || true
  )
  [[ -n "$insecure_assignments" ]] && add_fail "Security: suspicious hardcoded credential in $f
$insecure_assignments"

  debug=""
  if [[ "$(basename "$f")" != "code-quality-gate.sh" ]]; then
    debug=$(
      awk '
        match($0, /\<(TODO|FIXME|HACK|XXX|NOSONAR)\>/) {
          print NR ":" $0
        }
      ' "$f" 2>/dev/null | head -8 || true
    )
  fi
  [[ -n "$debug" ]] && add_warn "Technical debt marker in $f
$debug"

  long_lines=$(awk 'length($0) > 180 { print FNR ": line longer than 180 chars" }' "$f" 2>/dev/null | head -5 || true)
  [[ -n "$long_lines" ]] && add_warn "Long lines in $f
$long_lines"

  crypto_smells=$(grep -nE '\b(md5|sha1)\s*\(' "$f" 2>/dev/null | head -5 || true)
  [[ -n "$crypto_smells" ]] && add_warn "Security smell: weak hash usage in $f
$crypto_smells"
}

check_repo_semgrep() {
  local semgrep out
  semgrep="$(find_bin semgrep)"
  [[ -n "$semgrep" ]] || { add_na "Repository SAST not checked: semgrep not found"; return; }
  out="$(run_capture_in_root "$semgrep" --config auto --error --metrics=off . || true)"
  if echo "$out" | grep -qiE 'findings|\berror\b|\bwarning\b'; then
    add_fail "Repository SAST failed
$(echo "$out" | tail -80)"
  else
    add_pass "Repository SAST passed"
  fi
}

check_repo_security() {
  local out package_manager py
  [[ "$REPO_SECURITY_DONE" -eq 1 ]] && return 0
  REPO_SECURITY_DONE=1

  if [[ -f "$ROOT/package.json" ]]; then
    package_manager="npm"
    [[ -f "$ROOT/pnpm-lock.yaml" ]] && package_manager="pnpm"
    [[ -f "$ROOT/yarn.lock" ]] && package_manager="yarn"
    case "$package_manager" in
      pnpm)
        if has pnpm; then
          out="$(run_capture_in_root pnpm audit --audit-level high || true)"
          if echo "$out" | grep -qiE 'high|critical|vulnerabilities found'; then
            add_fail "Node dependency audit failed
$(echo "$out" | tail -80)"
          elif [[ -n "$out" ]]; then
            add_pass "Node dependency audit passed"
          else
            add_na "Node dependency audit not checked: pnpm audit produced no actionable output"
          fi
        else
          add_na "Node dependency audit not checked: pnpm not found"
        fi
        ;;
      yarn)
        if has yarn; then
          out="$(run_capture_in_root yarn audit --level high || true)"
          if echo "$out" | grep -qiE 'high|critical|vulnerab'; then
            add_fail "Node dependency audit failed
$(echo "$out" | tail -80)"
          elif [[ -n "$out" ]]; then
            add_pass "Node dependency audit passed"
          else
            add_na "Node dependency audit not checked: yarn audit produced no actionable output"
          fi
        else
          add_na "Node dependency audit not checked: yarn not found"
        fi
        ;;
      *)
        if has npm; then
          out="$(run_capture_in_root npm audit --audit-level=high || true)"
          if echo "$out" | grep -qiE 'high|critical|vulnerab'; then
            add_fail "Node dependency audit failed
$(echo "$out" | tail -80)"
          elif [[ -n "$out" ]]; then
            add_pass "Node dependency audit passed"
          else
            add_na "Node dependency audit not checked: npm audit produced no actionable output"
          fi
        else
          add_na "Node dependency audit not checked: npm not found"
        fi
        ;;
    esac
  fi

  if [[ -f "$ROOT/pyproject.toml" || -f "$ROOT/requirements.txt" ]]; then
    py="$(find_python)"
    if py_has "$py" pip_audit; then
      out="$(run_capture "$py" -m pip_audit || true)"
      if echo "$out" | grep -qiE 'vuln|advisory|fix versions'; then
        add_fail "Python dependency audit failed
$(echo "$out" | tail -80)"
      else
        add_pass "Python dependency audit passed"
      fi
    elif py_has "$py" safety; then
      out="$(run_capture "$py" -m safety check --full-report || true)"
      if echo "$out" | grep -qiE 'vulnerability|vulnerabilities reported'; then
        add_fail "Python dependency audit failed
$(echo "$out" | tail -80)"
      else
        add_pass "Python dependency audit passed"
      fi
    else
      add_na "Python dependency audit not checked: pip-audit/safety not found"
    fi
  fi

  if [[ -f "$ROOT/go.mod" ]]; then
    if has gosec; then
      out="$(run_capture_in_root gosec ./... || true)"
      if echo "$out" | grep -qiE 'Issues|Severity|G10[0-9]|G20[0-9]'; then
        add_fail "Go security scan failed
$(echo "$out" | tail -80)"
      else
        add_pass "Go security scan passed"
      fi
    else
      add_na "Go security scan not checked: gosec not found"
    fi
  fi

  if [[ -f "$ROOT/Cargo.toml" ]]; then
    if has cargo-audit; then
      out="$(run_capture_in_root cargo-audit || true)"
      if echo "$out" | grep -qiE 'vulnerabilities found|warning: [0-9]+ vulnerability'; then
        add_fail "Rust dependency audit failed
$(echo "$out" | tail -80)"
      else
        add_pass "Rust dependency audit passed"
      fi
    else
      add_na "Rust dependency audit not checked: cargo-audit not found"
    fi
  fi

  if [[ -f "$ROOT/composer.json" ]]; then
    if has composer; then
      out="$(run_capture_in_root composer audit --no-interaction || true)"
      if echo "$out" | grep -qiE 'advisories found|vulnerabilities'; then
        add_fail "PHP dependency audit failed
$(echo "$out" | tail -80)"
      else
        add_pass "PHP dependency audit passed"
      fi
    else
      add_na "PHP dependency audit not checked: composer not found"
    fi
  fi

  if find "$ROOT" -type f -name '*.tf' -print -quit 2>/dev/null | grep -q .; then
    if has tfsec; then
      out="$(run_capture_in_root tfsec . || true)"
      if echo "$out" | grep -qiE 'critical|high|medium|failed'; then
        add_fail "Terraform security scan failed
$(echo "$out" | tail -80)"
      else
        add_pass "Terraform security scan passed"
      fi
    elif has checkov; then
      out="$(run_capture_in_root checkov -d . || true)"
      if echo "$out" | grep -qiE 'FAILED|Check:'; then
        add_fail "IaC security scan failed
$(echo "$out" | tail -80)"
      else
        add_pass "IaC security scan passed"
      fi
    else
      add_na "IaC security scan not checked: tfsec/checkov not found"
    fi
  fi

  check_repo_semgrep
}

check_python() {
  local f="$1" py out module test_file pct pct_int
  py="$(find_python)"
  if py_has "$py" ruff; then
    out="$(run_capture "$py" -m ruff check "$f" --output-format=concise || true)"
    [[ -n "$out" ]] && add_fail "Python lint failed: $f
$out" || add_pass "Python lint passed: $f"
  elif py_has "$py" flake8; then
    out="$(run_capture "$py" -m flake8 "$f" --max-line-length=120 || true)"
    [[ -n "$out" ]] && add_fail "Python lint failed: $f
$out" || add_pass "Python lint passed: $f"
  else
    add_na "Python lint not checked for $f: ruff/flake8 not found"
  fi

  if py_has "$py" mypy; then
    out="$(run_capture "$py" -m mypy "$f" --ignore-missing-imports --no-error-summary || true)"
    out="$(echo "$out" | grep -vE '^(Found|Success)' | head -20 || true)"
    [[ -n "$out" ]] && add_fail "Python typecheck failed: $f
$out" || add_pass "Python typecheck passed: $f"
  fi

  if py_has "$py" radon; then
    out="$(run_capture "$py" -m radon cc "$f" -s -n C || true)"
    [[ -n "$out" ]] && add_warn "Python code smell: high cyclomatic complexity in $f
$(echo "$out" | head -10)"
  fi

  if py_has "$py" bandit; then
    out="$(run_capture "$py" -m bandit -q -ll "$f" || true)"
    out="$(echo "$out" | grep -E 'Issue|Severity|Location' | head -20 || true)"
    [[ -n "$out" ]] && add_fail "Python security issue: $f
$out" || add_pass "Python security passed: $f"
  else
    add_na "Python security not checked for $f: bandit not found"
  fi

  out="$(grep -nE 'subprocess\.(run|Popen|call|check_output).*shell\s*=\s*True|os\.system\(|yaml\.load\(|pickle\.loads?\(|eval\(|exec\(' "$f" 2>/dev/null | head -8 || true)"
  [[ -n "$out" ]] && add_fail "Python risky API usage in $f
$out"

  module="$(basename "$f" .py)"
  test_file="$(find "$ROOT" \( -name "test_${module}.py" -o -name "${module}_test.py" \) -not -path '*/node_modules/*' 2>/dev/null | head -1)"
  if [[ -n "$test_file" ]] && py_has "$py" pytest; then
    out="$(run_capture "$py" -m pytest "$test_file" --cov="$(dirname "$f")" --cov-report=term-missing --cov-fail-under=80 -q --tb=short || true)"
    pct="$(echo "$out" | grep -oE '[0-9]+%' | tail -1 | tr -d '%' || true)"
    if echo "$out" | grep -qiE 'failed|error|FAIL'; then
      add_fail "Python tests/coverage failed for $f
$(echo "$out" | tail -40)"
    elif [[ -n "$pct" ]]; then
      pct_int="${pct%.*}"
      (( pct_int >= 80 )) && add_pass "Python coverage passed: ${pct}% for $f" || add_fail "Python coverage below 80%: ${pct}% for $f"
    else
      add_warn "Python tests ran but coverage was not measured for $f"
    fi
  else
    add_na "Python coverage not measured for $f: matching test or pytest/pytest-cov not found"
  fi
}

check_js_ts() {
  local f="$1" ext eslint fmt raw errors warnings tsc module test_file runner out pct pct_int
  ext="${f##*.}"
  eslint="$(find_bin eslint "$f")"
  if [[ -n "$eslint" ]]; then
    fmt="stylish"
    raw="$(run_capture "$eslint" "$f" --format="$fmt" --no-warn-ignored || true)"
    errors="$(echo "$raw" | grep -iE 'error|✖' | head -20 || true)"
    warnings="$(echo "$raw" | grep -iE 'warning' | head -10 || true)"
    [[ -n "$errors" ]] && add_fail "ESLint failed: $f
$errors" || add_pass "ESLint passed: $f"
    [[ -n "$warnings" ]] && add_warn "ESLint warnings: $f
$warnings"
  else
    add_na "JS/TS lint not checked for $f: eslint not found"
  fi

  if [[ "$ext" =~ ^(ts|tsx)$ ]]; then
    tsc="$(find_bin tsc "$f")"
    if [[ -n "$tsc" ]]; then
      out="$(cd "$ROOT" && run_capture "$tsc" --noEmit --skipLibCheck || true)"
      out="$(echo "$out" | grep -F "$(basename "$f")" | head -20 || true)"
      [[ -n "$out" ]] && add_fail "TypeScript check failed: $f
$out" || add_pass "TypeScript check passed: $f"
    else
      add_na "TypeScript check not run: tsc not found"
    fi
  fi

  local dangerous any_count long_fn
  dangerous="$(grep -nE 'eval\s*\(|\.innerHTML\s*=|dangerouslySetInnerHTML|document\.write\s*\(' "$f" 2>/dev/null | head -8 || true)"
  [[ -n "$dangerous" ]] && add_fail "JS/TS security risk in $f
$dangerous"
  any_count="$(grep -c ': any' "$f" 2>/dev/null || echo 0)"
  [[ "$any_count" =~ ^[0-9]+$ ]] && (( any_count > 3 )) && add_warn "TypeScript code smell: excessive 'any' usage in $f (${any_count} occurrences)"
  long_fn="$(awk '/function |\) \{|=> \{/{fn=NR} fn&&NR-fn>70{print "line "fn" (~"NR-fn" lines)";fn=0}' "$f" 2>/dev/null | head -3 || true)"
  [[ -n "$long_fn" ]] && add_warn "JS/TS code smell: long functions in $f
$long_fn"

  runner="$(find_bin vitest "$f")"
  [[ -z "$runner" ]] && runner="$(find_bin jest "$f")"
  module="$(basename "$f" | sed 's/\.[^.]*$//')"
  test_file="$(find "$ROOT" \( -name "${module}.test.*" -o -name "${module}.spec.*" \) -not -path '*/node_modules/*' 2>/dev/null | head -1)"
  if [[ -n "$runner" && -n "$test_file" ]]; then
    if [[ "$(basename "$runner")" == "vitest" ]]; then
      out="$(run_capture "$runner" run "$test_file" --coverage || true)"
    else
      out="$(run_capture "$runner" "$test_file" --coverage --passWithNoTests || true)"
    fi
    if echo "$out" | grep -qiE 'failed|error|FAIL|Tests:.*failed'; then
      add_fail "JS/TS tests failed for $f
$(echo "$out" | tail -50)"
    else
      add_pass "JS/TS tests ran for $f"
      pct="$(echo "$out" | grep -E 'All files|Lines' | grep -oE '[0-9]+(\.[0-9]+)?' | tail -1 || true)"
      if [[ -n "$pct" ]]; then
        pct_int="${pct%.*}"
        (( pct_int >= 80 )) && add_pass "JS/TS coverage passed: ${pct}% for $f" || add_fail "JS/TS coverage below 80%: ${pct}% for $f"
      else
        add_warn "JS/TS coverage could not be parsed for $f"
      fi
    fi
  else
    add_na "JS/TS coverage not measured for $f: matching test or jest/vitest not found"
  fi
}

check_go() {
  local f="$1" out pkg pct pct_int
  if has go; then
    out="$(run_capture gofmt -l "$f" || true)"
    [[ -n "$out" ]] && add_fail "Go format required: $f" || add_pass "Go format passed: $f"
    pkg="./$(realpath --relative-to="$ROOT" "$(dirname "$f")")/..."
    out="$(cd "$ROOT" && run_capture go vet "$pkg" || true)"
    [[ -n "$out" ]] && add_fail "Go vet failed: $pkg
$out" || add_pass "Go vet passed: $pkg"
    out="$(cd "$ROOT" && run_capture go test "$pkg" -cover -coverprofile=/tmp/code-quality-gate-go.out || true)"
    if echo "$out" | grep -qiE 'FAIL|failed'; then
      add_fail "Go tests failed for $pkg
$out"
    else
      pct="$(go tool cover -func=/tmp/code-quality-gate-go.out 2>/dev/null | grep 'total:' | grep -oE '[0-9]+\.[0-9]+' || true)"
      if [[ -n "$pct" ]]; then
        pct_int="${pct%.*}"
        (( pct_int >= 80 )) && add_pass "Go coverage passed: ${pct}% for $pkg" || add_fail "Go coverage below 80%: ${pct}% for $pkg"
      else
        add_pass "Go tests passed for $pkg"
        add_warn "Go coverage not parsed for $pkg"
      fi
    fi
  else
    add_na "Go checks not run: go not found"
  fi
}

check_php() {
  local f="$1" out tool
  if has php; then
    out="$(run_capture php -l "$f" || true)"
    echo "$out" | grep -qi 'No syntax errors' && add_pass "PHP syntax passed: $f" || add_fail "PHP syntax failed: $f
$out"
  else
    add_na "PHP syntax not checked: php not found"
  fi
  for tool in phpcs phpstan psalm; do
    if has "$tool"; then
      out="$(run_capture "$tool" "$f" || true)"
      [[ -n "$out" ]] && add_warn "PHP $tool output for $f
$(echo "$out" | head -30)" || add_pass "PHP $tool passed: $f"
    fi
  done

  out="$(grep -nE '(^|[^A-Za-z_])(eval|exec|shell_exec|system|passthru|unserialize)\s*\(' "$f" 2>/dev/null | head -8 || true)"
  [[ -n "$out" ]] && add_fail "PHP risky API usage in $f
$out"
}

check_rust() {
  local out
  has cargo || { add_na "Rust checks not run: cargo not found"; return; }
  out="$(cd "$ROOT" && run_capture cargo fmt --check || true)"
  [[ -n "$out" ]] && add_fail "Rust format failed
$out" || add_pass "Rust format passed"
  out="$(cd "$ROOT" && run_capture cargo clippy --all-targets --all-features -- -D warnings || true)"
  [[ -n "$out" ]] && add_fail "Rust clippy failed
$(echo "$out" | tail -60)" || add_pass "Rust clippy passed"
  out="$(cd "$ROOT" && run_capture cargo test || true)"
  echo "$out" | grep -qiE 'test result: FAILED|error:' && add_fail "Rust tests failed
$(echo "$out" | tail -60)" || add_pass "Rust tests passed"
}

check_shell() {
  local f="$1" out
  if has shellcheck; then
    out="$(run_capture shellcheck -f gcc "$f" || true)"
    [[ -n "$out" ]] && add_fail "ShellCheck failed: $f
$out" || add_pass "ShellCheck passed: $f"
  else
    add_na "Shell lint not checked for $f: shellcheck not found"
  fi
}

check_dotnet_repo() {
  local out
  has dotnet || { add_na ".NET checks not run: dotnet not found"; return; }
  out="$(cd "$ROOT" && run_capture dotnet build --nologo || true)"
  echo "$out" | grep -qiE 'Build FAILED|error ' && add_fail ".NET build failed
$(echo "$out" | tail -80)" || add_pass ".NET build passed"
  out="$(cd "$ROOT" && run_capture dotnet test --nologo --no-build || true)"
  echo "$out" | grep -qiE 'Failed:|Error|failed' && add_fail ".NET tests failed
$(echo "$out" | tail -80)" || add_pass ".NET tests passed"
}

check_java_kotlin_repo() {
  local out
  if [[ -x "$ROOT/gradlew" ]]; then
    out="$(cd "$ROOT" && run_capture ./gradlew test check --continue || true)"
    echo "$out" | grep -qiE 'BUILD FAILED|FAILED' && add_fail "Gradle checks failed
$(echo "$out" | tail -100)" || add_pass "Gradle checks passed"
  elif [[ -f "$ROOT/pom.xml" ]] && has mvn; then
    out="$(cd "$ROOT" && run_capture mvn test -q || true)"
    echo "$out" | grep -qiE 'BUILD FAILURE|Failed tests|ERROR' && add_fail "Maven tests failed
$(echo "$out" | tail -100)" || add_pass "Maven tests passed"
  else
    add_na "Java/Kotlin checks not run: gradle wrapper or mvn not found"
  fi
}

check_dart_flutter_repo_or_file() {
  local out runner="dart"
  [[ -f "$ROOT/pubspec.yaml" ]] || return 0
  if has flutter && grep -q 'flutter:' "$ROOT/pubspec.yaml" 2>/dev/null; then runner="flutter"; fi
  has "$runner" || { add_na "Dart/Flutter checks not run: $runner not found"; return; }
  out="$(cd "$ROOT" && run_capture "$runner" analyze || true)"
  echo "$out" | grep -qiE 'error|issues found' && add_fail "Dart/Flutter analyze failed
$(echo "$out" | tail -80)" || add_pass "Dart/Flutter analyze passed"
  out="$(cd "$ROOT" && run_capture "$runner" test --coverage || true)"
  echo "$out" | grep -qiE 'Some tests failed|failed|error' && add_fail "Dart/Flutter tests failed
$(echo "$out" | tail -80)" || add_pass "Dart/Flutter tests passed"
}

check_swift_repo() {
  local out
  [[ -f "$ROOT/Package.swift" ]] || return 0
  has swift || { add_na "Swift checks not run: swift not found"; return; }
  out="$(cd "$ROOT" && run_capture swift test || true)"
  echo "$out" | grep -qiE 'error:|failed' && add_fail "Swift tests failed
$(echo "$out" | tail -80)" || add_pass "Swift tests passed"
  if has swiftlint; then
    out="$(cd "$ROOT" && run_capture swiftlint || true)"
    [[ -n "$out" ]] && add_warn "SwiftLint output
$(echo "$out" | head -80)" || add_pass "SwiftLint passed"
  fi
}

check_config_file() {
  local f="$1" ext="${1##*.}" out prettier yamllint markdownlint taplo
  case "$ext" in
    json)
      if has jq; then out="$(run_capture jq empty "$f" || true)"; else out="$(run_capture python3 -m json.tool "$f" >/dev/null || true)"; fi
      [[ -n "$out" ]] && add_fail "JSON validation failed: $f
$out" || add_pass "JSON validation passed: $f"
      ;;
    yml|yaml)
      yamllint="$(find_bin yamllint "$f")"
      if [[ -n "$yamllint" ]]; then out="$(run_capture "$yamllint" "$f" || true)"; [[ -n "$out" ]] && add_warn "YAML lint output: $f
$out" || add_pass "YAML lint passed: $f"; else add_na "YAML lint not checked for $f: yamllint not found"; fi
      ;;
    toml)
      taplo="$(find_bin taplo "$f")"
      if [[ -n "$taplo" ]]; then out="$(run_capture "$taplo" lint "$f" || true)"; [[ -n "$out" ]] && add_warn "TOML lint output: $f
$out" || add_pass "TOML lint passed: $f"; else add_na "TOML lint not checked for $f: taplo not found"; fi
      ;;
    md)
      markdownlint="$(find_bin markdownlint "$f")"
      if [[ -n "$markdownlint" ]]; then out="$(run_capture "$markdownlint" "$f" || true)"; [[ -n "$out" ]] && add_warn "Markdown lint output: $f
$out" || add_pass "Markdown lint passed: $f"; fi
      ;;
  esac
}

check_iac_or_misc() {
  local f="$1" base ext out
  base="$(basename "$f")"
  ext="${f##*.}"
  if [[ "$base" == Dockerfile* ]]; then
    if has hadolint; then out="$(run_capture hadolint "$f" || true)"; [[ -n "$out" ]] && add_warn "Dockerfile lint output: $f
$out" || add_pass "Dockerfile lint passed: $f"; else add_na "Dockerfile lint not checked: hadolint not found"; fi
  elif [[ "$ext" == tf ]]; then
    if has terraform; then
      out="$({
        cd "$(dirname "$f")" &&
          run_capture terraform fmt -check -diff &&
          run_capture terraform validate
      } 2>&1 || true)"
      [[ -n "$out" ]] && add_warn "Terraform output: $f
$out" || add_pass "Terraform checks passed: $f"
    else
      add_na "Terraform checks not run: terraform not found"
    fi
  elif [[ "$ext" == sql ]]; then
    if has sqlfluff; then out="$(run_capture sqlfluff lint "$f" || true)"; [[ -n "$out" ]] && add_warn "SQL lint output: $f
$out" || add_pass "SQL lint passed: $f"; else add_na "SQL lint not checked: sqlfluff not found"; fi
  fi
}

check_file() {
  local f="$1" ext base
  [[ -f "$f" ]] || { add_na "Skipped missing file: $f"; return; }
  is_ignored_file "$f" && return
  ext="$(echo "${f##*.}" | tr '[:upper:]' '[:lower:]')"
  base="$(basename "$f")"
  check_universal_text "$f"
  case "$ext" in
    py) check_python "$f" ;;
    js|jsx|ts|tsx|mjs|cjs) check_js_ts "$f" ;;
    go) check_go "$f" ;;
    php) check_php "$f" ;;
    rs) check_rust ;;
    sh|bash|zsh) check_shell "$f" ;;
    json|yml|yaml|toml|md) check_config_file "$f" ;;
    tf|sql) check_iac_or_misc "$f" ;;
    dart) check_dart_flutter_repo_or_file ;;
    swift) check_swift_repo ;;
    java|kt|kts) check_java_kotlin_repo ;;
    cs) check_dotnet_repo ;;
    c|cc|cpp|cxx|h|hpp)
      if has clang-tidy; then out="$(run_capture clang-tidy "$f" -- 2>/dev/null || true)"; [[ -n "$out" ]] && add_warn "clang-tidy output: $f
$(echo "$out" | head -60)" || add_pass "clang-tidy passed: $f"; else add_na "C/C++ static analysis not checked for $f: clang-tidy not found"; fi
      if has cppcheck; then out="$(run_capture cppcheck --enable=warning,style,performance,portability "$f" || true)"; [[ -n "$out" ]] && add_warn "cppcheck output: $f
$out" || add_pass "cppcheck passed: $f"; fi
      ;;
    *) check_iac_or_misc "$f" ;;
  esac
}

run_repo_checks() {
  local out script package_manager
  if [[ -f "$ROOT/package.json" ]]; then
    package_manager="npm"
    [[ -f "$ROOT/pnpm-lock.yaml" ]] && package_manager="pnpm"
    [[ -f "$ROOT/yarn.lock" ]] && package_manager="yarn"
    for script in lint typecheck test build; do
      if python3 - "$ROOT/package.json" "$script" <<'PY' >/dev/null 2>&1
import json,sys
p=json.load(open(sys.argv[1]))
raise SystemExit(0 if sys.argv[2] in p.get('scripts',{}) else 1)
PY
      then
        case "$package_manager" in
          pnpm) out="$(cd "$ROOT" && run_capture pnpm "$script" || true)" ;;
          yarn) out="$(cd "$ROOT" && run_capture yarn "$script" || true)" ;;
          *) out="$(cd "$ROOT" && run_capture npm run "$script" || true)" ;;
        esac
        echo "$out" | grep -qiE 'error|failed|FAIL|✖' && add_fail "package script failed: $script
$(echo "$out" | tail -80)" || add_pass "package script passed: $script"
      fi
    done
  fi

  if [[ -f "$ROOT/Makefile" ]] && grep -Eq '^(test|lint|quality|check):' "$ROOT/Makefile"; then
    for script in quality check lint test; do
      if grep -Eq "^${script}:" "$ROOT/Makefile"; then
        out="$(cd "$ROOT" && run_capture make "$script" || true)"
        echo "$out" | grep -qiE 'error|failed|FAIL' && add_fail "make $script failed
$(echo "$out" | tail -80)" || add_pass "make $script passed"
        break
      fi
    done
  fi

  [[ -f "$ROOT/Cargo.toml" ]] && check_rust
  find "$ROOT" -maxdepth 2 \( -name '*.sln' -o -name '*.csproj' \) -print -quit 2>/dev/null | grep -q . && check_dotnet_repo
  { [[ -f "$ROOT/pom.xml" ]] || [[ -f "$ROOT/build.gradle" ]] || [[ -x "$ROOT/gradlew" ]]; } && check_java_kotlin_repo
  [[ -f "$ROOT/pubspec.yaml" ]] && check_dart_flutter_repo_or_file
  [[ -f "$ROOT/Package.swift" ]] && check_swift_repo
  check_repo_security
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --changed) MODE="changed"; shift ;;
    --repo) MODE="repo"; shift ;;
    --advisory) ADVISORY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

hook_file="$(json_hook_file_from_stdin || true)"
[[ -n "$hook_file" ]] && FILES+=("$hook_file")

cd "$ROOT" || exit 1
record_stack

case "$MODE" in
  changed)
    mapfile -t FILES < <(changed_files)
    [[ ${#FILES[@]} -eq 0 ]] && add_na "No changed files detected"
    ;;
  repo)
    run_repo_checks
    mapfile -t FILES < <(changed_files)
    ;;
esac

if [[ "$MODE" == "files" && ${#FILES[@]} -eq 0 ]]; then
  usage
  exit 1
fi

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  check_file "$f"
done

if [[ "$MODE" != "repo" ]]; then
  # Run lightweight repo checks for ecosystems where file-level checks are unreliable.
  [[ -f "$ROOT/Cargo.toml" ]] && printf '%s\n' "${FILES[@]}" | grep -qE '\.rs$' && check_rust
  find "$ROOT" -maxdepth 2 \( -name '*.sln' -o -name '*.csproj' \) -print -quit 2>/dev/null | grep -q . && printf '%s\n' "${FILES[@]}" | grep -qE '\.cs$' && check_dotnet_repo
  printf '%s\n' "${FILES[@]}" | grep -qE '\.(js|jsx|ts|tsx|py|php|tf|go|rs|ya?ml|json|toml|sh|bash|zsh)$' && check_repo_security
fi

printf '\n%s\n' '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
printf '  Code Quality Gate Report\n'
printf '%s\n' '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
printf 'Root: %s\n' "$ROOT"
printf 'Mode: %s\n' "$MODE"
printf 'Stack detected: %s\n' "$(IFS=', '; echo "${STACK[*]:-unknown}")"
printf 'Files checked: %s\n' "${#FILES[@]}"

if [[ ${#COMMANDS_RUN[@]} -gt 0 ]]; then
  printf '\nCommands run:\n'
  for c in "${COMMANDS_RUN[@]}"; do printf -- '- %s\n' "$c"; done
fi

[[ ${#PASS[@]} -gt 0 ]] && { printf '\nPASS:\n'; for x in "${PASS[@]}"; do printf -- '- %b\n' "$x"; done; }
[[ ${#NOT_CHECKED[@]} -gt 0 ]] && { printf '\nNOT CHECKED:\n'; for x in "${NOT_CHECKED[@]}"; do printf -- '- %b\n' "$x"; done; }
[[ ${#WARN[@]} -gt 0 ]] && { printf '\nWARNINGS:\n'; for x in "${WARN[@]}"; do printf -- '- %b\n' "$x"; done; }
[[ ${#FAIL[@]} -gt 0 ]] && { printf '\nBLOCKING ISSUES:\n'; for x in "${FAIL[@]}"; do printf -- '- %b\n' "$x"; done; }

printf '\nDecision: '
if [[ ${#FAIL[@]} -gt 0 ]]; then
  printf 'NOT READY\n'
  [[ "$ADVISORY" -eq 1 ]] && exit 0 || exit 2
elif [[ ${#WARN[@]} -gt 0 || ${#NOT_CHECKED[@]} -gt 0 ]]; then
  printf 'READY WITH WARNINGS\n'
  exit 0
else
  printf 'READY TO MERGE\n'
  exit 0
fi
