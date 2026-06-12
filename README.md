# cnative-skills

Agentic skills for cloud-native tools, distributed as a [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces).

## Installation

Add the marketplace and install a plugin from inside Claude Code:

```
/plugin marketplace add glapsfun/cnative-slills
/plugin install kubernetes-operator@cnative-skills
```

To pick up new versions later:

```
/plugin marketplace update cnative-skills
```

## Plugins

| Plugin | Description |
| :--- | :--- |
| `kubernetes-operator` | Expert Kubernetes assistant — kubectl commands and scripting, writing/reviewing manifests, Helm charts, GitOps (Flux, Argo CD, kustomize), security hardening, debugging playbooks (CrashLoopBackOff, Pending pods, ImagePullBackOff, OOMKilled, and more), and cluster operations. |

## Repository layout

```
.claude-plugin/marketplace.json     ← marketplace catalog
plugins/
  kubernetes-operator/
    .claude-plugin/plugin.json      ← plugin manifest
    skills/kubernetes-operator/     ← the skill (SKILL.md + references)
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
