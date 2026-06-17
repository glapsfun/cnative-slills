# Operations: Helm, Auth, Observability, Architecture

## Contents

- Architecture overview (components, ports, endpoints)
- How reconciliation works (what to expect from the controller)
- Helm chart and key values
- Database configuration
- Authentication (OIDC via oauth2-proxy)
- Observability (OpenTelemetry tracing)
- AgentHarness / OpenShell support
- Multi-namespace watching

> Helm keys below reflect recent kagent versions and may drift. Verify with
> `helm show values oci://ghcr.io/kagent-dev/kagent/helm/kagent` before applying.

---

## Architecture Overview

Understanding the moving parts makes every debugging session faster:

| Component | What it does | Port |
|---|---|---|
| **kagent-controller** | Reconciles CRDs into Deployments/ConfigMaps; serves the HTTP API, A2A proxy, and `/mcp` endpoint; persists agents/sessions/tasks to the database | 8083 |
| **kagent-ui** | Next.js dashboard (chat, agent management, approvals, memories) | service 8080, `kagent dashboard` opens http://localhost:8082 |
| **Agent pods** | One Deployment + Service per Declarative agent (or your BYO image), speaking A2A | 8080 |
| **Database** | SQLite (bundled default) or PostgreSQL — sessions, tasks, events, tools, memories | — |
| **KMCP controller** | Manages MCPServer pods (bundled since v0.7) | — |

**Controller API endpoints worth knowing** (all on 8083):

| Endpoint | Purpose |
|---|---|
| `/healthz`, `/version` | Liveness and version checks (`curl` these when diagnosing connectivity) |
| `/api/a2a/{namespace}/{name}` | A2A JSON-RPC endpoint, proxied to the agent pod |
| `/mcp` | Streamable HTTP MCP endpoint exposing `list_agents` / `invoke_agent` (IDE integration) |
| `/api/agents`, `/api/sessions`, `/api/tasks`, `/api/tools`, `/api/modelconfigs` | CRUD/listing used by UI and CLI |
| `/api/memories`, `/api/memories/search` | Memory listing, clearing, and vector search |

## How Reconciliation Works

When you apply an Agent CR, the controller: validates the spec (→ `Accepted` condition), translates it into a Deployment + ConfigMap + Service, applies those to the cluster, stores the agent config in the database, and updates status (→ `Ready` when the pod is healthy). Consequences you can rely on:

- **Status conditions are the first diagnostic stop.** `Accepted=False` means the spec was rejected (bad reference, validation failure) — the message says why. `Accepted=True` but not Ready means a runtime problem (image pull, secret, resources) — look at the pod.
- **Referenced ConfigMaps trigger re-reconciliation** (e.g., prompt template sources) — editing a prompt ConfigMap rolls the agent automatically.
- **Update events only reconcile on generation/label changes** — status-only updates don't churn.
- For a `RemoteMCPServer`, the controller connects to the server over the network, lists its tools, and writes them to `status.discoveredTools` — an empty/missing list means the connection or listing failed.

## Helm Chart and Key Values

Charts are OCI-based:

```bash
helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds --namespace kagent --create-namespace
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent --namespace kagent \
  --set providers.default=anthropic \
  --set providers.anthropic.apiKey=$ANTHROPIC_API_KEY
```

Key values:

| Value | Default | Purpose |
|---|---|---|
| `providers.default` | `openAI` | Default LLM provider (see `providers.md`) |
| `providers.<name>.apiKey` / `.model` | — | Provider credentials and default model |
| `controller.loglevel` | `info` | Set `debug` when troubleshooting |
| `controller.replicas` | 1 | Controller replicas |
| `controller.watchNamespaces` | `[]` (all) | Restrict which namespaces are reconciled |
| `controller.a2aBaseUrl` | — | Externally advertised A2A base URL |
| `controller.service.type` | `ClusterIP` | Set `LoadBalancer` to expose 8083 without port-forward (IDE/MCP use) |
| `controller.auth.mode` | `unsecure` | `unsecure` or `trusted-proxy` (OIDC, below) |
| `database.postgres.bundled.enabled` | varies | Run a bundled Postgres |
| `database.postgres.url` | — | External Postgres connection string (overrides bundled) |
| `database.postgres.vectorEnabled` | `false` | Enable pgvector (required for memory on Postgres) |
| `otel.tracing.enabled` | `false` | OpenTelemetry tracing |
| `otel.tracing.exporter.otlp.endpoint` / `.protocol` | — / `grpc` | OTLP collector target |
| `oauth2-proxy.enabled` | `false` | Deploy the bundled oauth2-proxy subchart |
| `controller.openshell.enabled` | `false` | Enable OpenShell-backed AgentHarness support when available |
| `querydoc.enabled` | `true` | Documentation-query tool service |

Upgrade pattern (preserve existing values):

```bash
helm upgrade kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent --reuse-values \
  --set controller.loglevel=debug
```

## Database Configuration

- **Default**: bundled SQLite — fine for trying things out; supports memory vectors natively.
- **Production**: PostgreSQL — either the bundled instance (`database.postgres.bundled.enabled=true`) or external (`database.postgres.url=postgresql://...`).
- **Memory feature on Postgres** requires pgvector: `database.postgres.vectorEnabled=true`.

The database stores agents' translated configs, sessions, tasks, events, discovered tools, feedback, and memories. It is rebuildable state for CRD-derived data, but sessions/memories live only there — back it up if chat history matters.

## Authentication (OIDC via oauth2-proxy)

By default kagent is **unauthenticated** (`controller.auth.mode=unsecure`) — fine for local clusters, not for shared ones. For enterprise SSO, kagent uses a **trust-the-proxy** model:

1. **oauth2-proxy** (optional Helm subchart: `oauth2-proxy.enabled=true`) sits in front of the UI/API, runs the OIDC flow against your IdP (Okta, Cognito, Azure AD, ...), manages session cookies, and injects `Authorization: Bearer <JWT>` into upstream requests.
2. The **controller** runs in `trusted-proxy` mode (`controller.auth.mode=trusted-proxy`, or `AUTH_MODE` env var) and extracts user identity from the JWT **without re-validating the signature** — it trusts the proxy did that.
3. The user-ID claim defaults to `sub`; override with `AUTH_USER_ID_CLAIM` (`--auth-user-id-claim`). All raw JWT claims are passed through (`/api/me` returns the full payload), so any IdP's claim names work without mapping config.
4. In-cluster agents authenticate to the controller via a service-account fallback (agent name + user id headers), so internal traffic doesn't need JWTs.

**Critical caveat:** because the backend trusts the proxy, anything that can reach the controller/UI *directly* (bypassing oauth2-proxy) is unauthenticated. Restrict direct access with NetworkPolicies so traffic must flow through the proxy.

## Observability (OpenTelemetry Tracing)

```bash
helm upgrade kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent --reuse-values \
  --set otel.tracing.enabled=true \
  --set otel.tracing.exporter.otlp.endpoint=http://jaeger-collector.observability:4317 \
  --set otel.tracing.exporter.otlp.protocol=grpc
```

Traces cover agent invocations and tool calls — useful for diagnosing slow responses (LLM latency vs tool latency) and seeing full multi-agent call trees. The dashboard itself shows per-session chat history and tool invocations without any extra setup.

## AgentHarness / OpenShell Support

AgentHarness resources need an OpenShell gateway that the kagent controller can reach. Before recommending this path, verify both the kagent CRDs and the OpenShell deployment are installed. Typical controller settings include:

```yaml
controller:
  openshell:
    enabled: true
  env:
  - name: OPENSHELL_GATEWAY_URL
    value: dns:///openshell.openshell.svc:8080
  - name: OPENSHELL_INSECURE
    value: "true"
```

Use authenticated and TLS-protected OpenShell settings for shared or production clusters. Demo examples often disable TLS/auth; call that out explicitly when adapting them.

## Multi-Namespace Watching

By default the controller watches **all** namespaces. To scope it:

```bash
--set controller.watchNamespaces="{team-a,team-b}"
```

Cross-namespace references (e.g., an Agent using a RemoteMCPServer in another namespace) are governed by the referenced resource's `allowedNamespaces` field (Gateway API-style: `from: All` or `from: Selector` with a label selector). If a cross-namespace tool reference is rejected, check `allowedNamespaces` on the target resource.
