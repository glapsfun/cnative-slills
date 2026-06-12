# GitOps & Kustomize

## The model

Git is the source of truth; a controller in the cluster continuously reconciles live state toward what's in the repo (the same watch-and-converge loop as every Kubernetes controller, pointed at git). Consequences:

- **Changes go through git** — commit, push, let the controller apply. Hand-edits (`kubectl edit/apply`) to controller-managed objects are reverted at the next reconcile (the controller force-applies server-side as its field manager) — this is drift correction working, not a bug.
- Rollback = `git revert` (auditable), not `kubectl rollout undo`.
- Emergency hatch: suspend reconciliation, fix by hand, fix git, resume — never leave it suspended.

## Flux

CRDs: `GitRepository` (what to pull) → `Kustomization` (what path to apply, interval, prune, health checks) and `HelmRepository`/`HelmRelease` (charts). All in `flux-system` by convention.

```bash
flux get kustomizations -A          # sync status + errors
flux get helmreleases -A
flux reconcile kustomization <name> --with-source    # force sync now
flux suspend kustomization <name>   # emergency: stop reconciling
flux resume kustomization <name>
flux logs --follow
flux diff kustomization <name> --path ./clusters/prod   # preview against live
```

Diagnosis order: `flux get` (which object is failing) → `kubectl describe kustomization/helmrelease <name> -n flux-system` (the real error in conditions/events) → controller logs. Decryption of SOPS-encrypted secrets happens in kustomize-controller via a referenced age/gpg key secret.

## Argo CD

`Application` CRD: source (repo/path/chart + targetRevision) → destination (cluster/namespace) → syncPolicy:

```yaml
syncPolicy:
  automated: {prune: true, selfHeal: true}   # prune deletes removed objects; selfHeal reverts drift
  syncOptions: ["CreateNamespace=true"]
```

```bash
argocd app list; argocd app get <app>
argocd app diff <app>          # live vs git
argocd app sync <app>
argocd app history <app>; argocd app rollback <app> <id>
```

App-of-apps pattern: one Application points at a directory of Application manifests — bootstrap everything from one root. `ApplicationSet` generates Applications across clusters/dirs from templates.

## Repo layout patterns

```
clusters/<cluster-name>/...     # per-cluster entry point (Flux Kustomizations / Argo apps)
apps/
  base/<app>/                   # kustomize base: deployment, service, kustomization.yaml
  overlays/<env>/<app>/         # per-env patches (replicas, resources, hostnames, image tags)
infrastructure/                 # controllers, CRDs, cluster services — synced before apps
```

Order infra before apps (Flux `dependsOn`, Argo sync waves `argocd.argoproj.io/sync-wave`) so CRDs exist before CRs.

## Kustomize essentials

`kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod                  # force namespace on all resources
resources: [deployment.yaml, service.yaml, ../../base/app]
patches:
- path: replicas-patch.yaml      # strategic merge patch
- target: {kind: Deployment, name: web}
  patch: |-                      # inline JSON6902
    - op: replace
      path: /spec/replicas
      value: 5
images:
- name: registry.example.com/app
  newTag: v1.4.3                 # the GitOps way to bump a version
configMapGenerator:
- name: app-config
  files: [config.yaml]           # gets a content-hash suffix → pods roll on config change
labels:
- pairs: {app.kubernetes.io/part-of: shop}
  includeSelectors: false
```

```bash
kubectl kustomize <dir>          # render
kubectl apply -k <dir>; kubectl diff -k <dir>
```

The generator hash-suffix is the clean solution to "ConfigMap changed but pods didn't restart": new name → new pod template → rollout. Base/overlay discipline: bases are environment-agnostic; overlays patch only what differs per environment.

## Secrets in git

| Approach | How | Tradeoff |
|---|---|---|
| SOPS + age/KMS | Values encrypted in-file; GitOps controller decrypts with in-cluster key | Diffable structure, keys must be managed |
| Sealed Secrets | `kubeseal` encrypts against the cluster's controller keypair | Simple; ciphertext tied to one cluster |
| External Secrets Operator | `ExternalSecret` CR syncs from Vault/AWS/GCP secret managers | Secrets never in git; external dependency |

Never commit plaintext Secrets — base64 in a manifest is plaintext.

## Progressive delivery (brief)

Plain Deployments only do rolling updates. Canary/blue-green with analysis need **Argo Rollouts** (Rollout CRD replacing Deployment) or **Flagger** (wraps existing Deployments, shifts traffic via service mesh or ingress, auto-rollback on metric failure). Reach for them when "deploy 10% and watch error rate" is a requirement.

## Drift & operational hygiene

- Preview before merge: `kubectl diff -k`, `flux diff`, `argocd app diff` in CI.
- Detect manual meddling: `kubectl get <obj> --show-managed-fields` — a `kubectl` field manager entry on a controller-managed object means someone hand-edited.
- Per-field controller-ignore escape hatches exist (e.g. letting HPA own `replicas`) — use them rather than fighting reconciliation.
