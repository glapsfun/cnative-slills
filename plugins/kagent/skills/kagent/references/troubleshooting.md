# Troubleshooting kagent

## Contents

- Diagnostic commands
- Reading agent status conditions
- Agent not appearing in dashboard
- Agent stuck in not-ready state
- Agent not responding / timing out
- Failed to create MCP session (intermittent)
- MCP tools not available to agent
- Session stuck waiting (HITL approvals)
- Memory not working
- Context compaction not working
- SandboxAgent or AgentHarness not reconciling
- Dashboard not accessible
- CLI can't connect to controller
- MCP IDE integration not working
- Enabling debug logging
- Getting help

## Diagnostic Commands

```bash
# Cluster state
kubectl get agents.kagent.dev -n kagent          # all agents and their status
kubectl get mcpserver -n kagent                   # MCP server resources
kubectl get remotemcpserver -n kagent             # remote MCP server resources
kubectl get pods -n kagent                        # pod health
kubectl get events -n kagent --sort-by=.lastTimestamp

# Agent status details
kubectl get agent <name> -n kagent -o yaml        # full status including conditions

# Logs
kubectl logs -n kagent deployment/kagent-controller   # controller logs
kubectl logs -n kagent deployment/kagent-ui            # UI logs
kubectl logs -n kagent <agent-pod-name>                # specific agent logs

# Bug report (collects diagnostics)
kagent bug-report
```

## Reading Agent Status Conditions

The Agent status carries two conditions that split the problem space in half — always check them first:

- **`Accepted`** — the controller validated and translated the spec. `Accepted=False` means a *configuration* problem (bad modelConfig/tool reference, mutually exclusive fields, template error, validation failure); the condition `message` states the reason. The pod is irrelevant at this stage.
- **`Ready`** (called `DeploymentReady` in some versions) — the agent's pod is running and healthy. `Accepted=True` but not ready means a *runtime* problem: look at the Deployment/pod, not the YAML.

```bash
kubectl get agent <name> -n kagent -o jsonpath='{.status.conditions}' | jq
```

## Common Issues

### Agent not appearing in dashboard

**Symptoms:** Applied agent YAML but it doesn't show in the UI.

**Diagnosis:**
```bash
kubectl get agent <name> -n kagent -o yaml
```
Check `.status.conditions` — this is almost always `Accepted=False`.

**Common causes:**
- Missing or invalid `modelConfig` reference
- Invalid tool reference (MCPServer doesn't exist, or missing `apiGroup: kagent.dev`)
- Namespace mismatch between agent and referenced resources
- CRD version mismatch (using v1alpha1 fields in v1alpha2)
- Both `systemMessage` and `systemMessageFrom` set (mutually exclusive)
- `requireApproval` entry not present in `toolNames` (must be a subset)

### Agent stuck in not-ready state

**Diagnosis:**
```bash
kubectl get agent <name> -n kagent -o jsonpath='{.status.conditions}' | jq
kubectl describe pod -n kagent -l app.kubernetes.io/name=<name>,app.kubernetes.io/managed-by=kagent
```

**Common causes:**
- Image pull failures (check imagePullSecrets)
- Insufficient resources (CPU/memory limits too low)
- MCP server pod not ready
- LLM API key secret missing or incorrect

### Agent not responding / timing out

**Diagnosis:**
```bash
kubectl logs -n kagent <agent-pod-name>
kubectl logs -n kagent deployment/kagent-controller | grep <agent-name>
```

**Common causes:**
- LLM API rate limiting or key expiration
- MCP tool server crashed or unreachable
- Agent pod OOMKilled (increase memory limits)
- Network policy blocking outbound traffic to LLM provider

### Failed to create MCP session (intermittent)

**Symptoms:** Agent intermittently logs "Failed to create MCP session" — it works sometimes but not always.

**Diagnosis:**
```bash
kubectl get mcpserver <name> -n kagent -o yaml
kubectl get pods -n kagent -l app.kubernetes.io/name=<mcpserver-name>,app.kubernetes.io/managed-by=kagent
kubectl logs -n kagent <mcpserver-pod-name>
kubectl logs -n kagent <agent-pod-name>
```

Check agent pod logs for context around the error — connection refused, timeout, DNS failure, etc.

**Common causes:**

1. **Timeout too short (most common for intermittent failures):** The default MCP session creation timeout may be too short for servers that take time to initialize. Increase the `timeout` field on the MCPServer or RemoteMCPServer resource:
   ```yaml
   # RemoteMCPServer example
   spec:
     url: http://my-mcp-server:3000/sse
     timeout: 60s           # increase from default
     sseReadTimeout: 120s   # for long-running SSE connections
   ```

2. **MCP server pod instability:** Pod restarts, OOMKills, or readiness probe flapping. Check restart count with `kubectl get pods` and previous logs with `kubectl logs --previous`.

3. **Startup race condition:** Agent attempts to connect before the MCP server is fully ready. Ensure proper readiness probes on the MCP server pod.

4. **Namespace mismatch:** MCPServer must be in the same namespace as the Agent (or explicitly allowed via `allowedNamespaces`).

5. **Missing `apiGroup: kagent.dev`** in the agent's tool reference — required for both MCPServer and RemoteMCPServer kinds.

### MCP tools not available to agent

**Diagnosis:**
```bash
kubectl get remotemcpserver <name> -n kagent -o yaml   # check status.discoveredTools
kubectl get pods -n kagent -l app.kubernetes.io/name=<name>,app.kubernetes.io/managed-by=kagent
```

**Common causes:**
- `status.discoveredTools` empty — the controller couldn't connect or list tools; check URL, protocol, and auth headers
- Tool name mismatch in `toolNames` filter (compare against `discoveredTools` names exactly)
- RemoteMCPServer/MCPServer not in the agent's namespace
- MCP server binary not found (wrong `cmd` or `args`)

### Session stuck waiting (HITL approvals)

**Symptoms:** An agent appears hung mid-task; nothing in the logs looks wrong.

If any of the agent's tools have `requireApproval` (or it called the built-in `ask_user` tool), the A2A task is in `input-required` state, waiting for a human decision. Check the session in the dashboard — there will be a pending approval card. The task resumes as soon as someone approves/rejects. If the approval card never appeared in a *custom* client, see the HITL wire protocol in `hitl-and-memory.md` (the client must handle `input-required` DataParts and reply with the matching `taskId`).

### Memory not working

**Symptoms:** `memory.enabled: true` but the agent never recalls anything, or memory tools error.

**Checks:**
- Does the installed version support memory? `kubectl explain agent.spec.declarative.memory` — if unknown, upgrade.
- The embedding `modelConfig` referenced under `memory` must exist and be valid (it's a separate ModelConfig from the chat model).
- On Postgres, pgvector must be enabled: `database.postgres.vectorEnabled=true` (Helm). Bundled SQLite works out of the box.
- Memories have a default 15-day TTL and are pruned — old, rarely-used entries disappearing is by design.

### Context compaction not working

**Symptoms:** Long sessions still exceed model context limits, or older context disappears unexpectedly.

**Checks:**
- Does the installed version support compaction? `kubectl explain agent.spec.declarative.context.compaction`
- If compacted content must be preserved, configure `summarizer.modelConfig`; otherwise compacted events may be discarded.
- Confirm the compaction trigger is reachable: `compactionInterval` counts user invocations, while `tokenThreshold` triggers only after an invocation exceeds the threshold.
- Check the Agent `Accepted` condition for template/schema errors and controller logs for summarizer failures.

### SandboxAgent or AgentHarness not reconciling

**Checks:**
- Verify the CRDs exist: `kubectl api-resources | grep -i 'sandboxagent\|agentharness'`
- For SandboxAgent, inspect `kubectl explain sandboxagent.spec` and confirm sandbox runtime dependencies are installed.
- For AgentHarness, confirm OpenShell is deployed and the controller has `OPENSHELL_GATEWAY_URL` set.
- Check `Accepted` first. If accepted but not ready, inspect the generated workload and controller logs.

### Dashboard not accessible

```bash
# Check UI pod
kubectl get pods -n kagent -l app=kagent-ui

# Manual port-forward
kubectl port-forward -n kagent svc/kagent-ui 8082:8080

# Or use CLI
kagent dashboard
```

### CLI can't connect to controller

```bash
# Verify controller is running
kubectl get pods -n kagent -l app=kagent-controller

# Check service
kubectl get svc -n kagent kagent-controller

# Test connectivity
kubectl port-forward svc/kagent-controller 8083:8083 -n kagent
curl http://localhost:8083/healthz
curl http://localhost:8083/version
```

### MCP IDE integration not working

See `mcp-ide-setup.md` for detailed troubleshooting. Quick checks:
```bash
# Verify agents are eligible (must be Accepted + Ready)
kagent get agent

# Test controller MCP endpoint
curl http://localhost:8083/mcp -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.0.0"}}}'
```

## Enabling Debug Logging

### On an agent pod
```yaml
spec:
  declarative:
    deployment:
      env:
      - name: LOG_LEVEL
        value: debug
```

### On the controller
```bash
helm upgrade kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --reuse-values \
  --set controller.loglevel=debug
```

## Getting Help

- **Discord:** https://discord.gg/Fu3k65f2k3
- **GitHub Issues:** https://github.com/kagent-dev/kagent/issues
- **Bug report:** `kagent bug-report` (review for sensitive data before sharing)
