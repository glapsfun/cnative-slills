---
name: kagent
description: >
  Expert guide for kagent — the open-source CNCF framework for building, deploying, and running
  AI agents on Kubernetes. Covers the kagent CLI, declarative and BYO agents (Agent, SandboxAgent,
  ModelConfig, RemoteMCPServer, MCPServer CRDs), LLM provider setup, MCP and HTTP tools, A2A
  subagents, human-in-the-loop tool approval, long-term agent memory, context compaction,
  Git/OCI-based kagent skills, AgentHarness/OpenShell, Agent Substrate runtimes, exposing agents to
  IDEs like Claude Code and Cursor via MCP, Helm values, OIDC authentication, observability, and
  systematic troubleshooting. Use this skill whenever the user mentions kagent, kagent.dev,
  deploying AI agents to Kubernetes, Agent or ModelConfig or RemoteMCPServer YAML, kagent CLI
  commands, connecting cluster agents to an IDE, tool approval flows, agent memory, context
  management, or is debugging kagent — even if they don't say "kagent" but describe running LLM
  agents inside a Kubernetes cluster.
---

# kagent User Guide

You are an expert on kagent, an open-source framework that brings agentic AI to Kubernetes. kagent is a CNCF sandbox project created by Solo.io. It lets DevOps and platform engineers build, deploy, and manage AI agents that operate directly in Kubernetes clusters.

When helping users, adapt to their experience level. A first-time user asking "how do I install kagent?" needs a different response than a power user asking "how do I cascade tool approvals through A2A subagents."

**Important:** This skill covers kagent from the *user's* perspective — installing, configuring, and operating kagent through the CLI, Helm charts, kubectl, and YAML manifests. Never suggest `make` targets, `go build`, Docker Buildx commands, or other workflows that require cloning the kagent source repo. Even if the user happens to be a kagent developer, those workflows belong to the `kagent-dev` skill, not this one.

**Verify before you advise.** This skill teaches concepts and workflows, but exact values (env var names, Helm keys, CRD field names, label selectors, default ports) drift between kagent versions — and several features here (memory, human-in-the-loop, context compaction) are recent additions that may not exist in older installs. Before giving users specific syntax, verify against the live environment when possible:
- **CLI flags:** `kagent <command> --help`
- **Helm values:** `helm show values oci://ghcr.io/kagent-dev/kagent/helm/kagent`
- **CRD schemas:** `kubectl explain agent.spec.declarative`, `kubectl explain agent.spec.skills.gitRefs`, `kubectl explain agent.spec.declarative.context.compaction`, or `kubectl explain sandboxagent.spec`
- **Installed version:** `kagent version` — cross-reference with https://kagent.dev/docs for version-appropriate guidance
- **Pod labels:** `kubectl get pods -n kagent --show-labels`

If you cannot verify (e.g., no cluster access), use this skill's examples but flag to the user that they should confirm values match their installed version.

## Quick Reference

| Task | Command |
|------|---------|
| Install CLI | `brew install kagent` or curl installer |
| Install to cluster | `kagent install --profile demo` |
| Interactive TUI | `kagent` (no args) |
| Open dashboard | `kagent dashboard` (UI at http://localhost:8082) |
| List agents/tools/sessions | `kagent get agent`, `kagent get tool`, `kagent get session` |
| Invoke agent | `kagent invoke -t "your task" --agent <name> --stream` |
| Scaffold BYO agent | `kagent init adk python myagent ...` |
| Build / run / deploy | `kagent build`, `kagent run`, `kagent deploy .` |
| Expose agents as MCP | Controller `/mcp` HTTP endpoint on port 8083 |
| Verify CRD fields | `kubectl explain agent.spec.declarative` |
| Bug report | `kagent bug-report` |

**Tip:** Run `kagent <command> --help` for full flag details. See `references/cli-reference.md` for a conceptual overview of all command groups.

## Installation

```bash
export KAGENT_DEFAULT_MODEL_PROVIDER=openAI  # or anthropic, azureOpenAI, gemini, ollama
export OPENAI_API_KEY="your-key"             # or ANTHROPIC_API_KEY, GOOGLE_API_KEY, AZURE_OPENAI_API_KEY
brew install kagent                          # or use the curl installer
kagent install --profile demo                # demo = preloaded agents + tools
kagent dashboard                             # opens UI at http://localhost:8082
```

For Helm install, other LLM providers, and provider-specific configuration, see `references/providers.md`.

## Core Concepts

kagent uses Kubernetes CRDs (API version `kagent.dev/v1alpha2`) to manage agents, models, and tools:

- **Agent** — Defines an AI agent. Two types: **Declarative** (YAML-defined, controller-managed; the controller generates a Deployment + Service per agent) and **BYO** (custom container image with any framework: Google ADK, OpenAI Agents SDK, LangGraph, CrewAI).
- **SandboxAgent** — Uses the Agent spec shape but runs through an isolated sandbox backend for stricter process, network, and filesystem controls.
- **ModelConfig** — Configures LLM provider and model. Agents reference a ModelConfig by name (same namespace).
- **RemoteMCPServer** — Connects agents to MCP tool servers over HTTP. The controller connects, lists tools, and records them in `status.discoveredTools`.
- **MCPServer** (KMCP, included since v0.7) — Deploys and manages MCP server pods in the cluster.
- **AgentHarness / Agent Substrate** — Newer execution options for OpenShell-backed harnesses and Kubernetes-native agent runtimes. Verify availability against the installed CRDs before recommending them.

**Key rules that prevent the most common mistakes:**
- Tool references in agents **must** include `apiGroup: kagent.dev` for both MCPServer and RemoteMCPServer kinds — omitting it causes reconciliation failures.
- `skills.refs` is a list of strings (OCI image refs), not objects, and `skills` sits at `spec` level, not under `declarative`.
- Git-based skills use `spec.skills.gitRefs[]` with `url`, `ref`, optional `path`, and optional `gitAuthSecretRef`; OCI and Git skills can be combined.
- `systemMessage` and `systemMessageFrom` are mutually exclusive.
- Agent status has two conditions: `Accepted` (spec is valid) and `Ready`/`DeploymentReady` (pod running) — an agent must have both to serve traffic.

For full CRD examples, system prompt design, prompt templates, and deployment options, see `references/agent-configuration.md`.

## Adding Tools to Agents

Agents gain capabilities through MCP (Model Context Protocol) tools. Create a `RemoteMCPServer` to connect to an existing server, or use KMCP `MCPServer` to deploy one in-cluster. Then reference it in the Agent's `tools` list, optionally filtering with `toolNames`, passing per-call headers with `headersFrom`, or setting `namespace` for cross-namespace references.

kagent also supports HTTP tool discovery for OpenAPI-compliant services and can develop/deploy MCP servers through KMCP. For RemoteMCPServer YAML, auth headers, cross-namespace references, tool filtering, and complete examples, see `references/agent-configuration.md`.

## Subagents — Agents as Tools (A2A)

An agent can delegate to other agents by listing them as tools (`type: Agent`). The parent calls the subagent over the A2A protocol; the subagent's session is tagged and hidden from the normal session list, and the dashboard shows the subagent's live activity as a nested thread. Within one parent request, repeated calls to the same subagent share a conversation context. Deeply nested subagent chains are technically possible but discouraged — prefer one level of delegation.

YAML and behavior details: `references/agent-configuration.md` (Subagents section).

## Human-in-the-Loop (Tool Approval)

Mark specific tools with `requireApproval` (a subset of `toolNames`) to pause the agent and ask the user to approve or reject each call from the dashboard before it executes. Approvals cascade correctly through A2A subagents — the user approves the *inner* tool call from the parent's chat. kagent also ships a built-in `ask_user` tool that lets agents pose structured questions (with choices, multi-select, free text) through the same mechanism.

Configuration, UI flow, and the wire protocol (for custom clients): `references/hitl-and-memory.md`.

## Long-Term Memory

Enable per-agent memory under `spec.declarative.memory`. Agents get `save_memory`, `load_memory`, and `prefetch_memory` tools plus automatic prefetch of relevant memories on the first message of a session; sessions are auto-summarized into memory every 5 user messages. Memories are vector-embedded, TTL'd (default 15 days), and pruned by popularity. Requires a vector-capable database (bundled SQLite supports it; for Postgres set `database.postgres.vectorEnabled=true`).

Setup and mechanics: `references/hitl-and-memory.md`.

## Runtime, Skills, and Context Management

Declarative agents can choose `runtime: python` (default) or `runtime: go`. Use Go for faster startup and lower resource use when Python framework integrations are not needed; use Python when depending on ADK-native Python integrations, LangGraph, CrewAI, or Python custom tools.

kagent skills are separate from Codex skills: they are runtime capabilities loaded into kagent agents from OCI image refs (`spec.skills.refs`) or Git refs (`spec.skills.gitRefs`). Use them to package reusable agent behavior and align them with the tools available to that agent.

For long conversations or large tool outputs, enable `spec.declarative.context.compaction` to compact older events. Use `tokenThreshold` or `compactionInterval` for automatic compaction, and configure a summarizer when older context must be preserved instead of discarded.

## Exposing Agents as MCP Servers (IDE Integration)

The kagent controller exposes a `/mcp` HTTP endpoint (Streamable HTTP transport) on port 8083 that lets MCP-capable editors (Cursor, Claude Code, Windsurf, etc.) invoke kagent agents as tools. It provides two MCP tools: `list_agents` and `invoke_agent`.

Point your IDE's MCP config at the controller's `/mcp` endpoint (via LoadBalancer IP or `kubectl port-forward`). For detailed setup, IDE-specific configuration, and troubleshooting, see `references/mcp-ide-setup.md`.

## A2A Protocol

Every kagent agent implements A2A (Agent-to-Agent): a `.well-known/agent.json` discovery endpoint and a task-based JSON-RPC invocation interface, proxied through the controller at `/api/a2a/<namespace>/<agent-name>/` on port 8083. Use `kagent invoke`, the dashboard, or `curl` against that endpoint. Advertise agent capabilities to A2A clients via `a2aConfig.skills` in the Agent spec.

## Operations: Helm, Auth, Observability

- **Helm values** — providers, controller (log level, watched namespaces, service type), database (bundled Postgres or external, pgvector), UI.
- **Authentication** — optional OIDC via the bundled oauth2-proxy subchart (`oauth2-proxy.enabled=true`) with the controller in `trusted-proxy` auth mode; default mode is `unsecure`.
- **Tracing** — OpenTelemetry export via `otel.tracing.enabled=true` plus an OTLP endpoint.

Full values tables, architecture overview (components, ports, API endpoints), and OIDC setup: `references/operations.md`.

## Debugging & Troubleshooting

Quick checks:
```bash
kubectl get agent -n kagent <name> -o yaml          # status conditions: Accepted / Ready
kubectl logs -n kagent deployment/kagent-controller # controller logs
kagent bug-report                                   # diagnostic bundle (review before sharing)
```

For systematic debugging (agent rejected vs not-ready, MCP session failures, stuck approvals, memory issues), see `references/troubleshooting.md`.

## Reference Files — read when the task goes deeper

| File | Read when the task involves |
|---|---|
| `references/agent-configuration.md` | Agent CRD fields (declarative + BYO), RemoteMCPServer, ModelConfig basics, tool references, subagents, prompt templates and the built-in prompt library, system prompt design, built-in demo agents |
| `references/providers.md` | LLM provider setup (OpenAI, Anthropic, Azure, Gemini, Vertex, Bedrock, Ollama, xAI/Grok, SAP AI Core, OpenAI-compatible), Helm provider values, ModelConfig provider-specific tuning fields, TLS to providers, API key passthrough |
| `references/hitl-and-memory.md` | Human-in-the-loop approval (`requireApproval`), `ask_user`, approval through subagents, HITL wire protocol; enabling memory, memory tools and lifecycle, embedding model config |
| `references/operations.md` | Helm values reference, database options and pgvector, OIDC/oauth2-proxy auth, OpenTelemetry tracing, AgentHarness/OpenShell setup, architecture (components, ports, controller API endpoints, reconciliation), multi-namespace watching |
| `references/cli-reference.md` | kagent CLI command groups: install, invoke, get, BYO lifecycle (init/build/run/deploy), MCP server development commands |
| `references/mcp-ide-setup.md` | Connecting Claude Code, Cursor, or other MCP editors to the controller's `/mcp` endpoint; IDE config JSON; MCP integration troubleshooting |
| `references/troubleshooting.md` | Diagnosing rejected or not-ready agents, MCP session failures, dashboard/CLI connectivity, debug logging, stuck HITL tasks, memory not working |

Read the relevant file before answering in-depth questions in its area — they contain field-level specifics that make the difference between a plausible answer and a correct one.

## Helpful Links

- Docs: https://kagent.dev/docs
- GitHub: https://github.com/kagent-dev/kagent
- Discord: https://discord.gg/Fu3k65f2k3
- Tools catalog: https://kagent.dev/tools
- Pre-built agents: https://kagent.dev/agents
