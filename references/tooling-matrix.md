# Tooling Matrix

This file documents preferred quality checks by ecosystem. The quality gate script only runs tools that are already available.

| Ecosystem | Lint/style | Type/build | Tests | Coverage | Security/code smell |
|---|---|---|---|---|---|
| JavaScript / TypeScript | eslint, prettier | tsc, npm build | jest, vitest, playwright | jest/vitest coverage | secret scan, dangerous APIs, npm/pnpm/yarn audit |
| Python | ruff, flake8 | mypy, pyright | pytest | pytest-cov, coverage | bandit, radon, pip-audit or safety |
| PHP | php -l, pint, phpcs | phpstan, psalm | phpunit, pest | phpunit/pest coverage config | hardcoded credentials, debug calls, composer audit |
| Go | gofmt, go vet, golangci-lint | go test build | go test | go test -cover | gosec if installed |
| Java | checkstyle, pmd | maven/gradle build | maven/gradle test | jacoco when configured | spotbugs, dependency/security plugins |
| Kotlin | ktlint | gradle build/check | gradle test | jacoco when configured | detekt, dependency/security plugins |
| C# / .NET | dotnet format | dotnet build | dotnet test | coverlet when configured | analyzers, security analyzers when present |
| Rust | cargo fmt | cargo clippy | cargo test | tarpaulin when configured | cargo audit if installed |
| Ruby | rubocop | bundle exec rake | rspec/minitest | simplecov when configured | brakeman, bundle-audit if installed |
| Swift | swiftformat, swiftlint | swift build | swift test | xccov when configured | advisory |
| Dart / Flutter | dart format | dart/flutter analyze | dart/flutter test | flutter test --coverage | advisory |
| C / C++ | clang-format | cmake/build, clang-tidy | ctest | gcov/lcov when configured | cppcheck |
| Shell | shfmt, shellcheck | shell syntax | bats/shunit2 | not standard | shellcheck |
| SQL | sqlfluff | parser/project validation | db tests when configured | not standard | sqlfluff rules |
| Terraform | terraform fmt | terraform validate | module tests if configured | not standard | tflint, tfsec, checkov |
| Docker | hadolint | docker build if requested | integration tests | not standard | hadolint, trivy if installed |
| YAML / JSON / TOML / Markdown | prettier, yamllint, markdownlint, taplo | parser validation | not standard | not standard | advisory |
