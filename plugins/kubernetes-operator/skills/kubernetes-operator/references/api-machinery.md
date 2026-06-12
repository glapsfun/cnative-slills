# API Machinery, RBAC & Object Model

## API structure

- Core group at `/api/v1` (`apiVersion: v1`); named groups at `/apis/GROUP/VERSION` (`apiVersion: apps/v1`).
- Identity of an object = group + resource + namespace + name. Verbs: get, list, watch, create, update, patch, delete, deletecollection — the same vocabulary RBAC uses.
- **Versioning**: alpha (off by default, may vanish) → beta (off by default since 1.22; ≥9 months/3 releases before deprecation, same again before removal) → stable (`v1`, never removed within a major version). Before cluster upgrades, scan manifests for to-be-removed versions (`kubectl api-resources`, release deprecation guide).
- Discovery from the live server: `kubectl api-versions`, `kubectl api-resources`, `kubectl explain <type> --recursive`, `/openapi/v3`.

## ObjectMeta semantics

- `name` (immutable, unique per namespace) / `generateName` (server appends random suffix — how ReplicaSets name pods) / `uid` (unique across time; ownerReferences match on uid, so a recreated parent does not adopt old children).
- `resourceVersion` — opaque etcd revision; powers optimistic locking (replace fails with 409 Conflict if the object changed under you) and watch resumption. Only echo it back; never fabricate.
- `generation` — bumps on every *spec* change; controllers report `status.observedGeneration` — `rollout status` and GitOps health checks compare the two to know status is current.
- `labels` (queryable; drive every selector) vs `annotations` (non-queryable freight for tools).
- `ownerReferences` — garbage collection: object deleted when all owners are gone; deletion cascades `--cascade=background` (default) / `foreground` / `orphan`.
- `finalizers` — deletion blockers. `deletionTimestamp` set ≠ deleted; object stays until every finalizer is removed by its controller. Stuck Terminating = the responsible controller is broken/gone. Patching finalizers away is last resort (orphans external resources).
- `managedFields` — server-side apply ownership ledger (see below).

## spec/status contract

`spec` = your intent (writable); `status` = system observation, writable only via the `/status` subresource (hence separate RBAC like `deployments/status`). Uniform verbs across all resources + per-type subresources: `/scale`, `/log`, `/exec`, `/eviction`, `/status`.

## Watches

`GET ...?watch=true&resourceVersion=N` streams changes after N; bookmark events keep watches resumable; a stale version returns **410 Gone** → client relists. This list-then-watch loop is how every controller (and GitOps operator) stays in sync. Large lists paginate via `limit` + `continue`. `dryRun=All` runs full admission + validation without persisting (kubectl `--dry-run=server`).

## Server-Side Apply (SSA)

The apiserver merges and tracks **per-field ownership** in `managedFields`: entry = `manager` (e.g. `kubectl`, `kustomize-controller`, `helm-controller`) + `operation` (`Apply`/`Update`) + `fieldsV1` tree of owned fields.

- **Conflicts**: applying a field another manager owns → 409 rejected (unlike PUT, which steamrolls). Resolutions: **force** (`--force-conflicts` — sole ownership, others lose the field), **abandon** (drop field from your manifest — value stays, you stop managing it), **share** (set your value equal to theirs).
- **Merge semantics from schema markers**: `x-kubernetes-list-type: map` + `list-map-keys` (merge list items by key — containers, ports), `set`, `atomic` (replace whole value). CRDs without markers default lists to atomic — a common surprise.
- **Removal**: a field disappears only when no manager claims it anymore.
- **GitOps**: controllers force-apply as their field manager each reconcile, so hand-edits to managed fields are reverted by design — route changes through the source repo.

## The request path through the apiserver

1. **TLS** (typically :6443) — verified via the cluster CA.
2. **Authentication** — x509 client certs, bearer tokens, **ServiceAccount JWTs** (how in-cluster controllers authenticate), OIDC, webhook. No User objects exist; identity = username + groups. Failure → 401.
3. **Authorization** — RBAC (standard), Node, ABAC, webhook; any allow wins. Failure → 403.
4. **Admission** — mutating first (defaulting, sidecar injection, LimitRanger), then validating (quota, Pod Security admission, ValidatingAdmissionPolicy/CEL, webhooks). Skipped for reads.
5. **Schema validation + etcd write**, then audit logging.

Debugging access problems: 401 = who you are; 403 = what you may do (`kubectl auth can-i ... --as=...`); webhook failures show up as create/update errors naming the webhook.

## RBAC

- **Role** (namespaced) / **ClusterRole** (cluster-wide; also reusable per-namespace via RoleBinding — define once, grant per namespace).
- **RoleBinding** / **ClusterRoleBinding** bind a single `roleRef` (immutable — delete and recreate to change) to subjects: `User`, `Group`, `ServiceAccount`.
- Rules: `{apiGroups, resources, verbs, resourceNames?, nonResourceURLs?}`; `""` = core group; subresources as `pods/log`, `deployments/status`.
- **Aggregated ClusterRoles**: `aggregationRule` assembles rules from label-selected roles (how the built-in `view` learns about CRDs shipping `rbac.authorization.k8s.io/aggregate-to-view: "true"`).
- Built-ins: `cluster-admin`, `admin` (ns-admin), `edit`, `view`.
- Escalation prevention: you can't grant permissions you don't hold, without `escalate`/`bind` verbs.

```bash
kubectl auth can-i create deployments --as=system:serviceaccount:<ns>:<sa> -n <ns>
kubectl create role pod-reader --verb=get,list,watch --resource=pods -n <ns>
kubectl create rolebinding x --role=pod-reader --serviceaccount=<ns>:<sa> -n <ns>
kubectl auth reconcile -f rbac.yaml      # smarter than apply for RBAC
```

ServiceAccount usernames: `system:serviceaccount:<namespace>:<name>`; group `system:serviceaccounts[:<namespace>]`.

## Extension mechanisms (ladder)

CRDs (new resource types with full API machinery for free) → custom controllers watching them (CRD + controller = **Operator pattern**) → aggregated API servers (metrics-server) → admission webhooks (mutating/validating; each is an availability liability on the request path — prefer ValidatingAdmissionPolicy/CEL for policy) → node-level plugins: CNI, CSI, device plugins.

### Authoring CRDs — essentials

- `spec.versions[]`: each with `schema.openAPIV3Schema` (structural schema required), `served` + exactly one `storage: true`; multi-version needs a conversion strategy (None or webhook).
- Enable `subresources: {status: {}, scale: {...}}` — status subresource splits RBAC and stops spec writers clobbering status; scale enables `kubectl scale` and HPA.
- `additionalPrinterColumns` make `kubectl get` output useful; validation via schema constraints plus `x-kubernetes-validations` (CEL) for cross-field invariants; defaults via `default:` in the schema.
- List merge behavior under SSA comes from `x-kubernetes-list-type` / `list-map-keys` markers — set them or lists default to atomic.
- Controllers: scaffold with kubebuilder/controller-runtime (or operator-sdk). Reconcile must be **idempotent** (level-based, not edge-based), set `status.observedGeneration`, use owner references for GC, and use finalizers for external-resource cleanup.

## Object management styles

Three mutually exclusive styles — never mix on one object: imperative commands (`kubectl create deploy ...`; dev only), imperative config (`create/replace -f`), declarative (`diff -f` + `apply -f`, or GitOps where a controller applies). The declarative + git + controller combination is the production default.
