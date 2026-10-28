# CI and local Codex repair

Open a pull request from your feature branch early. `.github/workflows/ci.yml` runs on pull requests, pushes to `main`, and manual dispatch. Its jobs are:

| Job | What it checks |
| --- | --- |
| Swift lint | SwiftLint 0.65.1 with a deliberately small rule set. Its upstream binary is checked against the published SHA-256. Expand the rules after cleaning existing code. |
| Workflow lint | GitHub Actions syntax and embedded shell with actionlint. |
| macOS app checks | Builds Tile and runs the existing smoke, layout, focus, keyboard, and agent checks. |
| Package app | Builds the preview ZIP and checks its plist, ad hoc signature, and ZIP integrity. |
| CodeQL Swift | Static security analysis of a macOS Swift build. |
| CodeQL workflows | Static security analysis of the Actions files. |
| Dependency review | Blocks pull requests that introduce dependencies with high or critical known vulnerabilities. |

Dependabot checks GitHub Actions and Swift package versions weekly. Its proposed updates still need review and CI.

After the first successful CI run, configure branch protection on `main` to require the checks that should block merging. Workflow files alone do not make checks mandatory.

The macOS test job sets `TILE_SKIP_MANAGED_CODEX=1`. It does not install Codex or supply AI credentials. The separate authenticated `--codex-live-test` and `--managed-codex-live-test` commands remain manual. `Tests/` currently has no test target, so `swift test` is not part of CI yet.

The test job uploads `ci-test-evidence` with its log and feature-branch commit SHA on every run. It attempts a screenshot on failure, but a screenshot is only a best-effort view of the runner desktop after the test exits. It is not a frame captured at the failing assertion. The job is an app integration check; it does not install and launch the packaged `.app`, test signing or notarization, or prove every user flow.

## Repair a failed check with your local Codex CLI

1. Open the failed **macOS app checks** job on GitHub, download the **ci-test-evidence** artifact, and extract its ZIP into `<repo>/to-fix/`. Keep one run in this folder at a time. The helper accepts `test.log` and `head-sha.txt` directly in `to-fix/` or together in a subfolder. Keep `failure.png` beside them if present.
2. Switch your local checkout to the feature branch at the same commit as the failed run. Commit or stash unrelated work. The helper refuses to run unless your checkout is clean, matches the remote feature branch, and matches the artifact's `head-sha.txt`.
3. Ensure your local Codex CLI is installed and signed in, then run `bash scripts/fix-from-artifacts.sh`. Codex reads the log and receives the screenshot when present. It uses your local CLI authentication and account usage; no GitHub Actions API key is needed.
4. The helper accepts source changes only under `Sources/Tile/*.swift`, excluding `SmokeTest.swift`. It runs `TILE_SKIP_MANAGED_CODEX=1 ./scripts/test.sh`; if that passes and the remote branch has not moved, it commits and pushes to your feature branch. The pull request CI runs again. If the evidence points to a test harness or CI problem, fix that manually rather than letting Codex weaken the checks.

`to-fix/` is ignored by Git. Do not force-add it. CI logs and screenshots may contain sensitive data; Git ignore prevents accidental commits but does not remove data you give to Codex. Download only the evidence you intend Codex to inspect.

The local repair uses Codex account quota and cannot promise zero AI token use. GitHub Actions test execution itself uses none. The helper can verify only the existing app checks locally; full lint, CodeQL, and dependency review still run in CI after the push. An automatically pushed fix still needs human review before merging.

CodeQL upload and Dependency Review depend on the repository's GitHub security feature availability. Dependency Review is available for public repositories and private repositories with the required GitHub security license. If those jobs cannot be enabled for this repository, they should be made explicitly unavailable rather than silently marked as passed.
