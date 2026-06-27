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

## Repository layout

```
.claude-plugin/
  marketplace.json                  ← Claude Code marketplace catalog
.agents/plugins/
  marketplace.json                  ← Codex marketplace catalog
.ci/
  validate-structure.sh             ← plugin structure contract
  validate-marketplace-sync.sh      ← catalog vs directory consistency
  validate-json.sh                  ← JSON validity
  validate-markdown-internal-links.sh
  validate-shell-syntax.sh
.github/workflows/
  ci.yml                            ← GitHub Actions (runs all .ci/ scripts)
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

### Running CI checks locally

```bash
bash .ci/validate-structure.sh
bash .ci/validate-marketplace-sync.sh
bash .ci/validate-json.sh
bash .ci/validate-markdown-internal-links.sh
bash .ci/validate-shell-syntax.sh
```

---

## CI

GitHub Actions runs on every push and pull request to `main` and enforces:

- Plugin structure contract (`plugins/<name>/.claude-plugin/plugin.json`, `skills/<name>/SKILL.md`, and optional subdirectories)
- Marketplace and plugin consistency (catalog entries vs tracked plugin directories and manifests)
- JSON validity
- Internal Markdown link/reference integrity
- Shell script syntax (`bash -n`)

---

## License

[MIT](LICENSE)
