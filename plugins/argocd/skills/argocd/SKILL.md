---
name: argocd
description: Use this skill for ANY ArgoCD task — installing ArgoCD, creating or debugging Applications/AppProjects/ApplicationSets, writing argocd CLI commands, configuring RBAC/SSO/Dex, managing secrets, setting up notifications, troubleshooting sync failures or health issues, designing multi-cluster GitOps workflows, implementing App of Apps pattern, or migrating from push-based CD to GitOps. Trigger whenever the user pastes ArgoCD YAML, ArgoCD error messages, asks about sync status, OutOfSync apps, ApplicationSet generators, Helm/Kustomize source config, argocd login failures, RBAC policy syntax, Sealed Secrets, External Secrets, or anything touching argo-cd. Also use for GitOps architecture questions where ArgoCD is the CD tool.
---

# ArgoCD Skill

Help users install, configure, operate, and troubleshoot ArgoCD — the declarative GitOps CD tool for Kubernetes.

## Operating Principles

1. **Read the live state before mutating.** Use `argocd app get <app>`, `argocd app diff <app>`, and `kubectl describe application <app> -n argocd` before suggesting changes.
2. **Prefer declarative over imperative.** Always show the YAML equivalent of CLI commands. Applications managed via UI/CLI will be overwritten if the cluster uses GitOps — point changes to the source repo.
3. **Understand sync ≠ health.** An app can be Synced but Degraded (e.g., pods crash-looping). Always check both sync status and health status.
4. **Minimal blast radius on fixes.** Use `argocd app sync --dry-run` before syncing, `argocd app diff` before changes. For stuck apps, prefer `argocd app terminate-op` over force-deleting resources.
5. **Surface the actual error.** ArgoCD sync errors are almost always in `argocd app get <app>` under `Operation State` or in `kubectl describe application`. Read it before guessing.

---

## Quick Diagnostics — Start Here

```bash
# Full app status (sync + health + conditions + last operation)
argocd app get <app-name>

# See what's actually different from Git
argocd app diff <app-name>

# Force a refresh from Git (bypass 3-min poll)
argocd app get <app-name> --refresh

# Sync a specific resource only
argocd app sync <app-name> --resource apps:Deployment:<name>

# Stream app logs
argocd app logs <app-name> --follow

# Kill a stuck sync operation
argocd app terminate-op <app-name>
```

### Reading App Status

```bash
argocd app get my-app
# Key fields to read:
# Health Status:   Healthy | Progressing | Degraded | Suspended | Missing | Unknown
# Sync Status:     Synced | OutOfSync | Unknown
# Operation:       Sync / Terminated / Error + message
# Conditions:      InvalidSpecError | ExcludedNode | SharedResource | etc.
```

### Fastest Troubleshooting Path

| Symptom | First command | Common cause |
|---|---|---|
| OutOfSync after sync | `argocd app diff` | Mutating webhook modifies resource; use `ignoreDifferences` |
| Progressing forever | `kubectl get pods -n <dest-ns>` | Pod not starting; check `kubectl describe pod` |
| Degraded | `argocd app get` → check conditions | CrashLoopBackOff, readiness probe failing |
| Sync failed | `argocd app get` → Operation State message | RBAC, resource quota, invalid YAML, hook failure |
| Missing | `argocd app get` → resource tree | Resource was pruned or never created |
| Repo error | `argocd repo list` | Credential expired, SSH key not trusted, `.git` suffix missing for GitLab |

---

## Core CRD Patterns

### Minimal Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io  # cascade delete
spec:
  project: default
  source:
    repoURL: https://github.com/my-org/my-config.git
    targetRevision: HEAD
    path: apps/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 2m
```

### Helm Application

```yaml
spec:
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: postgresql
    targetRevision: "15.x.x"
    helm:
      releaseName: postgres
      valueFiles:
        - values.yaml
        - values-production.yaml
      parameters:
        - name: primary.persistence.size
          value: "50Gi"
      values: |
        auth:
          existingSecret: postgres-credentials
```

### Kustomize Application

```yaml
spec:
  source:
    repoURL: https://github.com/my-org/config.git
    targetRevision: HEAD
    path: overlays/production
    kustomize:
      namePrefix: prod-
      images:
        - name: my-app
          newTag: v1.2.3
      patches:
        - target:
            kind: Deployment
            name: my-app
          patch: |-
            - op: replace
              path: /spec/replicas
              value: 3
```

### Multiple Sources

```yaml
spec:
  sources:
    - repoURL: https://charts.example.com
      chart: my-chart
      targetRevision: "1.0.0"
      helm:
        valueFiles:
          - $values/environments/production/values.yaml
    - repoURL: https://github.com/my-org/config.git
      targetRevision: HEAD
      ref: values  # reference name for $values above
```

### ignoreDifferences (fixes OutOfSync from mutations)

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas               # HPA manages replicas
    - group: ""
      kind: ConfigMap
      name: my-config
      jqPathExpressions:
        - .data."injected-key"         # Mutating webhook injects this
    - group: "*"
      kind: "*"
      managedFieldsManagers:
        - kube-controller-manager      # Ignore controller-managed fields
  syncPolicy:
    syncOptions:
      - RespectIgnoreDifferences=true  # Also respect during sync
```

---

## ApplicationSet — Key Generators

### Cluster Generator (deploy to all/selected clusters)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: my-app-all-clusters
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            env: production
  template:
    metadata:
      name: '{{name}}-my-app'
    spec:
      project: default
      source:
        repoURL: https://github.com/my-org/config.git
        targetRevision: HEAD
        path: 'clusters/{{name}}'
      destination:
        server: '{{server}}'
        namespace: my-app
```

### Git Directory Generator (one app per directory)

```yaml
spec:
  generators:
    - git:
        repoURL: https://github.com/my-org/apps.git
        revision: HEAD
        directories:
          - path: services/*
            exclude: false
          - path: services/legacy
            exclude: true
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      source:
        repoURL: https://github.com/my-org/apps.git
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
```

### Matrix Generator (clusters × environments)

```yaml
spec:
  generators:
    - matrix:
        generators:
          - clusters:
              selector:
                matchLabels:
                  type: workload
          - list:
              elements:
                - env: staging
                - env: production
```

---

## RBAC — Common Patterns

```yaml
# argocd-rbac-cm
data:
  policy.default: role:readonly   # all authenticated users get readonly
  scopes: '[groups, email]'
  policy.csv: |
    # Admin via SSO group
    g, my-org:platform-team, role:admin

    # Developer: sync dev/staging, read prod
    p, role:developer, applications, get,  */*, allow
    p, role:developer, applications, sync, dev/*, allow
    p, role:developer, applications, sync, staging/*, allow
    p, role:developer, logs,         get,  */*, allow
    g, my-org:developers, role:developer

    # CI bot: sync any app
    p, ci-bot, applications, get,  */*, allow
    p, ci-bot, applications, sync, */*, allow
```

```bash
# Test RBAC policy
argocd admin settings rbac can role:developer applications sync dev/my-app
argocd admin settings rbac validate --policy-file policy.csv
```

---

## CLI — Most Used Commands

```bash
# Authentication
argocd login argocd.example.com --grpc-web
argocd login argocd.example.com --auth-token $TOKEN  # CI/CD
argocd context                                         # show/switch contexts

# Application management
argocd app list
argocd app get <app> [--refresh]
argocd app sync <app> [--dry-run] [--prune] [--force]
argocd app wait <app> --health --timeout 120
argocd app rollback <app> <history-id>
argocd app history <app>
argocd app delete <app> [--cascade]  # --cascade also deletes k8s resources

# Multi-app operations
argocd app list -l app.kubernetes.io/part-of=my-suite
argocd app sync -l environment=staging

# Cluster management
argocd cluster add <context-name>    # registers cluster
argocd cluster list
argocd cluster rm <server-url>

# Repository management
argocd repo add https://github.com/org/repo --username u --password p
argocd repo add git@github.com:org/repo --ssh-private-key-path ~/.ssh/id_rsa
argocd repo list
argocd repo rm <url>

# Project management
argocd proj create my-project
argocd proj add-source my-project https://github.com/org/*
argocd proj add-destination my-project https://kubernetes.default.svc my-namespace
argocd proj role create-token my-project ci-role --expires-in 720h

# Admin (ops)
argocd admin app get my-app --core   # core-install mode
argocd admin export > backup.yaml    # backup all apps/projects
argocd admin import < backup.yaml
argocd admin settings validate       # check argocd-cm/argocd-rbac-cm
```

---

## Common Fixes

### App Stuck in Progressing
```bash
# Check what's not healthy
argocd app get <app>  # look at resource tree, find non-Healthy resources
kubectl get pods -n <dest-namespace>
kubectl describe pod <pod-name> -n <dest-namespace>  # events section
```

### Sync Operation Stuck
```bash
argocd app terminate-op <app-name>
# If hooks are stuck:
kubectl delete job <hook-job-name> -n <dest-namespace>
```

### OutOfSync Due to Managed Fields
```yaml
spec:
  ignoreDifferences:
    - group: "*"
      kind: "*"
      managedFieldsManagers:
        - kube-controller-manager
        - kube-scheduler
  syncPolicy:
    syncOptions:
      - ServerSideApply=true
      - RespectIgnoreDifferences=true
```

### Repository "Unknown" / Connection Failed
```bash
argocd repo list  # check status
# For GitLab: URL must end in .git
# For SSH: ensure known hosts
argocd admin settings update --argocd-cm-path argocd-cm.yaml
kubectl get cm argocd-ssh-known-hosts-cm -n argocd -o yaml
```

### App Synced But Pod Not Updated (Helm)
```bash
# Helm doesn't update Deployments when only ConfigMap changes
# Force pod restart via annotation:
argocd app actions run <app> restart --kind Deployment --resource-name <name>
```

---

## Reference Files

Load these when the task requires deep detail — don't read all at once, pick the relevant one:

| File | Contents |
|---|---|
| `references/01-installation-and-concepts.md` | Architecture, all install methods (kubectl/Helm/Kustomize), HA vs non-HA, ingress config, getting started |
| `references/02-crds-and-configuration.md` | Full Application/AppProject/ApplicationSet CRD specs with all fields, source types, sync options |
| `references/03-cli-reference-and-best-practices.md` | Complete CLI reference for all subcommands, flags, CI/CD integration patterns, sync waves |
| `references/04-security-rbac-sso.md` | RBAC policy syntax, Dex SSO connectors (GitHub/GitLab/LDAP/OIDC/Azure), secrets management, notifications |
| `references/05-troubleshooting-and-advanced.md` | Troubleshooting playbooks, HA setup, metrics, Helm/Kustomize deep dive, ApplicationSet patterns, upgrading |

**When to load which reference:**
- "How do I install ArgoCD?" → `01-installation-and-concepts.md`
- CRD spec questions, full field list → `02-crds-and-configuration.md`
- CLI flags, CI/CD pipeline commands → `03-cli-reference-and-best-practices.md`
- SSO, RBAC, secrets, notifications → `04-security-rbac-sso.md`
- Sync errors, stuck apps, performance, HA → `05-troubleshooting-and-advanced.md`
