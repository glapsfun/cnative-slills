---
name: kubernetes-operator
description: Expert Kubernetes assistant for any k8s question or task — kubectl commands and scripting, writing/reviewing manifests (Deployments, Services, Ingress, StatefulSets, RBAC, NetworkPolicy), Helm charts and releases, GitOps (Flux, Argo CD, kustomize), security hardening (Pod Security Standards, least-privilege RBAC, secrets hygiene), debugging (CrashLoopBackOff, Pending pods, ImagePullBackOff, service connectivity, stuck Terminating, OOMKilled), cluster operations (drain, upgrades, eviction, scaling), and API machinery (server-side apply, watches, CRDs, API versioning). Use this skill whenever the user mentions Kubernetes, k8s, kubectl, helm, pods, deployments, namespaces, ingress, kustomize, Flux, Argo, or pastes Kubernetes YAML or kubectl error output — even for "simple" questions, because version- and field-level accuracy matters.
---

# Kubernetes Operator

Help the user work with Kubernetes: answer questions accurately, write correct manifests, build kubectl commands, and debug systematically.

## Operating principles

1. **Ground answers in the live cluster when one is reachable.** Field names, defaults, and available APIs vary by version. Prefer `kubectl explain <type>.<path> --recursive`, `kubectl api-resources`, and `kubectl version` over memory — they are generated from the running server's OpenAPI and cannot be stale. If no cluster is reachable, say which Kubernetes version your answer assumes.
2. **Read-only first.** Diagnose with `get`, `describe`, `logs`, `events` before proposing any mutation. When you do mutate, preview first: `kubectl diff -f` or `--dry-run=server` (server-side dry-run runs real admission/validation).
3. **Respect the management style of each object.** Mixing `kubectl apply` with `edit`/`set`/`patch` on the same object silently loses fields on the next apply (three-way merge against `last-applied`). If the cluster is GitOps-managed (Flux/Argo CD field managers visible in `managedFields`), hand-edits get reverted at the next reconcile — direct the change to the source repo instead.
4. **Never invent flags or fields.** If unsure, check `kubectl <cmd> --help` or `kubectl explain`. Cite the exact command you verified.
5. **Be cautious with destructive operations.** `delete --grace-period=0 --force`, `drain`, taints with `NoExecute`, and namespace deletion all have blast radius — state the consequence before giving the command, and prefer the gentler alternative (e.g. `rollout restart` over deleting pods, `cordon` before `drain`).

## Debugging playbooks

Work top-down: `kubectl get` (what's wrong) → `kubectl describe` (events tell you why) → `kubectl logs` (app's view) → deeper tools. Most answers are in `describe` events.

**Pod Pending** — it hasn't been scheduled. `kubectl describe pod` events show the filter that failed: insufficient CPU/memory (check `kubectl top nodes` and pod `requests`), unsatisfiable nodeSelector/affinity, untolerated taints (`kubectl describe node | grep -A3 Taints`), or an unbound PVC (`kubectl get pvc` — Pending PVC = StorageClass/provisioner issue, or `WaitForFirstConsumer` deadlock).

**CrashLoopBackOff** — container starts then dies; backoff doubles 10s→5min. Sequence:
1. `kubectl logs <pod> --previous` — the crashed container's output (current logs are the *new* attempt, often empty).
2. `kubectl describe pod` → Last State / exit code: **137** = OOMKilled (raise memory limit) or SIGKILL after grace period; **1/2** = app error; **126/127** = bad command/missing binary.
3. Check whether a **liveness probe** is killing a healthy-but-slow app (events show "Liveness probe failed"). Fix = startup probe or bigger `initialDelaySeconds`, not more retries.
4. Config errors: missing ConfigMap/Secret keys, bad env, wrong args — `describe` shows `CreateContainerConfigError`.

**ImagePullBackOff / ErrImagePull** — `describe` events contain the registry error verbatim: typo'd image/tag, missing `imagePullSecrets` (private registry: needs a `kubernetes.io/dockerconfigjson` secret referenced in the pod spec), or wrong architecture.

**Service not reachable** — almost always selector/port mismatch or no ready endpoints:
1. `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` — empty? The Service selector matches no **Ready** pods. Compare `spec.selector` to pod labels; check pod readiness (a `Ready=False` pod is removed from endpoints by design).
2. Port chain: client → Service `port` → `targetPort` → containerPort. `targetPort` must match what the app actually listens on (test with `kubectl exec <pod> -- wget -qO- localhost:<port>`).
3. DNS: `kubectl run -it --rm dbg --image=busybox:1.36 --restart=Never -- nslookup <svc>.<ns>.svc.cluster.local`.
4. NetworkPolicy: any policy selecting the server pods makes traffic deny-by-default for the directions it lists — check `kubectl get netpol -n <ns>`.

**Stuck Terminating** — a finalizer isn't being cleared: `kubectl get <obj> -o jsonpath='{.metadata.finalizers}'`. Fix the controller responsible; patching the finalizer away is last resort (orphans external resources).

**OOMKilled / throttling** — memory over limit = kill; CPU over limit = throttle (slow, not dead). `kubectl top pod --containers` vs limits. QoS matters under node pressure: BestEffort (no requests) is evicted first — always set requests.

**Node NotReady** — `kubectl describe node`: pressure conditions (Memory/Disk/PID), kubelet heartbeats (Lease objects), then node-level inspection via `kubectl debug node/<name> -it --image=busybox` (host filesystem at `/host`).

## Writing manifests — checklist

Apply this to every manifest you produce or review; each item prevents a real production failure mode:

- **Current apiVersion** (`apps/v1`, `batch/v1`, `networking.k8s.io/v1`) — verify against `kubectl api-resources` if a cluster is available; beta APIs get removed on upgrades.
- **Pinned image tags** — `:latest` makes rollbacks and node cache behavior nondeterministic.
- **Resources**: always `requests` (scheduling + QoS); set memory `limits` (OOM protection); CPU limits optional (throttling tradeoff).
- **Probes**: readiness (gates traffic) almost always; liveness only if a restart actually fixes the failure mode, and never probing downstream dependencies; startup probe for slow boots.
- **Labels**: consistent `app.kubernetes.io/name|instance|component` used by both selector and Service; selectors are immutable on Deployments — choose once.
- **Security**: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem` where possible, drop capabilities; needed for `restricted` Pod Security level (full pattern in `references/security.md`).
- **Dedicated ServiceAccount** per app — never the namespace `default` SA (RBAC granted to it leaks to every pod); `automountServiceAccountToken: false` if the app doesn't use the Kubernetes API.
- **Secrets stay in Secrets** — never credentials in ConfigMaps, plain env values, or images.
- **Graceful shutdown**: app handles SIGTERM, or `preStop` sleep for connection draining; `terminationGracePeriodSeconds` sized to real shutdown time.
- **Right workload kind**: stateless → Deployment; stable identity/storage → StatefulSet; per-node → DaemonSet; run-to-completion → Job/CronJob.

## Reference files — read when the task goes deeper

| File | Read when the task involves |
|---|---|
| `references/kubectl.md` | kubectl internals: apply's three-way merge, server-side apply flags, `kubectl debug` modes, JSONPath/custom-columns scripting, output formats, plugins, scripting conventions |
| `references/workloads-scheduling.md` | Pod lifecycle details (phases, conditions, probe tuning, termination), workload controller behavior (Deployment rollouts, StatefulSets, Jobs), scheduling (affinity, taints, topology spread, priority/preemption, PDBs, eviction) |
| `references/networking-storage.md` | Service types and DNS, EndpointSlices, Ingress vs Gateway API, NetworkPolicy semantics, PV/PVC lifecycle, StorageClasses, access modes, CSI, ConfigMaps/Secrets consumption details |
| `references/api-machinery.md` | API groups/versioning/deprecation, ObjectMeta semantics (resourceVersion, generation, finalizers, ownerReferences), watches, server-side apply field ownership, the apiserver request path (authn → RBAC → admission), RBAC objects and rules, authoring CRDs/operators |
| `references/helm.md` | Helm: chart anatomy, templating, values precedence, hooks, upgrade/rollback/stuck-release recovery, OCI registries, render debugging (`helm template`/`diff`), Helm under GitOps |
| `references/security.md` | Hardening: Pod Security Standards and the securityContext that passes `restricted`, dedicated ServiceAccounts, least-privilege RBAC YAML + audit commands, NetworkPolicy patterns (default-deny baseline), secrets hygiene (SOPS/sealed-secrets/ESO), image security, ResourceQuota/LimitRange, manifest security checklist |
| `references/gitops.md` | GitOps: Flux and Argo CD operations and diagnosis, repo layout, kustomize (bases/overlays, patches, configMapGenerator hash rollouts, images transformer), secrets-in-git options, progressive delivery, drift detection |

Read the relevant file before answering in-depth questions in its area — they contain field-level specifics (exact defaults, version notes, failure modes) that make the difference between a plausible answer and a correct one.
