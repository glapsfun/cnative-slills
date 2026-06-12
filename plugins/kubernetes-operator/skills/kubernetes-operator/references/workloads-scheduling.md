# Workloads, Pod Lifecycle & Scheduling

## Choosing a workload kind

- Stateless → **Deployment** (rolling updates, rollback, scaling).
- Stable identity + per-replica storage → **StatefulSet** (stable names `db-0`, `db-1`, ordered rollout, `volumeClaimTemplates`, requires a headless Service for per-pod DNS).
- One per node → **DaemonSet** (agents, CNI, log collectors).
- Run-to-completion → **Job** (`backoffLimit`, `completions`, `parallelism`, `ttlSecondsAfterFinished` for cleanup).
- Scheduled → **CronJob** (`schedule`, `concurrencyPolicy: Forbid|Replace|Allow`, `startingDeadlineSeconds`).
- ReplicaSet — never created directly; each Deployment rollout revision *is* a ReplicaSet (what `rollout undo` switches between, kept per `revisionHistoryLimit`).

## Deployment rollout mechanics

- `strategy.rollingUpdate`: `maxUnavailable` / `maxSurge` (absolute or %). `maxUnavailable: 0, maxSurge: 1` = strictly additive rollout.
- A rollout is "complete" when the new ReplicaSet's pods are Ready and `status.observedGeneration >= metadata.generation`. `kubectl rollout status` watches exactly this.
- `minReadySeconds` — pod must stay Ready this long before counting as available (catches crash-on-warmup).
- `progressDeadlineSeconds` (default 600) — rollout marked failed (condition `Progressing=False`) if no progress; it does NOT auto-rollback.
- Selectors are **immutable**; the pod-template-hash label links Deployment ↔ ReplicaSet ↔ Pods.

## Pod lifecycle

**Phases**: Pending → Running → Succeeded/Failed (terminal) / Unknown. `CrashLoopBackOff` is a container *waiting-state reason*, not a phase. Restart backoff: 10s→20s→40s→… capped 5 min, reset after 10 min healthy running.

**Conditions** (in order): `PodScheduled` → `Initialized` (init containers done) → `ContainersReady` → `Ready` (= ContainersReady + all readiness gates). `Ready=False` removes the pod from Service endpoints — by design.

**Container states**: Waiting (with reason: `ImagePullBackOff`, `CrashLoopBackOff`, `CreateContainerConfigError`), Running (`startedAt`), Terminated (exit code, reason like `OOMKilled`, `Error`, `Completed`).

**Init containers** run sequentially to completion before app containers. **Sidecars** = init containers with `restartPolicy: Always` — start before, terminate after the main container, restart independently.

### Probes

Three kinds, four mechanisms each (`exec`, `httpGet`, `tcpSocket`, `grpc`):

| Probe | On failure | Use for |
|---|---|---|
| **startup** | Container restarted; other probes gated until it succeeds | Slow boots — size `failureThreshold × periodSeconds` to worst-case startup |
| **liveness** | Container restarted | Deadlocks only. Never probe downstream dependencies — a dead DB would restart-storm every replica |
| **readiness** | Removed from endpoints (not restarted) | "Can I take traffic now" — warmup, temporary overload, dependency checks belong here |

Defaults to know: `periodSeconds: 10`, `timeoutSeconds: 1` (often too low!), `failureThreshold: 3`, `successThreshold: 1` (must be 1 for liveness/startup).

### Termination

delete → pod Terminating + removed from endpoints (async!) → `preStop` hook → SIGTERM to PID 1 → up to `terminationGracePeriodSeconds` (default 30) → SIGKILL.

- Endpoint removal and SIGTERM race: `preStop: exec: command: ["sleep","5"]` lets load balancers catch up — the standard zero-downtime trick.
- App must handle SIGTERM (shell-wrapped entrypoints often swallow it — use `exec` in scripts or `ENTRYPOINT ["binary"]` exec form).
- `kubectl delete pod --grace-period=0 --force` skips confirmation the process died — risk of split-brain for StatefulSets; last resort only.

### Resources & QoS

- `requests` = scheduling + QoS; `limits` = enforcement (memory over limit → OOMKill; CPU over limit → throttling, not death).
- CPU: millicores (`500m`); memory: binary suffixes (`256Mi`, `1Gi`).
- QoS (derived automatically): **Guaranteed** (requests == limits for every container) > **Burstable** > **BestEffort** (nothing set). Under node pressure, eviction order is BestEffort first, then Burstable exceeding requests. Always set requests on anything that matters.

## Scheduling toolbox (weakest → strongest)

- `nodeSelector` — exact label match, hard.
- **Node affinity** — `requiredDuringSchedulingIgnoredDuringExecution` (hard) / `preferred...` (soft, weighted); `matchExpressions` with `In/NotIn/Exists/Gt/Lt`.
- **Pod affinity / anti-affinity** — placement relative to other pods over a `topologyKey`. Anti-affinity on `kubernetes.io/hostname` = "don't co-locate my replicas". Expensive at large scale; prefer topology spread for spreading.
- **Topology spread constraints** — `maxSkew` over a `topologyKey` (zone/hostname) with `whenUnsatisfiable: DoNotSchedule|ScheduleAnyway`; the modern way to spread replicas.
- **Taints & tolerations** — nodes repel pods unless tolerated. Effects: `NoSchedule`, `PreferNoSchedule`, `NoExecute` (also evicts running pods; `tolerationSeconds` delays it). `kubectl taint nodes n1 dedicated=infra:NoSchedule`.
- **PriorityClass & preemption** — higher `value` preempts lower when capacity is tight; `preemptionPolicy: Never` opts out of preempting others.

The scheduler itself: **filter** (feasibility: resources, taints, affinity, volume topology) → **score** (rank survivors) → bind. `describe pod` events name the failed filter — that's your Pending diagnosis.

## Disruptions & eviction

- **PodDisruptionBudget** (`policy/v1`): `minAvailable` or `maxUnavailable` over a selector. Protects against *voluntary* disruptions (drain, eviction API). `kubectl drain` hangs rather than violate a PDB — working as intended.
- **Node-pressure eviction**: kubelet acts alone on `memory.available`, `nodefs.available`, PID pressure — *ignores PDBs*; order is QoS-based.
- **API-initiated eviction**: the `pods/eviction` subresource; what `drain` uses.

## Autoscaling

- **HPA** (`autoscaling/v2`): scales replicas on metrics (CPU/memory utilization vs *requests*, or custom/external metrics). Needs metrics-server. Don't combine with a fixed `replicas` in an applied manifest (apply will fight HPA — omit `replicas` from the manifest once HPA owns it).
- **VPA**: adjusts requests/limits (separate component).
- `kubectl autoscale deploy web --min=2 --max=10 --cpu-percent=70`.
