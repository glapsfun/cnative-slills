# ArgoCD CRDs and Application Configuration

Comprehensive reference for ArgoCD's three core CRDs: Application, AppProject, and ApplicationSet, with full field specs and declarative configuration patterns.

---

## Table of Contents

1. [Application CRD — Full Spec](#1-application-crd--full-spec)
2. [Source Types](#2-source-types)
3. [Sync Policy and Options](#3-sync-policy-and-options)
4. [Health Status and Custom Health Checks](#4-health-status-and-custom-health-checks)
5. [Resource Hooks](#5-resource-hooks)
6. [ignoreDifferences](#6-ignoredifferences)
7. [AppProject CRD — Full Spec](#7-appproject-crd--full-spec)
8. [ApplicationSet CRD — All Generators](#8-applicationset-crd--all-generators)
9. [App of Apps Pattern](#9-app-of-apps-pattern)
10. [Declarative Setup Best Practices](#10-declarative-setup-best-practices)

---

## 1. Application CRD — Full Spec

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-application
  namespace: argocd           # Always in the ArgoCD namespace
  labels:
    app.kubernetes.io/part-of: argocd
  annotations:
    argocd.argoproj.io/refresh: "normal"   # Trigger refresh: normal | hard
  finalizers:
    # Cascade delete: removes all managed k8s resources when Application is deleted
    - resources-finalizer.argocd.argoproj.io
    # Foreground cascade delete (waits for deletion to complete)
    # - resources-finalizer.argocd.argoproj.io/foreground

spec:
  # Which AppProject this app belongs to (required)
  project: default

  # --- Single source (most common) ---
  source:
    repoURL: https://github.com/my-org/my-config.git
    targetRevision: HEAD       # branch, tag, commit SHA, or semver constraint
    path: apps/my-app          # path within the repo
    # See §2 for source-type-specific fields (helm/kustomize/directory/plugin)

  # --- Multiple sources (v2.6+) ---
  # sources:
  #   - repoURL: ...
  #     targetRevision: ...
  #     path: ...
  #   - repoURL: ...
  #     chart: ...
  #     targetRevision: ...
  #     ref: values            # give this source a $ref name for valueFiles

  destination:
    server: https://kubernetes.default.svc   # in-cluster
    # server: https://my-remote-cluster.example.com
    namespace: my-app          # target namespace in the cluster
    # name: in-cluster         # alternative to server: use cluster name

  # How many previous revision manifests to keep (default: 10)
  revisionHistoryLimit: 10

  # --- Sync behavior ---
  syncPolicy:
    automated:
      prune: true              # delete resources removed from Git
      selfHeal: true           # re-sync when live state drifts
      allowEmpty: false        # prevent pruning everything if source is empty
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
      - PruneLast=true
      - PrunePropagationPolicy=foreground  # foreground|background|orphan
      - Replace=false
      - FailOnSharedResource=true
      - RespectIgnoreDifferences=true
      - SkipDryRunOnMissingResource=true
    managedNamespaceMetadata:
      labels:
        env: production
      annotations:
        contact: platform-team@example.com
    retry:
      limit: 5                 # -1 = unlimited
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

  # --- Ignore resource differences ---
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas       # HPA manages replicas
    - group: ""
      kind: ConfigMap
      name: my-config
      namespace: my-app
      jqPathExpressions:
        - .data."runtime-injected"
    - group: "*"
      kind: "*"
      managedFieldsManagers:
        - kube-controller-manager
        - helm

  # --- Informational annotations visible in UI ---
  info:
    - name: Documentation
      value: https://wiki.example.com/my-app
    - name: Slack Channel
      value: "#platform-alerts"

  # --- Application-level health override ---
  # (see §4 for custom health checks via ConfigMap)
```

### Application Status Fields (read-only)

```yaml
status:
  sync:
    status: Synced              # Synced | OutOfSync | Unknown
    revision: abc1234           # current deployed commit
    comparedTo:
      source:
        repoURL: ...
        targetRevision: HEAD
        path: apps/my-app
  health:
    status: Healthy             # Healthy | Progressing | Degraded | Suspended | Missing | Unknown
    message: ""
  operationState:
    phase: Succeeded            # Running | Succeeded | Failed | Error | Terminating
    message: ""
    startedAt: "2024-01-01T00:00:00Z"
    finishedAt: "2024-01-01T00:01:00Z"
    operation:
      sync:
        revision: abc1234
        prune: true
  conditions:
    - type: ComparisonError     # or: SyncError, InvalidSpecError, SharedResourceWarning
      message: "..."
      lastTransitionTime: "..."
  resources:
    - group: apps
      version: v1
      kind: Deployment
      namespace: my-app
      name: my-app
      status: Synced
      health:
        status: Healthy
  summary:
    images:
      - my-registry/my-app:v1.2.3
```

---

## 2. Source Types

### Helm Chart from Repository

```yaml
spec:
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: postgresql           # chart name (for Helm repos only)
    targetRevision: "15.5.x"   # semver constraint, exact version, or HEAD
    helm:
      releaseName: postgres     # Helm release name (defaults to app name)
      version: v3               # Helm version: v2 | v3
      passCredentials: false    # pass credentials to sub-charts

      # Values files (resolved relative to source path or $ref)
      valueFiles:
        - values.yaml
        - values-production.yaml
        - $values/environments/prod/values.yaml  # from a $ref source

      # Inline values (highest precedence, merged last)
      values: |
        auth:
          existingSecret: postgres-credentials
        primary:
          persistence:
            size: 50Gi

      # Individual parameter overrides
      parameters:
        - name: primary.persistence.size
          value: "50Gi"
        - name: auth.username
          value: myuser
          forceString: true     # keep as string even if looks like number/bool

      # Skip CRD installation (useful when managing CRDs separately)
      skipCrds: false

      # Pass --set-file
      fileParameters:
        - name: config
          path: config/app.conf

      # Ignore helm hooks (manage via ArgoCD hooks instead)
      ignoreMissingValueFiles: true
```

### Helm Chart from Git

```yaml
spec:
  source:
    repoURL: https://github.com/my-org/charts.git
    targetRevision: HEAD
    path: charts/my-app        # directory containing Chart.yaml
    helm:
      releaseName: my-app
      valueFiles:
        - ../../environments/production/values.yaml  # relative path in repo
      values: |
        image:
          tag: v1.2.3
```

### Kustomize

```yaml
spec:
  source:
    repoURL: https://github.com/my-org/config.git
    targetRevision: HEAD
    path: overlays/production
    kustomize:
      version: v5.2.1          # pin kustomize version (must be configured on server)
      namePrefix: prod-
      nameSuffix: -v2
      namespace: production    # override namespace for all resources
      commonLabels:
        env: production
        team: platform
      forceCommonLabels: true  # override existing labels
      commonAnnotations:
        managed-by: argocd
      forceCommonAnnotations: false

      # Image tag overrides
      images:
        - name: my-registry/my-app
          newTag: v1.2.3
        - name: my-registry/my-app
          newName: my-registry/my-app-arm64  # rename image
          newTag: v1.2.3
        - name: my-registry/my-sidecar
          digest: sha256:abc123...

      # Inline patches (kustomize patch syntax)
      patches:
        - target:
            kind: Deployment
            name: my-app
          patch: |-
            - op: replace
              path: /spec/replicas
              value: 3
        - target:
            kind: Deployment
            labelSelector: "app=my-app"
          patch: |-
            apiVersion: apps/v1
            kind: Deployment
            metadata:
              name: irrelevant
            spec:
              template:
                spec:
                  containers:
                    - name: my-app
                      resources:
                        limits:
                          memory: 512Mi

      # Kustomize components
      components:
        - ../../components/monitoring
        - ../../components/ingress

      # Pass --load-restrictor=none
      kubeVersion: "1.29"
      apiVersions:
        - monitoring.coreos.com/v1

      # Build options passed to kustomize build
      namespace: production
```

### Directory (Plain YAML/JSON/Jsonnet)

```yaml
spec:
  source:
    repoURL: https://github.com/my-org/config.git
    targetRevision: HEAD
    path: manifests/my-app
    directory:
      recurse: true            # include subdirectories
      include: "*.yaml"        # glob filter (include only)
      exclude: "secret*.yaml"  # glob filter (exclude)

      # Jsonnet configuration
      jsonnet:
        extVars:
          - name: env
            value: production
          - name: apiKey
            code: false        # treat as string, not code
        tlas:                  # top-level arguments
          - name: cluster
            value: my-cluster
        libs:
          - vendor/            # jsonnet library paths
```

### Config Management Plugin (CMP)

```yaml
spec:
  source:
    repoURL: https://github.com/my-org/config.git
    targetRevision: HEAD
    path: apps/my-app
    plugin:
      name: my-cmp-plugin      # plugin name registered in argocd-cm
      env:
        - name: ENVIRONMENT
          value: production
        - name: SECRET_TOKEN
          value: $secret-key   # resolved from argocd-secret
      parameters:
        - name: helm-version
          string: v3
```

---

## 3. Sync Policy and Options

### Sync Options Reference

| Option | Scope | Description |
|---|---|---|
| `CreateNamespace=true` | App | Auto-create destination namespace if missing |
| `ServerSideApply=true` | App/Resource | Use Kubernetes SSA instead of client-side apply |
| `Replace=true` | App/Resource | Use `kubectl replace` (destructive, use for immutable fields) |
| `ApplyOutOfSyncOnly=true` | App | Only apply resources that are OutOfSync (faster for large apps) |
| `PruneLast=true` | App | Prune resources only after all others are synced and healthy |
| `PrunePropagationPolicy=foreground` | App | Deletion propagation: `foreground`, `background`, `orphan` |
| `Prune=false` | Resource annotation | Never prune this specific resource |
| `FailOnSharedResource=true` | App | Fail sync if a resource is already managed by another app |
| `RespectIgnoreDifferences=true` | App | Apply `ignoreDifferences` during sync (not just diff display) |
| `SkipDryRunOnMissingResource=true` | App | Skip dry-run for CRDs that don't exist yet |
| `Validate=false` | Resource annotation | Skip kubectl schema validation for this resource |
| `Force=true` | Resource annotation | Delete and re-create resource (destructive) |
| `Delete=false` | App | Keep resources when Application is deleted (no prune) |
| `Trim=true` | App | Trim trailing whitespace from string values |

### Resource-Level Annotations

```yaml
# On any managed resource:
metadata:
  annotations:
    # Exclude resource from ArgoCD management entirely
    argocd.argoproj.io/managed: "false"

    # Override sync option per resource
    argocd.argoproj.io/sync-options: "Replace=true"
    argocd.argoproj.io/sync-options: "ServerSideApply=true,Force=true"

    # Never prune this resource
    argocd.argoproj.io/sync-options: "Prune=false"

    # Apply a sync wave
    argocd.argoproj.io/sync-wave: "5"

    # Resource hook type
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

### Sync Windows (in AppProject)

```yaml
spec:
  syncWindows:
    - kind: allow
      schedule: "10 1 * * *"   # cron expression
      duration: 1h
      applications:
        - "*"
      namespaces:
        - production
      clusters:
        - in-cluster
      timeZone: "America/New_York"
    - kind: deny
      schedule: "0 22 * * 5"   # Friday 10pm
      duration: 16h
      namespaces:
        - production
      manualSync: true          # allow manual override during deny window
```

---

## 4. Health Status and Custom Health Checks

### Built-in Health Check Resources

ArgoCD has built-in health checks for these resource types:
- `apps/Deployment`, `apps/StatefulSet`, `apps/DaemonSet`, `apps/ReplicaSet`
- `batch/Job`, `batch/CronJob`
- `v1/Pod`, `v1/Service`, `v1/PersistentVolumeClaim`
- `networking.k8s.io/Ingress`
- `argoproj.io/Rollout` (Argo Rollouts)

### Custom Health Check (Lua Script)

Add to `argocd-cm` ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  # Custom health check for a CRD
  resource.customizations.health.my.io_MyResource: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.phase == "Running" then
        hs.status = "Healthy"
        hs.message = "Resource is running"
        return hs
      end
      if obj.status.phase == "Failed" then
        hs.status = "Degraded"
        hs.message = obj.status.message or "Resource failed"
        return hs
      end
      if obj.status.phase == "Pending" then
        hs.status = "Progressing"
        hs.message = "Resource is starting up"
        return hs
      end
    end
    hs.status = "Progressing"
    hs.message = "Waiting for status"
    return hs

  # Custom health check for Flux HelmRelease
  resource.customizations.health.helm.toolkit.fluxcd.io_HelmRelease: |
    hs = {}
    if obj.status ~= nil then
      for _, condition in ipairs(obj.status.conditions or {}) do
        if condition.type == "Ready" then
          if condition.status == "True" then
            hs.status = "Healthy"
            hs.message = condition.message
            return hs
          else
            hs.status = "Degraded"
            hs.message = condition.message
            return hs
          end
        end
      end
    end
    hs.status = "Progressing"
    hs.message = "Waiting for HelmRelease to be ready"
    return hs
```

### Ignore Health Check for a Resource Type

```yaml
data:
  resource.customizations.health.my.io_MyResource: |
    hs = {}
    hs.status = "Healthy"
    hs.message = "Ignored"
    return hs
```

### Custom Actions (UI/CLI triggered operations)

```yaml
data:
  resource.customizations.actions.my.io_MyResource: |
    discovery.lua: |
      actions = {}
      actions["restart"] = {["disabled"] = false}
      return actions
    definitions:
    - name: restart
      action.lua: |
        obj.metadata.annotations["restart-trigger"] = tostring(os.time())
        return obj
```

---

## 5. Resource Hooks

Hooks are Kubernetes resources (usually Jobs) with special annotations that run at specific sync phases.

### Hook Types

| Hook | When it runs | Use case |
|---|---|---|
| `PreSync` | Before manifests are applied | Database migrations, pre-flight checks |
| `Sync` | Concurrently with manifest application (after PreSync) | Custom resource creation |
| `PostSync` | After all resources are Healthy | Smoke tests, Slack notifications, cache warming |
| `SyncFail` | When the sync operation fails | Rollback notifications, cleanup |
| `PostDelete` | After the Application's resources are deleted | Cleanup external resources |
| `Skip` | Never applied by ArgoCD | Exclude a resource from sync (but show in diff) |

### Hook Deletion Policies

| Policy | Description |
|---|---|
| `HookSucceeded` | Delete resource after it succeeds |
| `HookFailed` | Delete resource after it fails |
| `BeforeHookCreation` | Delete any existing resource with same name before creating (default) |

### Database Migration PreSync Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  namespace: my-app
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    argocd.argoproj.io/sync-wave: "-1"   # run before other PreSync hooks
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: db-migrator
      containers:
        - name: migrate
          image: my-registry/my-app:v1.2.3
          command: ["./migrate", "--db-url", "$(DB_URL)"]
          env:
            - name: DB_URL
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: url
  backoffLimit: 0
```

### Smoke Test PostSync Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: smoke-test
  namespace: my-app
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: test
          image: curlimages/curl:latest
          command:
            - sh
            - -c
            - |
              curl -f http://my-app.my-app.svc.cluster.local/health || exit 1
  backoffLimit: 3
```

### SyncFail Notification Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sync-fail-notify
  namespace: argocd
  annotations:
    argocd.argoproj.io/hook: SyncFail
    argocd.argoproj.io/hook-delete-policy: HookFailed
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: notify
          image: curlimages/curl:latest
          command:
            - sh
            - -c
            - |
              curl -X POST -H 'Content-type: application/json' \
                --data '{"text":"Sync failed for $ARGOCD_APP_NAME"}' \
                $SLACK_WEBHOOK_URL
          env:
            - name: ARGOCD_APP_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.labels['app.kubernetes.io/instance']
            - name: SLACK_WEBHOOK_URL
              valueFrom:
                secretKeyRef:
                  name: slack-webhook
                  key: url
```

### Sync Waves

Control ordering within a sync phase. Lower wave number = applied first. Default wave = 0.

```yaml
# Wave ordering within a phase:
# 1. All wave -2 resources become Healthy
# 2. All wave -1 resources become Healthy (e.g., CRDs)
# 3. All wave 0 resources (default, e.g., ConfigMaps, Secrets)
# 4. All wave 1 resources (e.g., Deployments)
# 5. All wave 2 resources (e.g., dependent services)

# CRDs first
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: myresources.my.io
  annotations:
    argocd.argoproj.io/sync-wave: "-2"

---
# Namespace and RBAC second
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  annotations:
    argocd.argoproj.io/sync-wave: "-1"

---
# Application last
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

---

## 6. ignoreDifferences

Prevent specific resource fields from triggering OutOfSync.

### Common Patterns

```yaml
spec:
  ignoreDifferences:
    # HPA manages replicas — ignore drift
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas

    # Specific resource by name
    - group: ""
      kind: ConfigMap
      name: my-config
      namespace: my-app
      jsonPointers:
        - /data/generated-at

    # JQ expression (more powerful than JSON pointer)
    - group: apps
      kind: Deployment
      jqPathExpressions:
        - .spec.template.spec.containers[].env[] | select(.name == "INJECTED_VAR")

    # Managed fields from controllers (ignores specific field managers)
    - group: "*"
      kind: "*"
      managedFieldsManagers:
        - kube-controller-manager
        - kube-scheduler
        - helm

    # Ignore all status fields
    - group: "apiextensions.k8s.io"
      kind: "CustomResourceDefinition"
      jsonPointers:
        - /status

    # Webhook-injected sidecar
    - group: apps
      kind: Deployment
      jqPathExpressions:
        - .spec.template.spec.containers[] | select(.name == "istio-proxy")
        - .spec.template.spec.initContainers[] | select(.name == "istio-init")
        - .spec.template.metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]
```

### Global ignoreDifferences (argocd-cm)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  # Apply to all applications globally
  resource.customizations.ignoreDifferences.apps_Deployment: |
    jsonPointers:
    - /spec/replicas
    managedFieldsManagers:
    - kube-controller-manager

  resource.customizations.ignoreDifferences.admissionregistration.k8s.io_MutatingWebhookConfiguration: |
    jqPathExpressions:
    - '.webhooks[]?.clientConfig.caBundle'
```

---

## 7. AppProject CRD — Full Spec

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-alpha
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  description: "Team Alpha project"

  # Allowed source Git repos (glob, negation with !)
  sourceRepos:
    - https://github.com/my-org/team-alpha-*
    - https://github.com/my-org/shared-charts
    - "!https://github.com/my-org/forbidden"
    # Allow all:
    # - "*"

  # Source namespaces: where Application CRs can live (v2.5+)
  # Allows teams to manage their own Application CRs
  sourceNamespaces:
    - team-alpha

  # Allowed deployment destinations
  destinations:
    - server: https://kubernetes.default.svc
      namespace: team-alpha-*          # glob supported
    - server: https://prod-cluster.example.com
      namespace: team-alpha-production
    # Allow any namespace on any cluster (DANGER in multi-tenant):
    # - server: "*"
    #   namespace: "*"

  # Cluster-scoped resources the project can deploy
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
    - group: rbac.authorization.k8s.io
      kind: ClusterRole
    - group: rbac.authorization.k8s.io
      kind: ClusterRoleBinding
    # Deny all cluster resources:
    # clusterResourceBlacklist:
    #   - group: "*"
    #     kind: "*"

  # Namespace-scoped resources the project CANNOT deploy
  namespaceResourceBlacklist:
    - group: ""
      kind: ResourceQuota
    - group: ""
      kind: LimitRange
    - group: networking.k8s.io
      kind: NetworkPolicy

  # Alternative: whitelist specific namespace resources (deny all others)
  # namespaceResourceWhitelist:
  #   - group: apps
  #     kind: Deployment
  #   - group: apps
  #     kind: StatefulSet

  # Orphaned resources: warn about k8s resources not managed by any app
  orphanedResources:
    warn: true
    ignore:
      - group: ""
        kind: ConfigMap
        name: kube-root-ca.crt

  # Sync windows (restrict when syncs can happen)
  syncWindows:
    - kind: allow
      schedule: "0 9 * * 1-5"    # weekdays 9am
      duration: 8h
      applications:
        - "*"
    - kind: deny
      schedule: "0 22 * * 5"     # Friday 10pm
      duration: 60h               # fri night through monday morning
      namespaces:
        - team-alpha-production
      manualSync: true            # emergency manual override allowed

  # Restrict to clusters owned by this project
  permitOnlyProjectScopedClusters: false

  # Project-level RBAC roles
  roles:
    - name: developer
      description: "Dev access to staging"
      policies:
        - p, proj:team-alpha:developer, applications, get,    team-alpha/*, allow
        - p, proj:team-alpha:developer, applications, sync,   team-alpha/*-staging, allow
        - p, proj:team-alpha:developer, logs,         get,    team-alpha/*, allow
        - p, proj:team-alpha:developer, applications, action/*/Pod/delete, team-alpha/*, allow
      groups:
        - my-org:team-alpha-devs

    - name: ci-deployer
      description: "CI pipeline automation"
      policies:
        - p, proj:team-alpha:ci-deployer, applications, get,    team-alpha/*, allow
        - p, proj:team-alpha:ci-deployer, applications, sync,   team-alpha/*, allow
        - p, proj:team-alpha:ci-deployer, applications, update, team-alpha/*, allow
      # JWT tokens generated via: argocd proj role create-token team-alpha ci-deployer
      jwtTokens:
        - iat: 1696000000

# Generate a token:
# argocd proj role create-token team-alpha ci-deployer --expires-in 720h
```

---

## 8. ApplicationSet CRD — All Generators

### List Generator

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
  namespace: argocd
spec:
  # Prevent ApplicationSet deletion if apps exist
  preservedFields:
    annotations:
      - argocd.argoproj.io/skip-reconcile

  # Control when apps are created/updated/deleted
  syncPolicy:
    # Create apps but don't auto-delete when removed from generator
    preserveResourcesOnDeletion: false
    applicationsSync: create-update   # create-only | create-update | create-update-delete

  generators:
    - list:
        elements:
          - cluster: dev
            url: https://dev.example.com
            env: development
          - cluster: staging
            url: https://staging.example.com
            env: staging
          - cluster: prod
            url: https://prod.example.com
            env: production

  template:
    metadata:
      name: '{{cluster}}-guestbook'
      labels:
        env: '{{env}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/my-org/config.git
        targetRevision: HEAD
        path: 'environments/{{env}}'
      destination:
        server: '{{url}}'
        namespace: guestbook
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Cluster Generator

```yaml
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            env: production
            region: us-east-1
          matchExpressions:
            - key: tier
              operator: In
              values: [workload, shared]

        # Values injected for all clusters (can be overridden per cluster)
        values:
          revision: stable
          environment: production

        # Template variables available:
        # {{name}}       - cluster name
        # {{server}}     - cluster API server URL
        # {{metadata.labels.<key>}} - cluster label values
        # {{metadata.annotations.<key>}} - cluster annotation values
        # {{values.<key>}} - values defined above
```

### Git Directory Generator

```yaml
spec:
  generators:
    - git:
        repoURL: https://github.com/my-org/apps.git
        revision: HEAD
        requeueAfterSeconds: 20    # polling interval for new directories

        directories:
          - path: services/*
          - path: services/deprecated
            exclude: true

        # Variables available:
        # {{path}}              - full path (e.g., services/my-app)
        # {{path.basename}}     - last directory component (e.g., my-app)
        # {{path.basenameNormalized}} - normalized for k8s names
        # {{path[0]}}           - first path segment
        # {{path[N]}}           - Nth path segment
```

### Git Files Generator

```yaml
spec:
  generators:
    - git:
        repoURL: https://github.com/my-org/config.git
        revision: HEAD
        files:
          - path: "apps/**/config.json"

# config.json example:
# {
#   "app": { "name": "my-service", "namespace": "production" },
#   "helm": { "valueFile": "values-prod.yaml" }
# }
# Access as: {{app.name}}, {{app.namespace}}, {{helm.valueFile}}
```

### Matrix Generator

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
                - environment: staging
                  imageTag: latest
                - environment: production
                  imageTag: v1.2.3
  template:
    metadata:
      name: '{{name}}-{{environment}}'
    spec:
      source:
        helm:
          parameters:
            - name: image.tag
              value: '{{imageTag}}'
            - name: environment
              value: '{{environment}}'
      destination:
        server: '{{server}}'
        namespace: '{{environment}}'
```

### Merge Generator

```yaml
spec:
  generators:
    - merge:
        mergeKeys:
          - server              # key(s) to merge on
        generators:
          # Base: all clusters
          - clusters:
              values:
                env: staging
                imageTag: latest
          # Override: production clusters get different values
          - list:
              elements:
                - server: https://prod.example.com
                  env: production
                  imageTag: v1.2.3
```

### Pull Request Generator (GitHub)

```yaml
spec:
  generators:
    - pullRequest:
        github:
          owner: my-org
          repo: my-app
          appSecretName: github-app-secret  # GitHub App credentials
          tokenRef:                          # or PAT
            secretName: github-token
            key: token
          labels:
            - preview                        # only PRs with this label
        requeueAfterSeconds: 60
  template:
    metadata:
      name: 'preview-{{number}}'
    spec:
      source:
        helm:
          parameters:
            - name: image.tag
              value: '{{head_sha}}'
            - name: ingress.host
              value: 'pr-{{number}}.preview.example.com'
      destination:
        namespace: 'preview-{{number}}'
      syncPolicy:
        syncOptions:
          - CreateNamespace=true
```

### SCM Provider Generator (GitHub)

```yaml
spec:
  generators:
    - scmProvider:
        github:
          organization: my-org
          appSecretName: github-app-secret
          allBranches: false   # only default branch
        filters:
          - repositoryMatch: ^my-app-.*    # regex
            labelMatch: argocd-managed
            branchMatch: main
        requeueAfterSeconds: 300
  template:
    metadata:
      name: '{{repository}}'
    spec:
      source:
        repoURL: '{{url}}'
        targetRevision: '{{branch}}'
        path: deploy/
      destination:
        namespace: '{{repository}}'
```

### ApplicationSet Sync Policy

```yaml
spec:
  # Control how generated Applications are reconciled
  syncPolicy:
    preserveResourcesOnDeletion: true     # don't delete apps when removed from generator
    applicationsSync: create-update       # create-only | create-update | create-update-delete

  # Prevent specific Application fields from being overwritten
  ignoreApplicationDifferences:
    - jsonPointers:
        - /spec/source/targetRevision     # don't overwrite if manually changed

  # Template patch (per-element overrides)
  templatePatch: |
    {{- if eq .cluster "prod" }}
    spec:
      syncPolicy:
        automated:
          selfHeal: true
    {{- end }}

  # Progressive rollouts (deploy to clusters in waves)
  strategy:
    type: RollingSync
    rollingSync:
      steps:
        - matchExpressions:
            - key: env
              operator: In
              values:
                - dev
        - matchExpressions:
            - key: env
              operator: In
              values:
                - staging
          maxUpdate: 2         # max concurrent
        - matchExpressions:
            - key: env
              operator: In
              values:
                - production
          maxUpdate: "10%"
```

---

## 9. App of Apps Pattern

A root Application that manages other Application CRs via Git.

```
config-repo/
├── root-app/
│   └── applications/
│       ├── team-alpha-app.yaml      # Application CRD
│       ├── team-beta-app.yaml       # Application CRD
│       └── infrastructure-app.yaml  # Application CRD
└── apps/
    ├── team-alpha/                  # Team Alpha's actual manifests
    ├── team-beta/
    └── infrastructure/
```

```yaml
# Root application (applied once manually or via bootstrap)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/my-org/config.git
    targetRevision: HEAD
    path: root-app/applications       # Contains Application CRDs
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd                 # Applications land in argocd namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

```yaml
# Child Application (one of many in root-app/applications/)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: team-alpha-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: team-alpha
  source:
    repoURL: https://github.com/my-org/config.git
    targetRevision: HEAD
    path: apps/team-alpha
  destination:
    server: https://kubernetes.default.svc
    namespace: team-alpha
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**App of Apps vs ApplicationSet:**
- App of Apps: Flexible, each child app independently configured in Git. Better for varied configurations.
- ApplicationSet: Templated, DRY. Better for uniform deployments across many clusters/environments.

---

## 10. Declarative Setup Best Practices

### Repository Secret (declarative)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-private-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/my-org/private-config
  # HTTPS credentials
  username: my-user
  password: my-token
  # OR: SSH private key
  # sshPrivateKey: |
  #   -----BEGIN OPENSSH PRIVATE KEY-----
  #   ...
  # OR: GitHub App
  # githubAppID: "123456"
  # githubAppInstallationID: "789"
  # githubAppPrivateKey: |
  #   -----BEGIN RSA PRIVATE KEY-----
  #   ...
  # Optional: make project-scoped
  project: my-project
```

### Credential Template (shared credentials for URL prefix)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-org-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  type: git
  url: https://github.com/my-org   # all repos under this prefix use these creds
  username: git
  password: ghp_mytoken
```

### Cluster Secret (declarative registration)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: prod-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    env: production               # used by cluster generator selector
    region: us-east-1
type: Opaque
stringData:
  name: prod-us-east-1
  server: https://api.prod.example.com
  config: |
    {
      "bearerToken": "eyJhbGciOiJSUzI1NiJ9...",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "LS0tLS1CRUdJTi..."
      }
    }
```

### argocd-cm Key Settings

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  # ArgoCD URL (required for SSO callbacks, notifications)
  url: https://argocd.example.com

  # Git polling interval (default: 3m)
  timeout.reconciliation: 180s

  # Enable Apps in any Namespace (v2.5+)
  application.namespaces: "team-alpha, team-beta"

  # Disable admin user (after SSO is configured)
  admin.enabled: "false"

  # Kustomize build options
  kustomize.buildOptions: "--load-restrictor=LoadRestrictionsNone"

  # Helm version override
  helm.versions: "v3.14"

  # Resource tracking method (default: label)
  application.resourceTrackingMethod: annotation   # label | annotation | annotation+label

  # Custom resource actions and health checks (see §4)
  resource.customizations.health.my.io_MyResource: |
    hs = {}
    hs.status = "Healthy"
    return hs
```

### argocd-cmd-params-cm Runtime Parameters

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd
data:
  # Server
  server.insecure: "false"
  server.tls.minversion: "1.2"
  server.log.level: "info"

  # Repo server
  reposerver.parallelism.limit: "10"
  reposerver.max.combined.directory.manifests.size: "10M"

  # Application controller
  controller.status.processors: "20"
  controller.operation.processors: "10"
  controller.self.heal.timeout.seconds: "5"
  controller.repo.server.timeout.seconds: "60"

  # ApplicationSet
  applicationsetcontroller.enable.progressive.syncs: "true"
```
