# Security Hardening

## Pod Security Standards (PSS) & Pod Security Admission

Three levels, enforced per-namespace by the built-in admission controller via labels:

- **privileged** — unrestricted (system/infra namespaces only).
- **baseline** — blocks known privilege escalations (hostNetwork/hostPID/hostPath, privileged containers, added capabilities beyond a safe set).
- **restricted** — hardened: runAsNonRoot, allowPrivilegeEscalation: false, drop ALL capabilities, seccompProfile RuntimeDefault, only safe volume types.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: prod
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted     # also: audit
    # version pin optional: pod-security.kubernetes.io/enforce-version: v1.32
```

Rollout strategy: set `warn`/`audit` first, fix the warnings, then flip `enforce`. Enforcement rejects *pods*, not Deployments — a non-compliant Deployment silently fails to create pods (check ReplicaSet events).

## The securityContext that passes `restricted`

```yaml
spec:
  securityContext:                  # pod level
    runAsNonRoot: true
    runAsUser: 1000                 # only if image doesn't define a non-root user
    fsGroup: 2000                   # group ownership of mounted volumes
    seccompProfile: {type: RuntimeDefault}
  containers:
  - name: app
    securityContext:                # container level
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true  # add emptyDir mounts for tmp/cache paths the app writes
      capabilities: {drop: ["ALL"]}
```

Why each: non-root + no-escalation contains container escapes; read-only rootfs blocks payload drops; dropped capabilities shrink kernel attack surface; RuntimeDefault seccomp filters syscalls. Ports <1024 need `NET_BIND_SERVICE` added back — or just listen on 8080.

## ServiceAccounts

- **Never run app pods as the `default` ServiceAccount** — RBAC granted to it leaks to every pod in the namespace. One SA per app: `serviceAccountName: my-app`.
- If the app never talks to the Kubernetes API (most don't): `automountServiceAccountToken: false` (on the SA or pod) — no token to steal.
- SA identity for RBAC/audit: `system:serviceaccount:<ns>:<name>`.

## Least-privilege RBAC pattern

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: {name: my-app, namespace: prod}
automountServiceAccountToken: false      # flip to true only if the app uses the API
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: my-app, namespace: prod}
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch"]        # exactly what it needs, nothing more
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: my-app, namespace: prod}
subjects: [{kind: ServiceAccount, name: my-app, namespace: prod}]
roleRef: {kind: Role, name: my-app, apiGroup: rbac.authorization.k8s.io}
```

Auditing:
```bash
kubectl auth can-i --list --as=system:serviceaccount:prod:my-app -n prod   # full permission dump
kubectl auth can-i get secrets --as=system:serviceaccount:prod:my-app -n prod
```
Red flags in an audit: wildcards (`*` in verbs/resources/apiGroups), cluster-admin bindings to SAs, `get secrets` cluster-wide, `escalate`/`bind`/`impersonate` verbs, write access to `pods/exec`.

## NetworkPolicy patterns

Baseline for every namespace that holds workloads (policies are additive allow-only; the deny *is* an empty policy selecting the pods):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-all, namespace: prod}
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-dns, namespace: prod}
spec:
  podSelector: {}
  policyTypes: ["Egress"]
  egress:
  - to: [{namespaceSelector: {kubernetes.io/metadata.name: kube-system}}]
    ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-frontend-to-app, namespace: prod}
spec:
  podSelector: {matchLabels: {app: my-app}}
  policyTypes: ["Ingress"]
  ingress:
  - from: [{podSelector: {matchLabels: {app: frontend}}}]
    ports: [{protocol: TCP, port: 8080}]
```

Gotchas: `from: [{namespaceSelector: X}, {podSelector: Y}]` is OR; nesting both in ONE element is AND. **Verify the CNI enforces NetworkPolicy** (flannel doesn't; Calico/Cilium do) — an unenforced policy is silent false security. Remember ingress-controller and monitoring traffic when writing allows.

## Secrets hygiene

- Never put credentials in ConfigMaps, plain env values in manifests, or container images. Use Secrets and mount or `envFrom: secretRef`.
- Base64 ≠ encryption. Layered protection: etcd encryption-at-rest, RBAC that narrows `get secrets` (it's effectively cluster-read if granted broadly), audit logging.
- Secrets in git require encryption or indirection: **SOPS+age** (encrypt values in-file; GitOps controller decrypts in-cluster), **sealed-secrets** (cluster keypair, controller decrypts), **External Secrets Operator** (sync from Vault/cloud secret managers — secrets never in git at all).
- Private registries: `kubernetes.io/dockerconfigjson` Secret + `imagePullSecrets` on the pod/SA.
- Prefer projected ServiceAccount tokens & workload identity over long-lived static credentials where the platform supports it.

## Image security

- Pin tags (`:v1.4.2`); pin by digest (`@sha256:...`) for supply-chain-sensitive workloads.
- Minimal base images (distroless/alpine/scratch) — fewer CVEs, no shell for attackers (use `kubectl debug` ephemeral containers instead).
- Build images to run as a non-root USER so `runAsNonRoot` passes without forcing a UID.
- `imagePullPolicy: IfNotPresent` with pinned immutable tags; never `Always` + `:latest` in prod.

## Multi-tenancy guards: ResourceQuota & LimitRange

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: {name: quota, namespace: team-a}
spec:
  hard: {requests.cpu: "10", requests.memory: 20Gi, limits.memory: 40Gi, pods: "50"}
---
apiVersion: v1
kind: LimitRange
metadata: {name: defaults, namespace: team-a}
spec:
  limits:
  - type: Container
    defaultRequest: {cpu: 100m, memory: 128Mi}   # injected when a pod omits requests
    default: {cpu: 500m, memory: 512Mi}           # injected limits
```

Note: once a ResourceQuota covers cpu/memory, pods **without** requests/limits are rejected — LimitRange defaults prevent that breakage.

## Security review checklist for a manifest

1. Dedicated SA, token automount off if unused. 2. restricted-compliant securityContext. 3. Pinned image, minimal base. 4. Requests + memory limits (DoS containment). 5. Secrets via Secret objects, not ConfigMap/env literals. 6. NetworkPolicy covering the pod (and CNI enforces it). 7. RBAC rules minimal — no wildcards. 8. No hostPath/hostNetwork/hostPID/privileged without strong justification.
