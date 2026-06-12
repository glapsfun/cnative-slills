# cnative-skills

Agentic skills for cloud-native tools, distributed as a [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces).

## Installation

### Claude Code

Add the marketplace and install a plugin:

```
/plugin marketplace add glapsfun/cnative-slills
/plugin install kubernetes-operator@cnative-skills
```

To pick up new versions later:

```
/plugin marketplace update cnative-skills
```

### Codex

Add this repository as a Codex plugin marketplace and install a plugin:

```
/plugin marketplace add glapsfun/cnative-slills
/plugin install kubernetes-operator@cnative-skills
```

Codex marketplace metadata lives in `.agents/plugins/marketplace.json`; plugin manifests live in `plugins/<name>/.codex-plugin/plugin.json`.

## Plugins

| Plugin | Description |
| :--- | :--- |
| `kubernetes-operator` | Expert Kubernetes assistant — kubectl commands and scripting, writing/reviewing manifests, Helm charts, GitOps (Flux, Argo CD, kustomize), security hardening, debugging playbooks (CrashLoopBackOff, Pending pods, ImagePullBackOff, OOMKilled, and more), and cluster operations. |
| `kagent` | Expert guide for [kagent](https://kagent.dev) — the CNCF framework for running AI agents on Kubernetes: CLI, Agent/ModelConfig/RemoteMCPServer CRDs, MCP tools, A2A subagents, human-in-the-loop approval, long-term memory, IDE integration, Helm/OIDC/observability, and troubleshooting. Derived from and extending the upstream [kagent skill](https://github.com/kagent-dev/kagent/tree/main/.claude/skills/kagent) (Apache-2.0). |
| `kgateway` | Expert guide for [kgateway](https://kgateway.dev) — the CNCF Kubernetes Gateway API implementation powered by Envoy (formerly Gloo by Solo.io): installation, Gateway/HTTPRoute/TCPRoute setup, traffic management (splitting, delegation, transformations), security (TLS/mTLS, JWT, ext-auth, rate limiting, CORS, IP ACL), resiliency (retries, timeouts, circuit breakers, fault injection), Istio integration, observability, debugging, and upgrade procedures including v2.3 migration. |
| `fluxcd` | Expert guide for [Flux CD](https://fluxcd.io/flux/) — Kubernetes GitOps install/bootstrap, repository structure, Flux source/Kustomization/Helm/notification resources, SOPS and RBAC security, schema validation, operations, upgrades, and troubleshooting. |

Install any plugin the same way: `/plugin install <name>@cnative-skills`.

## Repository layout

```
.claude-plugin/
  marketplace.json                  ← marketplace catalog
.agents/plugins/
  marketplace.json                  ← Codex marketplace catalog
plugins/
  kubernetes-operator/
    .claude-plugin/plugin.json      ← plugin manifest
    .codex-plugin/plugin.json       ← Codex plugin manifest
    skills/kubernetes-operator/     ← the skill (SKILL.md + references + evals)
  kagent/
    .claude-plugin/plugin.json
    .codex-plugin/plugin.json
    skills/kagent/
  kgateway/
    .claude-plugin/plugin.json
    .codex-plugin/plugin.json
    skills/kgateway/
  fluxcd/
    .claude-plugin/plugin.json
    .codex-plugin/plugin.json
    skills/fluxcd/
```

## Development

Test changes locally before pushing:

```
/plugin marketplace add ./path/to/this/repo
/plugin install kubernetes-operator@cnative-skills
```

When releasing a change, bump `version` in the plugin's `plugin.json` — users only receive updates when the version string changes.

## License

[MIT](LICENSE)
