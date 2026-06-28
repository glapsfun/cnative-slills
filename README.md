# cnative-skills

[![CI](https://github.com/glapsfun/cnative-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/glapsfun/cnative-skills/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Agentic skills for cloud-native tools, distributed as a [Claude Code plugin marketplace](https://docs.anthropic.com/en/docs/claude-code) and as standard Agent Skills that can be installed into Codex.

## Plugins

| Plugin | Description |
| :--- | :--- |
| `kubernetes-operator` | Expert Kubernetes assistant — kubectl commands and scripting, writing/reviewing manifests, Helm charts, GitOps (Flux, Argo CD, kustomize), security hardening, debugging playbooks (CrashLoopBackOff, Pending pods, ImagePullBackOff, OOMKilled, and more), and cluster operations. |
| `kagent` | Expert guide for [kagent](https://kagent.dev) — the CNCF framework for running AI agents on Kubernetes: CLI, Agent/ModelConfig/RemoteMCPServer CRDs, MCP tools, A2A subagents, human-in-the-loop approval, long-term memory, IDE integration, Helm/OIDC/observability, and troubleshooting. Derived from and extending the upstream [kagent skill](https://github.com/kagent-dev/kagent/tree/main/.claude/skills/kagent) (Apache-2.0). |
| `kgateway` | Expert guide for [kgateway](https://kgateway.dev) — the CNCF Kubernetes Gateway API implementation powered by Envoy (formerly Gloo by Solo.io): installation, Gateway/HTTPRoute/TCPRoute setup, traffic management (splitting, delegation, transformations), security (TLS/mTLS, JWT, ext-auth, rate limiting, CORS, IP ACL), resiliency (retries, timeouts, circuit breakers, fault injection), Istio integration, observability, debugging, and upgrade procedures including v2.3 migration. |
| `fluxcd` | Expert guide for [Flux CD](https://fluxcd.io/flux/) — Kubernetes GitOps install/bootstrap, repository structure, Flux source/Kustomization/Helm/notification resources, SOPS and RBAC security, schema validation, operations, upgrades, and troubleshooting. |
| `argocd` | Expert guide for [Argo CD](https://argo-cd.readthedocs.io/) — Kubernetes GitOps install/upgrade, Application/AppProject/ApplicationSet resources, Helm/Kustomize workflows, RBAC/SSO security, notifications, HA operations, and troubleshooting sync, health, drift, repository, and controller issues. |
| `bash-scripting` | Expert guide for writing, hardening, debugging, and reviewing [Bash](https://www.gnu.org/software/bash/) and POSIX shell scripts — strict mode, defensive patterns, safe quoting/expansion, arrays, trap-based cleanup, getopts/long-option parsing, ShellCheck/shfmt linting, Bats testing, and Linux/macOS (GNU vs BSD) portability. Ships scaffold, lint, version-check, and doc-discovery scripts. |
| `helm` | Expert guide for [Helm](https://helm.sh/) — authoring charts (Chart.yaml, values, `values.schema.json`, `_helpers.tpl`, dependencies, hooks), Go/Sprig templating, the `helm` CLI and release lifecycle (install/upgrade/rollback), discovering and vendoring existing charts from repositories/Artifact Hub/OCI, and debugging chart-rendering vs release failures with lint, template, dry-run, and manifest inspection. Ships version-check, chart-validate, release-debug, and doc-discovery scripts. |

---

## Installation

### Method 1 — Claude Code (slash commands, recommended)

This is the standard way to install plugins in Claude Code or any environment that supports the `/plugin` slash command (including the Claude desktop app and VS Code/JetBrains extensions).

**Step 1 — Add the marketplace** (one-time per machine):

```
/plugin marketplace add glapsfun/cnative-skills
```

This registers the marketplace under the alias **`cnative-skills`** from the `name` field in `.claude-plugin/marketplace.json`.

**Step 2 — Install a plugin**:

```
/plugin install kubernetes-operator@cnative-skills
```

Replace `kubernetes-operator` with any plugin name from the table above.

**To update all plugins from this marketplace** after new versions are published:

```
/plugin marketplace update cnative-skills
```

**To remove a plugin**:

```
/plugin remove kubernetes-operator
```

---

### Method 2 — Claude Code CLI (non-interactive)

If you have `claude` on your `PATH` (or use `npx @anthropic-ai/claude-code` to run it without a global install), the `plugin` subcommand works non-interactively:

```bash
claude plugin marketplace add glapsfun/cnative-skills
claude plugin install kubernetes-operator@cnative-skills
```

With npx (no prior global install required):

```bash
npx @anthropic-ai/claude-code plugin marketplace add glapsfun/cnative-skills
npx @anthropic-ai/claude-code plugin install kubernetes-operator@cnative-skills
```

> Note: `claude "/plugin ..."` (with the slash command as a quoted string) passes that string as a model prompt, not as a plugin command — use `claude plugin ...` (no leading slash) for non-interactive use.

---

### Method 3 — Codex skills (`npx skills`)

Use this method to install one of this repository's `SKILL.md` folders into Codex. This writes to the global Codex skills directory (`~/.codex/skills/` unless `CODEX_HOME` is set):

```bash
npx skills add glapsfun/cnative-skills --skill kubernetes-operator --agent codex --global -y
```

Replace `kubernetes-operator` with any skill name from this repository:

```bash
npx skills add glapsfun/cnative-skills --skill kagent --agent codex --global -y
npx skills add glapsfun/cnative-skills --skill kgateway --agent codex --global -y
npx skills add glapsfun/cnative-skills --skill fluxcd --agent codex --global -y
npx skills add glapsfun/cnative-skills --skill argocd --agent codex --global -y
npx skills add glapsfun/cnative-skills --skill bash-scripting --agent codex --global -y
npx skills add glapsfun/cnative-skills --skill helm --agent codex --global -y
```

To install into the current project instead of globally, omit `--global`:

```bash
npx skills add glapsfun/cnative-skills --skill kubernetes-operator --agent codex -y
```

Verify the install:

```bash
npx skills list -a codex
```

Restart Codex after installing or updating skills so the new skill metadata is loaded.

Codex marketplace metadata also lives in `.agents/plugins/marketplace.json`, and plugin manifests live in `plugins/<name>/.codex-plugin/plugin.json`, but `npx skills` installs the actual skill folders from `plugins/<name>/skills/<name>/`.

---

### Method 4 — Local / development install

Use this method when iterating on a local clone of this repository before publishing.

```bash
git clone https://github.com/glapsfun/cnative-skills.git
cd cnative-skills
```

Then, inside Claude Code, substitute the actual path to your clone:

```
/plugin marketplace add /path/to/cnative-skills
/plugin install kubernetes-operator@cnative-skills
```

The path must point to the repo root (the directory containing `.claude-plugin/marketplace.json`). Using an absolute path avoids ambiguity. A relative path like `./cnative-skills` only works if your working directory is the parent of the clone.

For local Codex skill development, install from the clone with `npx skills`:

```bash
npx skills add . --skill kubernetes-operator --agent codex --global -y
```

Run the command from the repository root. Omit `--global` for a project-local install.

---

### Method 5 — Install a specific release (pinned version)

Methods 1–3 always install the **latest** published content (the default branch). To pin to a specific [release](https://github.com/glapsfun/cnative-skills/releases) — each one is a git tag such as `v0.1.0` — check out that tag and install from the local clone:

```bash
git clone --branch v0.1.0 --depth 1 https://github.com/glapsfun/cnative-skills.git
cd cnative-skills
```

Then install from that checkout. In Claude Code (use the absolute path to the clone):

```
/plugin marketplace add /path/to/cnative-skills
/plugin install kubernetes-operator@cnative-skills
```

For Codex, run from the repo root:

```bash
npx skills add . --skill kubernetes-operator --agent codex --global -y
```

To move to a different release later, fetch the new tag and re-checkout:

```bash
git fetch --tags
git checkout v0.2.0
```

then re-run the install/update steps below.

---

### Install all plugins at once with slash commands

After adding the marketplace with Method 1 or Method 4, install all plugins:

```
/plugin install kubernetes-operator@cnative-skills
/plugin install kagent@cnative-skills
/plugin install kgateway@cnative-skills
/plugin install fluxcd@cnative-skills
/plugin install argocd@cnative-skills
/plugin install bash-scripting@cnative-skills
/plugin install helm@cnative-skills
```

### Install all skills into Codex with `npx skills`

```bash
npx skills add glapsfun/cnative-skills \
  --skill kubernetes-operator \
  --skill kagent \
  --skill kgateway \
  --skill fluxcd \
  --skill argocd \
  --skill bash-scripting \
  --skill helm \
  --agent codex \
  --global \
  -y
```

Restart Codex after installing or updating skills.

---

## Updating skills

How you update depends on how you installed. In all cases, a plugin only changes on a user's machine when its `version` field (in `plugins/<name>/.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`) has been bumped in a newer release.

### Claude Code (Methods 1, 2)

Refresh the marketplace catalog, then the installed plugins pick up the new versions:

```
/plugin marketplace update cnative-skills
```

Non-interactively with the CLI:

```bash
claude plugin marketplace update cnative-skills
```

### Codex (Method 3)

Re-run the same `npx skills add` command — it overwrites the installed skill with the latest content — then restart Codex:

```bash
npx skills add glapsfun/cnative-skills --skill kubernetes-operator --agent codex --global -y
```

Check what's installed and their versions with:

```bash
npx skills list -a codex
```

### Pinned releases (Method 5)

A pinned clone stays on its tag until you move it. Fetch tags, check out the newer release, and re-run the local install:

```bash
git fetch --tags
git checkout v0.2.0
```

Then `/plugin marketplace update cnative-skills` (Claude Code) or re-run `npx skills add . ...` from the checkout (Codex).

See [docs/RELEASING.md](docs/RELEASING.md) for how releases and versions are produced.

---

## Repository layout

```
.claude-plugin/
  marketplace.json                  ← Claude Code marketplace catalog
.agents/plugins/
  marketplace.json                  ← Codex marketplace catalog
scripts/
  bootstrap.sh                      ← install developer tooling
  check.sh                          ← run the check suite (--all for everything)
  fmt.sh  lint.sh  validate.sh      ← format, lint, validate stages
  test.sh  install-test.sh  security.sh
  release-dryrun.sh                 ← preflight a release
  lib/common.sh                     ← shared script helpers
  checks/                           ← individual validators (structure, json, yaml, …)
.github/workflows/
  ci.yml                            ← GitHub Actions: fast + slow check jobs
  release.yml                       ← GitHub Actions: tag-driven release
plugins/
  kubernetes-operator/
    .claude-plugin/plugin.json      ← Claude Code plugin manifest
    .codex-plugin/plugin.json       ← Codex plugin manifest
    skills/kubernetes-operator/
      SKILL.md                      ← main skill content
      agents/                       ← agent definitions
      evals/                        ← evaluation scenarios
      references/                   ← reference docs
      scripts/                      ← utility scripts
  kagent/
    .claude-plugin/plugin.json
    .codex-plugin/plugin.json
    skills/kagent/
      SKILL.md
      agents/
      evals/
      references/
  kgateway/
    .claude-plugin/plugin.json
    .codex-plugin/plugin.json
    skills/kgateway/
      SKILL.md
      evals/
      references/
  fluxcd/
    .claude-plugin/plugin.json
    .codex-plugin/plugin.json
    skills/fluxcd/
      SKILL.md
      agents/
      evals/
      references/
      scripts/
  argocd/
    .claude-plugin/plugin.json
    .codex-plugin/plugin.json
    skills/argocd/
      SKILL.md
      agents/
      evals/
      references/
      scripts/
```

---

## Development

### Adding a new plugin

1. Create `plugins/<name>/` with the structure above.
2. Add `.claude-plugin/plugin.json` (Claude Code manifest) and `.codex-plugin/plugin.json` (Codex manifest).
3. Write the skill in `plugins/<name>/skills/<name>/SKILL.md`.
4. Register the plugin in both `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`.
5. Add an entry to the **Plugins** table in this README.

### Bumping a version

Increment `version` in both manifest files — users receive updates only when the version string changes:

- `plugins/<name>/.claude-plugin/plugin.json` — Claude Code
- `plugins/<name>/.codex-plugin/plugin.json` — Codex

### Local checks

All developer commands are shell scripts under `scripts/`, runnable from the repo root. They are exactly what CI runs, so passing them locally means the pipeline will pass too.

```bash
scripts/bootstrap.sh          # install tooling (Homebrew on macOS)
pre-commit install            # enable git hooks (fast checks on commit)

scripts/fmt.sh                # auto-format shell (shfmt) and JSON/YAML (prettier)
scripts/check.sh              # fast suite: fmt --check, lint, validate --fast
scripts/check.sh --all        # full suite: also markdown links, eval tests, install smoke, secret scan
```

Individual stages live under `scripts/` (`fmt.sh`, `lint.sh`, `validate.sh`, `test.sh`, `install-test.sh`, `security.sh`); the underlying validators are in `scripts/checks/`. All checks operate on **git-tracked files only** — stage files before validating.

### Cutting a release

Releases are repo-level semver tags. See [docs/RELEASING.md](docs/RELEASING.md). In short: `scripts/release-dryrun.sh vX.Y.Z` to preflight, then push the tag to publish a GitHub Release.

---

## CI

Two workflows enforce quality:

- **CI** (`.github/workflows/ci.yml`) runs on every push and pull request to `main`, split into a **fast** job (format check, lint, fast validation) and a **slow** job (markdown links, install smoke test, secret scan). Both must pass to merge.
- **Release** (`.github/workflows/release.yml`) runs on `v*` tags: it runs the full check suite, generates a changelog with git-cliff, and publishes a GitHub Release (`-rc.N` tags become prereleases).

---

## License

[MIT](LICENSE)
