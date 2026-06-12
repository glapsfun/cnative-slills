# Networking, Storage & Configuration

## Network model

Every pod gets a cluster-unique IP; all pods reach all pods without NAT (unless NetworkPolicy says otherwise). Services provide stable virtual identities in front of churning pods. Containers in one pod share a network namespace — they talk over `localhost` and can't reuse each other's ports.

## Service types

- **ClusterIP** (default) — internal virtual IP; kube-proxy (or the CNI) load-balances to ready endpoints.
- **NodePort** — opens a port (30000–32767) on every node; mostly dev/test or as LB plumbing.
- **LoadBalancer** — cloud controller provisions an external LB; external IP appears in `.status.loadBalancer.ingress`. On bare metal needs MetalLB/kube-vip or a built-in LB (k3s ServiceLB).
- **ExternalName** — DNS CNAME to an external host; no proxying, no endpoints.
- **Headless** (`clusterIP: None`) — no VIP; DNS returns pod IPs directly, plus per-pod records `<pod>.<svc>.<ns>.svc.cluster.local`. Required by StatefulSets.

Port chain: client → Service `port` → `targetPort` (name or number; must match what the container actually listens on) → containerPort. `nodePort` is the third, optional hop.

## DNS

- Services: `<svc>.<ns>.svc.cluster.local`; pod search paths make `my-svc` resolve in-namespace and `my-svc.other-ns` across namespaces.
- Provided by CoreDNS (Deployment + `kube-dns` Service in kube-system). DNS debugging: `kubectl run -it --rm dbg --image=busybox:1.36 --restart=Never -- nslookup <svc>`; check CoreDNS logs/pods if cluster-wide.

## EndpointSlices

`discovery.k8s.io/v1`, label `kubernetes.io/service-name=<svc>`; ≤100 endpoints per slice, each with `ready`/`serving`/`terminating` conditions + node name. This is what proxies and gateways watch. **Empty slices = your Service selects no Ready pods** — the #1 cause of "service not reachable".

## Ingress vs Gateway API

- **Ingress** (`networking.k8s.io/v1`): frozen API — HTTP(S) only, host + path routing, everything else via controller-specific annotations. Needs an ingress controller and usually an `ingressClassName`. TLS via `spec.tls[].secretName` (a `kubernetes.io/tls` secret; cert-manager automates issuance).
- **Gateway API** (`gateway.networking.k8s.io`): the successor — role-separated `GatewayClass` (implementation) / `Gateway` (listeners, TLS) / `HTTPRoute` (+ TCPRoute/TLSRoute/GRPCRoute), typed matching (headers, query, method), traffic weighting/splitting. Routes attach via `parentRefs`; cross-namespace via ReferenceGrant. Prefer it for new designs when an implementation is installed.

## NetworkPolicy

- Additive **allow-only**; there are no deny rules. As soon as any policy selects a pod, that pod becomes deny-by-default for the directions (`policyTypes`) the policy declares; an empty `ingress: []` *is* a full deny.
- Selectors: `podSelector`, `namespaceSelector` (combine both in one `from` element for "these pods in those namespaces" — separate elements mean OR), `ipBlock`.
- Standard baseline per namespace: one default-deny-all (Ingress+Egress) + explicit allows + DNS egress (UDP/TCP 53 to kube-system).
- **Enforcement depends on the CNI** — flannel (stock k3s) does not enforce NetworkPolicy; Calico/Cilium do. A policy on a non-enforcing CNI silently does nothing.

## Storage

### Volumes vs PV/PVC

- Pod-scoped volumes die with the pod: `emptyDir` (scratch, also `medium: Memory`), `configMap`, `secret`, `downwardAPI`, `projected`, ephemeral CSI volumes. `hostPath` ties to a node and is a security risk — avoid in general workloads.
- **PV/PVC**: PVC = namespaced request, PV = cluster resource, bound 1:1.

### Lifecycle

provisioning (**static** = admin pre-creates PVs; **dynamic** = StorageClass `provisioner` creates on demand) → binding → use → reclaim:
- `Retain` — PV stays (status Released, not reusable until manually cleared); data survives.
- `Delete` — backing storage destroyed with the PVC. Check this before deleting PVCs!

### StorageClass knobs

- `provisioner` (CSI driver), `parameters` (driver-specific), `reclaimPolicy`, `allowVolumeExpansion: true` (then grow by editing PVC `spec.resources.requests.storage`), `volumeBindingMode: WaitForFirstConsumer` (bind at scheduling time so the volume lands where the pod can use it — essential for local/zonal storage).
- Default class via annotation `storageclass.kubernetes.io/is-default-class: "true"` — a PVC without `storageClassName` uses it.

### Access modes

`ReadWriteOnce` (one **node** — multiple pods on that node OK), `ReadWriteOncePod` (one pod), `ReadOnlyMany`, `ReadWriteMany` (needs a shared filesystem: NFS, CephFS, etc. — most block storage can't).

### Pending PVC diagnosis

`kubectl describe pvc` events: no StorageClass / no default class, provisioner not installed, `WaitForFirstConsumer` waiting for a pod, or (static) no matching PV (size/mode/class).

## ConfigMaps & Secrets

- Consumption: env (`valueFrom.configMapKeyRef` / `envFrom`) or volume mount. **Volume-mounted ConfigMaps/Secrets update live** (~kubelet sync period, and NOT when mounted via `subPath`); **env vars never update** without pod restart — `kubectl rollout restart` after changing config consumed as env.
- `immutable: true` — prevents edits, reduces apiserver watch load; change = create a new name and roll (kustomize's configMapGenerator hash-suffix pattern automates this).
- Secret types: `Opaque`, `kubernetes.io/tls` (cert+key), `kubernetes.io/dockerconfigjson` (for `imagePullSecrets`), `basic-auth`, `ssh-auth`, SA tokens.
- Base64 is encoding, not encryption. Real protections: etcd encryption-at-rest, RBAC narrowing `get secrets`, external secret managers / sealed or SOPS-encrypted secrets for anything stored in git.
- `stringData` (write plain text, server encodes) vs `data` (base64) when authoring.
