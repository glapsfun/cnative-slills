# kubectl Reference

## Core syntax

```
kubectl [command] [TYPE] [NAME] [flags]
```

- Types are case-insensitive and accept singular/plural/short forms (`pod`/`pods`/`po`); names are case-sensitive.
- Mix forms freely: `kubectl get pod/p1 deployment/d1`; repeat `-f` for multiple files; `-f` accepts URLs and `-` (stdin).
- Precedence: CLI flags > env vars > kubeconfig defaults. `-n <ns>` overrides everything; `-A` = all namespaces.
- In-cluster, kubectl auto-detects via `KUBERNETES_SERVICE_HOST`/`PORT` + the ServiceAccount token.
- `kubectl <anything> -v=6` shows request URLs; `-v=8` shows full request/response bodies — the best way to learn the REST API and debug RBAC denials.

## Context & namespace

```bash
kubectl config get-contexts
kubectl config use-context <ctx>
kubectl config set-context --current --namespace=<ns>
kubectl --kubeconfig ~/.kube/other-config get nodes   # per-call kubeconfig
```

## How `kubectl apply` works (client-side three-way merge)

Apply stores your file verbatim in the `kubectl.kubernetes.io/last-applied-configuration` annotation, then computes a patch from **three** inputs — your file, the live object, and last-applied:

- Field in file → set/updated.
- Field in **last-applied but missing from your file** → **deleted** from the live object (this is how apply knows you removed something).
- Field only in the live object (server defaults, other controllers' fields) → left alone.

Merge per field type: primitives replace; maps (labels/annotations) merge key-by-key; lists depend on the field's patch strategy — `containers` merges items by the `name` key (updating an image preserves ports you didn't mention), un-keyed lists replace wholesale.

**The trap**: mixing apply with imperative commands loses data. `kubectl set env` adds a var; the next `apply` deletes it (it's in neither your file nor last-applied). One management style per object.

## Server-side apply (SSA)

```bash
kubectl apply --server-side -f manifest.yaml          # apiserver merges via managedFields
kubectl apply --server-side --force-conflicts -f ...  # seize field ownership
kubectl apply --field-manager=my-tool -f ...          # name your actor
kubectl get <obj> -o yaml --show-managed-fields       # who owns which fields
```

SSA tracks per-field ownership in `metadata.managedFields`. Applying a field another manager owns is **rejected** (409 conflict) unless forced. GitOps controllers (Flux kustomize-controller, Argo CD) are field managers — your hand-edit takes ownership, then the controller force-applies it back at the next reconcile. See `api-machinery.md` for full SSA semantics.

## Patching

```bash
# Strategic merge patch (default; respects merge keys like container name)
kubectl patch deploy web -p '{"spec":{"template":{"spec":{"containers":[{"name":"app","image":"app:v2"}]}}}}'
# JSON patch (positional, exact)
kubectl patch deploy web --type=json -p='[{"op":"replace","path":"/spec/replicas","value":3}]'
# Subresources
kubectl patch deploy web --subresource=scale -p '{"spec":{"replicas":5}}'
```

## `kubectl debug` — three modes

1. **Ephemeral container** (default): `kubectl debug mypod -it --image=busybox --target=app` — injects a temporary container into the *running* pod, no restart. `--target` shares the target container's process namespace. The only way to shell into distroless/scratch images.
2. **Pod copy**: `kubectl debug mypod -it --copy-to=dbg --image=ubuntu` (+ `--set-image=*=busybox`, `--share-processes`, `--same-node`) — clone for invasive poking; original keeps serving.
3. **Node debug**: `kubectl debug node/<name> -it --image=busybox` — privileged pod in host namespaces, node filesystem mounted at `/host`. Substitute for SSH for many node tasks.

Security context via `--profile`: `general` (default), `baseline`, `restricted`, `netadmin` (network tooling), `sysadmin`.

## Output formats & scripting

In scripts use only machine-stable formats: `-o name|json|yaml|jsonpath|go-template|custom-columns`. Fully qualify types to survive version changes: `jobs.v1.batch/myjob`.

### JSONPath

Operators: `.field` / `['field']`, `..` recursive descent, `*` wildcard, slices `[0:3]` (negative indices ok), unions `['a','b']`, filters `?(@.field=="x")`, iteration `{range .items[*]}...{end}`. Escape dots in label keys: `kubernetes\.io/hostname`. **No regex** — pipe to `jq` for that.

```bash
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
kubectl get pods -o custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount
kubectl get pods --field-selector=status.phase=Running
kubectl get pods --sort-by='.status.containerStatuses[0].restartCount'
kubectl get pods -l app=web,tier!=cache          # label selectors
```

### Waiting & watching

```bash
kubectl wait --for=condition=Ready pod/mypod --timeout=120s
kubectl wait --for=condition=Available deploy/web --timeout=300s
kubectl wait --for=delete pod/mypod --timeout=60s
kubectl get pods -w
```

## Rollouts

```bash
kubectl rollout status deploy/web          # blocks until done or deadline
kubectl rollout history deploy/web         # revisions (each = a ReplicaSet)
kubectl rollout undo deploy/web [--to-revision=2]
kubectl rollout restart deploy/web         # rolling restart (e.g. to pick up ConfigMap changes)
```

## Node operations

```bash
kubectl cordon <node>                      # unschedulable, existing pods stay
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data   # evict (respects PDBs)
kubectl uncordon <node>
kubectl taint nodes <node> key=value:NoSchedule     # (NoExecute also evicts)
```

`drain` uses the Eviction API and **respects PodDisruptionBudgets** — it will hang if a PDB would be violated; that's the PDB doing its job.

## Discovery & self-documentation

```bash
kubectl api-resources [--api-group=apps] [--namespaced=true]
kubectl api-versions
kubectl explain deploy.spec.strategy --recursive    # field docs from YOUR server's OpenAPI — never stale
kubectl cluster-info; kubectl version
```

Prefer `kubectl explain` over any web reference: it is generated from the connected server's schema, so it always matches the cluster version.

## Logs, exec, files, events

```bash
kubectl logs <pod> [-c <container>] [-f] [--previous] [--timestamps] [--since=1h] [--tail=100]
kubectl logs deploy/web                    # picks a pod for you
kubectl logs -l app=web --prefix          # all matching pods
kubectl exec -it <pod> [-c c] -- sh       # note the -- separator
kubectl cp <ns>/<pod>:/path/file ./file
kubectl port-forward svc/web 8080:80
kubectl events --types=Warning [--for=pod/mypod]
kubectl top node; kubectl top pod --containers     # needs metrics-server
```

## Misc that saves time

- `kubectl diff -f manifest.yaml` — what apply would change, before applying.
- `--dry-run=client` (local render) vs `--dry-run=server` (full admission + validation, nothing persisted).
- `kubectl create deploy web --image=nginx --dry-run=client -o yaml` — manifest scaffolding.
- `kubectl auth can-i create deployments --as=system:serviceaccount:<ns>:<sa> -n <ns>` — RBAC checks.
- Plugins: any `kubectl-foo` executable on PATH becomes `kubectl foo`; manage via **krew** (`ctx`, `ns`, `tree`, `neat` are the high-value ones). `kubectl plugin list` to inspect.
- kuberc (`~/.kube/kuberc`, beta ≥1.34): user preferences separate from kubeconfig — command aliases with default flags, per-command option defaults (e.g. interactive delete).
