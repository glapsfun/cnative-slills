# Human-in-the-Loop & Long-Term Memory

## Contents

- Human-in-the-loop (HITL) tool approval
  - Enabling approval on tools
  - What the user experiences
  - The built-in `ask_user` tool
  - HITL with A2A subagents
  - Wire protocol (for custom clients and debugging)
- Long-term memory
  - Enabling memory on an agent
  - How memory works (tools, auto-save, prefetch)
  - Memory lifecycle (TTL, popularity, pruning)
  - Database requirements
  - Costs and caveats

---

## Human-in-the-Loop (HITL) Tool Approval

kagent can pause an agent before it executes specific tools and ask the user to approve or reject the call. This is built on A2A task states (`input_required`) plus ADK's `request_confirmation()` mechanism — when approved, the *exact same* tool call is replayed without an extra LLM round-trip.

### Enabling approval on tools

Add `requireApproval` to a tool reference. Entries **must be a subset of `toolNames`** (CEL-validated — listing a tool only in `requireApproval` is rejected):

```yaml
spec:
  declarative:
    tools:
    - type: McpServer
      mcpServer:
        name: k8s-tools
        kind: MCPServer
        apiGroup: kagent.dev
        toolNames:
          - k8s_get_resources
          - k8s_delete_resource
        requireApproval:          # pause before these execute
          - k8s_delete_resource
```

Read tools normally don't need approval; reserve `requireApproval` for destructive or sensitive operations (deletes, scaling, writes to external systems) — every approval interrupts the user's flow.

### What the user experiences

1. Agent decides to call an approval-gated tool.
2. Execution pauses; the dashboard shows a tool card with the tool name and arguments, plus **Approve** / **Reject** buttons.
3. On approve, the tool runs and the agent continues with its result. On reject, the agent is told the call was rejected (optionally with a free-text rejection reason) and responds accordingly.
4. Multiple parallel tool calls can be decided individually (mixed approve/reject in one batch).

While a task is waiting for a decision, its A2A state is `input-required` — relevant when debugging "stuck" sessions (see `troubleshooting.md`).

### The built-in `ask_user` tool

Every agent automatically has an `ask_user` tool (no configuration needed). It lets the agent pose one or more structured questions in a single call — each with optional predefined choices, single- or multi-select, and free-text answers always allowed:

```python
ask_user(questions=[
  {"question": "Which database should I use?", "choices": ["PostgreSQL", "MySQL", "SQLite"], "multiple": False},
  {"question": "Which features do you want?",  "choices": ["Auth", "Logging", "Caching"],   "multiple": True},
  {"question": "Any additional requirements?", "choices": [], "multiple": False}
])
```

The dashboard renders these as forms; answers return to the model positionally, one entry per question. Encourage users to mention `ask_user` in system prompts when they want agents to clarify intent before acting.

### HITL with A2A subagents

When a parent agent delegates to a subagent (tool `type: Agent`) and the *subagent's* tools require approval, the request cascades up: the subagent pauses, the parent's chat shows the **inner** tool's name and arguments (not a generic "call subagent" card), and the user's decision cascades back down. Batch decisions are keyed by the inner tool call IDs. This works recursively, but nesting subagents beyond one level is discouraged.

### Wire protocol (for custom clients and debugging)

If the user is building their own UI/client or debugging raw A2A traffic:

**Request path (server → client):** a `TaskStatusUpdateEvent` with `state: "input-required"` whose status message contains a DataPart. A DataPart is an approval request when all three hold:
- `metadata.kagent_type` (or `adk_type`) is `"function_call"`
- `metadata.kagent_is_long_running` (or `adk_is_long_running`) is `true`
- `data.name` is `"adk_request_confirmation"`

The tool name/args/ID to display are in `data.args.originalFunctionCall`. For subagent HITL, `data.args.toolConfirmation.payload.hitl_parts[]` carries the inner tool calls — display those instead.

**Decision path (client → server):** a normal A2A user `Message` that **must** include the pending task's `taskId`, containing a DataPart:

```json
{ "decision_type": "approve" }                          // or "reject"
{ "decision_type": "batch",
  "decisions": { "<tool_call_id>": "approve", "<tool_call_id_2>": "reject" },
  "rejection_reasons": { "<tool_call_id_2>": "Too dangerous" } }
{ "decision_type": "approve",
  "ask_user_answers": [ { "answer": ["PostgreSQL"] }, { "answer": ["Auth", "Caching"] } ] }
```

Tool call IDs come from `originalFunctionCall.id` (inner IDs from `hitl_parts` for subagents). `ask_user_answers` is positional, matching the original `questions` array.

---

## Long-Term Memory

Memory lets agents remember and learn across sessions: facts are embedded into vectors and retrieved by semantic similarity. This is a recent feature — verify it exists in the user's version with `kubectl explain agent.spec.declarative.memory`.

### Enabling memory on an agent

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
spec:
  type: Declarative
  declarative:
    modelConfig: chat-model
    memory:
      enabled: true
      modelConfig: embedding-model   # separate ModelConfig used for embeddings
      # ttlDays: 15                  # memory retention (default 15)
```

The embedding ModelConfig can use a different provider than the chat model. Embeddings are 768-dimensional; outputs from other models are truncated/normalized.

### How memory works

When enabled, the agent's instruction is automatically extended and it gains:

- **`save_memory`** — the agent explicitly saves a fact verbatim (no summarization).
- **`load_memory`** — semantic search over stored memories; results filtered by a minimum similarity score.
- **`prefetch_memory`** — explicit access to the same prefetch behavior exposed as a tool.
- **Prefetch** — on the *first* user message of a session only, relevant memories are automatically retrieved and injected into that turn (the prompt is split into sentences for better matching). Prefetch does not run on every turn — that would be too expensive.
- **Auto-save** — every 5 user messages, the session is summarized by the LLM in the background and the summary is embedded and stored.

### Memory lifecycle

- Every memory gets `expires_at` = creation + TTL (default **15 days**).
- Each successful retrieval increments the memory's access count.
- A daily pruning job checks expired memories: popular ones (access count ≥ 10) get their TTL extended and counter reset; unpopular ones are deleted.
- Users can view and clear an agent's memories from the dashboard. The controller also exposes `/api/memories` (GET to list, DELETE to clear, POST `/api/memories/search` for similarity search).

### Database requirements

Memory needs a vector-capable database:

- **Bundled SQLite** — supported natively (libSQL vector type), works out of the box for development.
- **Postgres** — requires pgvector; set `database.postgres.vectorEnabled=true` in Helm values (see `operations.md`).

### Costs and caveats

- Memory tools consume token budget, and auto-save adds background LLM calls (cost + latency).
- There is no consolidation/dedup step — repeatedly saving the same facts creates near-duplicate entries that can crowd retrieval results.
- Retrieval is dense-vector only (no keyword/BM25 hybrid), so exact-match lookups like error codes or IDs may retrieve poorly.
