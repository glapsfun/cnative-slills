# ArgoCD Troubleshooting and Advanced Patterns

Comprehensive reference for ArgoCD troubleshooting, operations, advanced patterns, and best practices. Sourced from official ArgoCD documentation (stable release).

---

## Table of Contents

1. [Sync Troubleshooting](#1-sync-troubleshooting)
2. [Out of Sync Issues and Diffing Customization](#2-out-of-sync-issues-and-diffing-customization)
3. [Application States: Progressing, Degraded, Unknown](#3-application-states-progressing-degraded-unknown)
4. [Repository Connection Issues](#4-repository-connection-issues)
5. [Private Repositories](#5-private-repositories)
6. [RBAC Configuration and Troubleshooting](#6-rbac-configuration-and-troubleshooting)
7. [Performance Tuning](#7-performance-tuning)
8. [High Availability Setup](#8-high-availability-setup)
9. [Metrics and Monitoring](#9-metrics-and-monitoring)
10. [Upgrading ArgoCD](#10-upgrading-argocd)
11. [Helm Chart Management](#11-helm-chart-management)
12. [Kustomize Configuration](#12-kustomize-configuration)
13. [Automated Sync Policy](#13-automated-sync-policy)
14. [Sync Options Reference](#14-sync-options-reference)
15. [ApplicationSet Patterns](#15-applicationset-patterns)
16. [App of Apps Pattern](#16-app-of-apps-pattern)
17. [Multi-Cluster Management](#17-multi-cluster-management)
18. [Best Practices](#18-best-practices)
19. [Operator Troubleshooting Tools](#19-operator-troubleshooting-tools)

---

## 1. Sync Troubleshooting

### Common Sync Errors

#### Context Deadline Exceeded
```
Error: context deadline exceeded
```
**Cause:** Manifest generation is taking too long and overflowing the refresh queue.

**Fix:** Increase the repo-server timeout:
```bash
# Patch the application controller
kubectl edit deployment argocd-repo-server -n argocd
# Add or increase: --repo-server-timeout-seconds=120
```
Or via env variable on the application controller:
```bash
--repo-server-timeout-seconds=300
```
Also consider scaling up `argocd-repo-server` replicas.

#### Server Could Not Find the Requested Resource (CRD Not Yet Applied)
```
error: the server could not find the requested resource
```
**Cause:** A custom resource is being applied before its CRD is in the cluster.

**Fix:** Use `SkipDryRunOnMissingResource` sync option on the resource:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
```
Or at the application level:
```yaml
spec:
  syncPolicy:
    syncOptions:
      - SkipDryRunOnMissingResource=true
```

#### Resource Too Large for Client-Side Apply (Annotation Size Limit)
```
metadata.annotations: Too long: must have at most 262144 bytes
```
**Cause:** The `kubectl.kubernetes.io/last-applied-configuration` annotation exceeds Kubernetes size limits.

**Fix:** Enable server-side apply:
```yaml
spec:
  syncPolicy:
    syncOptions:
      - ServerSideApply=true
```

#### Shared Resource Conflict
If you want ArgoCD to fail the sync when a resource is managed by another Application:
```yaml
spec:
  syncPolicy:
    syncOptions:
      - FailOnSharedResource=true
```

#### Sync Stuck Due to PreSync Hook Failure
Hooks run in waves. If a PreSync hook fails, the sync stops. Check hook status:
```bash
argocd app get <app-name> --show-operation
kubectl get jobs -n <namespace> -l app.kubernetes.io/instance=<app-name>
kubectl logs -n <namespace> job/<hook-job-name>
```

### Debugging Sync Operations

```bash
# View application details and sync status
argocd app get <app-name>

# View detailed operation status
argocd app get <app-name> --show-operation

# Manually trigger a refresh
argocd app get <app-name> --refresh

# Hard refresh (ignores cache)
argocd app get <app-name> --hard-refresh

# View differences between Git and live state
argocd app diff <app-name>

# View resource tree
argocd app resources <app-name>

# Sync with specific options
argocd app sync <app-name> --dry-run
argocd app sync <app-name> --prune
argocd app sync <app-name> --replace
argocd app sync <app-name> --force
argocd app sync <app-name> --server-side
```

---

## 2. Out of Sync Issues and Diffing Customization

### Why an App Stays OutOfSync After Successful Sync

Common reasons:
- Extra or unknown fields in the manifest that Kubernetes drops from the live state
- A mutating webhook or controller modifies the object after submission
- A Helm chart uses `randAlphaNum` or similar functions generating different data each render
- HPA reorders `spec.metrics` in a specific order
- Status fields stored in Git manifests
- Aggregated ClusterRoles rules being modified by Kubernetes

### Ignoring Differences at Application Level

Ignore specific JSON paths using RFC6902 JSON patches:
```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
```

Narrow to a specific resource:
```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      name: guestbook
      namespace: default
      jsonPointers:
        - /spec/replicas
```

Use JQ path expressions for list elements:
```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jqPathExpressions:
        - .spec.template.spec.initContainers[] | select(.name == "injected-init-container")
```

Ignore fields by managed field managers (e.g., kube-controller-manager):
```yaml
spec:
  ignoreDifferences:
    - group: '*'
      kind: '*'
      managedFieldsManagers:
        - kube-controller-manager
```

Note: If your pointer path contains `/`, replace it with `~1`:
```yaml
jsonPointers:
  - /metadata/labels/node-role.kubernetes.io~1worker
```

### System-Level Diff Customization (argocd-cm)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  # Ignore caBundle field for MutatingWebhookConfiguration
  resource.customizations.ignoreDifferences.admissionregistration.k8s.io_MutatingWebhookConfiguration: |
    jqPathExpressions:
      - '.webhooks[]?.clientConfig.caBundle'

  # Ignore kube-controller-manager changes in Deployments
  resource.customizations.ignoreDifferences.apps_Deployment: |
    managedFieldsManagers:
      - kube-controller-manager

  # Apply to ALL resources in every Application
  resource.customizations.ignoreDifferences.all: |
    managedFieldsManagers:
      - kube-controller-manager
    jsonPointers:
      - /spec/replicas

  # Disable status field diffing
  resource.compareoptions: |
    ignoreResourceStatusField: all
    # Options: 'crd', 'all', 'none'

  # Ignore aggregated ClusterRole rule changes
  resource.compareoptions: |
    ignoreAggregatedRoles: true
```

### Handling randAlphaNum in Helm Charts

ArgoCD renders Helm manifests periodically to check for drift. Functions like `randAlphaNum` generate new values each render causing constant OutOfSync.

**Fix:** Pin the value explicitly:
```bash
argocd app set redis -p password=abc123
```
Or in `values.yaml`:
```yaml
password: "abc123"  # Use a stable value
```

### Known Kubernetes Types in CRDs (False Positives)

Some CRDs reuse core Kubernetes types (e.g., `PodSpec`) whose marshaling differs:
```
from: cpu: 100m
to:   cpu: 0.1
```
Fix by declaring known type fields:
```yaml
data:
  resource.customizations.knownTypeFields.argoproj.io_Rollout: |
    - field: spec.template.spec
      type: core/v1/PodSpec
```

### JQ Timeout for Complex Expressions

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
data:
  ignore.normalizer.jq.timeout: '5s'
```

### Making ignoreDifferences Active During Sync

By default, `ignoreDifferences` only affects diff display, not sync behavior. To make sync respect it:
```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
  syncPolicy:
    syncOptions:
      - RespectIgnoreDifferences=true
```

---

## 3. Application States: Progressing, Degraded, Unknown

### Application Stuck in Progressing

ArgoCD marks an application "Progressing" when resources are not yet healthy.

**Debug steps:**
```bash
# Check the resource health details
argocd app get <app-name>

# Check resource events
kubectl describe <resource-type>/<resource-name> -n <namespace>

# Common culprits: Deployments, StatefulSets, Jobs not reaching desired state
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

**Common causes:**
- Pods in CrashLoopBackOff or ImagePullBackOff
- PVC not bound
- Resource quotas exceeded
- Init containers failing

**Custom health checks** can be added in `argocd-cm` using Lua:
```yaml
data:
  resource.customizations.health.argoproj.io_Rollout: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.phase == "Paused" then
        hs.status = "Healthy"
        hs.message = obj.status.message
        return hs
      end
    end
    return hs
```

Test a health check locally:
```bash
argocd admin settings resource-overrides health ./deploy.yaml --argocd-cm-path ./argocd-cm.yaml
```

### Application in Degraded State

An application becomes "Degraded" when one or more resources are unhealthy.

```bash
# Check which resources are degraded
argocd app get <app-name>
argocd app resources <app-name>

# Check specific resource health
kubectl get <resource-type> <resource-name> -n <namespace> -o yaml
```

### Unknown Status

Unknown status often means the application controller cannot communicate with the target cluster.

```bash
# Check application controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Verify cluster connectivity
argocd cluster get <cluster-url>
argocd cluster list
```

---

## 4. Repository Connection Issues

### SSH Known Hosts Issues

Error:
```
Unable to connect to repository: ssh: handshake failed: ssh: unable to authenticate, attempted methods [none publickey]
```

**Fix:** Add the SSH known hosts:
```bash
# Via CLI
argocd cert add-ssh --batch < /etc/ssh/ssh_known_hosts

# Or add specific host
ssh-keyscan github.com | argocd cert add-ssh --batch
```

Via declarative configuration:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-ssh-known-hosts-cm
  namespace: argocd
data:
  ssh_known_hosts: |
    github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFB...
```

### HTTPS Repository TLS Issues

Error:
```
x509: certificate signed by unknown authority
```

**Fix (recommended - add CA cert):**
```bash
argocd cert add-tls git.example.com --from /path/to/ca-cert.pem
```

**Fix (insecure - not for production):**
```bash
argocd repo add https://git.example.com/repo.git --insecure-skip-server-verification
```

### GitLab `.git` Suffix Requirement

GitLab requires the `.git` suffix in repository URLs. ArgoCD will not follow HTTP 301 redirects:
```bash
# Wrong
argocd repo add https://gitlab.example.com/group/repo

# Correct
argocd repo add https://gitlab.example.com/group/repo.git
```

### Troubleshooting Cluster Credentials

If you manually created a cluster Secret and encounter connectivity issues:

```bash
# 1. SSH into the application-controller pod
kubectl exec -n argocd -it \
  $(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-application-controller -o jsonpath='{.items[0].metadata.name}') -- bash

# 2. Export kubeconfig from the cluster Secret
argocd admin cluster kubeconfig https://<api-server-url> /tmp/kubeconfig --namespace argocd

# 3. Use kubectl with verbose output to debug
export KUBECONFIG=/tmp/kubeconfig
kubectl get pods -v 9
```

---

## 5. Private Repositories

### HTTPS Username/Password

```bash
argocd repo add https://github.com/myorg/myrepo --username <username> --password <password>
```

### HTTPS with Access Token

Use any non-empty string as username and the token as password:
```bash
argocd repo add https://github.com/myorg/myrepo --username token --password <access-token>
```

For BitBucket Cloud/Data Center, use `x-token-auth` as username:
```bash
argocd repo add https://bitbucket.org/myorg/myrepo --username x-token-auth --password <token>
```

### HTTPS with TLS Client Certificates

```bash
argocd repo add https://repo.example.com/repo.git \
  --tls-client-cert-path ~/mycert.crt \
  --tls-client-cert-key-path ~/mycert.key \
  --username myuser --password mypass
```

Note: Certificate must be in PEM format, not PKCS12, and the key must not be password-protected.

### SSH Private Key

```bash
argocd repo add git@github.com:myorg/myrepo.git --ssh-private-key-path ~/.ssh/id_rsa
```

Note: As of ArgoCD 2.4 (OpenSSH 8.9), `ssh-rsa` SHA-1 key signatures are no longer supported. Use `ed25519` or `ecdsa` keys.

For non-standard SSH ports, use `ssh://` format (not SCP-style `git@`):
```bash
argocd repo add ssh://git@example.com:2222/myrepo.git --ssh-private-key-path ~/.ssh/id_rsa
```

### GitHub App Authentication

```bash
argocd repo add https://github.com/myorg/myrepo.git \
  --github-app-id 1 \
  --github-app-installation-id 2 \
  --github-app-private-key-path test.private-key.pem
```

For GitHub Enterprise:
```bash
argocd repo add https://ghe.example.com/myorg/myrepo.git \
  --github-app-id 1 \
  --github-app-installation-id 2 \
  --github-app-private-key-path test.private-key.pem \
  --github-app-enterprise-base-url https://ghe.example.com/api/v3
```

### Google Cloud Source

```bash
argocd repo add https://source.developers.google.com/p/my-project/r/my-repo \
  --gcp-service-account-key-path service-account-key.json
```

### Azure Repos with Workload Identity

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: git-private-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://contoso@dev.azure.com/my-projectcollection/my-project/_git/my-repo
  useAzureWorkloadIdentity: "true"
```

### Credential Templates (Prefix-Based)

Set up credentials once for an entire URL prefix:
```bash
argocd repocreds add https://github.com/myorg --username myuser --password mypass

# Now any repo under https://github.com/myorg can be added without credentials
argocd repo add https://github.com/myorg/any-repo
```

### Declarative Repository Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-private-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/myorg/myrepo
  username: myuser
  password: mypassword
```

For SSH:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-private-repo-ssh
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: git@github.com:myorg/myrepo.git
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
```

---

## 6. RBAC Configuration and Troubleshooting

### Built-In Roles

ArgoCD has two pre-defined roles:
- `role:readonly` - read-only access to all resources
- `role:admin` - unrestricted access to all resources

### RBAC Policy Model

```
# Assign a role to a user or group
g, <user/group>, <role>

# Assign a permission policy
p, <role/user/group>, <resource>, <action>, <object>, <effect>
```

**Resources and valid actions:**

| Resource | get | create | update | delete | sync | action | override |
|----------|-----|--------|--------|--------|------|--------|----------|
| applications | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| applicationsets | ✅ | ✅ | ✅ | ✅ | - | - | - |
| clusters | ✅ | ✅ | ✅ | ✅ | - | - | - |
| projects | ✅ | ✅ | ✅ | ✅ | - | - | - |
| repositories | ✅ | ✅ | ✅ | ✅ | - | - | - |
| accounts | ✅ | - | ✅ | - | - | - | - |
| logs | ✅ | - | - | - | - | - | - |
| exec | - | ✅ | - | - | - | - | - |
| extensions | - | - | - | - | - | - | ✅ (invoke) |

### argocd-rbac-cm Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    # Assign admin role to admin group
    g, admin-group, role:admin

    # Read-only role for all applications
    p, role:readonly, applications, get, */*, allow
    p, role:readonly, clusters, get, *, allow
    p, role:readonly, repositories, get, *, allow

    # Custom developer role - sync own project's apps
    p, role:developer, applications, get, my-project/*, allow
    p, role:developer, applications, sync, my-project/*, allow
    p, role:developer, logs, get, my-project/*, allow

    # SSO group mapping
    g, my-sso-group@company.com, role:developer

  # Enable glob matching (default)
  policy.matchMode: glob
```

### Fine-Grained Resource Permissions

Allow update on app but restrict sub-resources:
```
# Allow updating the application itself
p, example-user, applications, update, default/prod-app, allow
# Deny updating any sub-resources
p, example-user, applications, update/*, default/prod-app, deny
```

Allow delete of specific resource kind only:
```
# Deny deleting the application
p, example-user, applications, delete, default/prod-app, deny
# Allow deleting only Pods
p, example-user, applications, delete/*/Pod/*/*, default/prod-app, allow
```

### Application-Specific Policies in AppProject

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: my-project
  namespace: argocd
spec:
  roles:
    - name: developer
      description: Developer role for my-project
      policies:
        - p, proj:my-project:developer, applications, get, my-project/*, allow
        - p, proj:my-project:developer, applications, sync, my-project/*, allow
        - p, proj:my-project:developer, logs, get, my-project/*, allow
      groups:
        - my-dev-team
```

### Validating RBAC Policies

```bash
# Validate the RBAC policy
argocd admin settings rbac validate --policy-file /path/to/policy.csv

# Test a specific policy
argocd admin settings rbac can <role/user> <action> <resource> [flags]
# Example:
argocd admin settings rbac can role:developer sync applications my-project/my-app
```

### Troubleshooting RBAC

If a user cannot perform an action:
1. Verify their SSO group claims are populated (check with `argocd account get-user-info`)
2. Confirm `policy.default` is not too restrictive
3. Note: `deny` effect takes precedence over `allow` - order of policies does NOT matter
4. Groups must have a role assigned via `g, <group>, <role>` before `p, <group>,...` policies apply
5. Default policies cannot be blocked by a `deny` rule - users always get at minimum `policy.default` permissions

---

## 7. Performance Tuning

### argocd-repo-server Tuning

```yaml
# Deployment env vars and args
containers:
  - name: argocd-repo-server
    args:
      # Limit concurrent manifest generations to avoid OOM
      - --parallelismlimit=10
      # Reduce cache expiration for frequently changing repos
      - --repo-cache-expiration=1h
    env:
      # Retry git ls-remote failures
      - name: ARGOCD_GIT_ATTEMPTS_COUNT
        value: "5"
      # Increase timeout for slow manifest generation tools
      - name: ARGOCD_EXEC_TIMEOUT
        value: "2m30s"
      # Enable gRPC metrics (expensive but useful for troubleshooting)
      - name: ARGOCD_ENABLE_GRPC_TIME_HISTOGRAM
        value: "true"
```

**Disk space:** Mount a persistent volume if many repos or large repos:
```yaml
volumeMounts:
  - name: repo-cache
    mountPath: /tmp
volumes:
  - name: repo-cache
    emptyDir:
      sizeLimit: 10Gi
```

### argocd-application-controller Tuning

```yaml
containers:
  - name: argocd-application-controller
    args:
      # Increase queue processors for large installations
      - --status-processors=50     # default: 20; use 50 for ~1000 apps
      - --operation-processors=25  # default: 10; use 25 for ~1000 apps
      # Increase timeout if repo-server is slow
      - --repo-server-timeout-seconds=300
    env:
      # Number of controller replicas (for sharding)
      - name: ARGOCD_CONTROLLER_REPLICAS
        value: "2"
      # Enable batch event processing for large clusters
      - name: ARGOCD_CLUSTER_CACHE_BATCH_EVENTS_PROCESSING
        value: "true"
      - name: ARGOCD_CLUSTER_CACHE_EVENTS_PROCESSING_INTERVAL
        value: "100ms"
      # Split large app trees across multiple Redis keys
      - name: ARGOCD_APPLICATION_TREE_SHARD_SIZE
        value: "100"
      # Buffer size for list operations (fix "continue parameter too old" errors)
      - name: ARGOCD_CLUSTER_CACHE_LIST_PAGE_BUFFER_SIZE
        value: "10"
```

**Reconciliation interval** in `argocd-cm`:
```yaml
data:
  # Git polling interval
  timeout.reconciliation: 180s
  timeout.reconciliation.jitter: 60s
```

### argocd-server Tuning

```yaml
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: argocd-server
          env:
            - name: ARGOCD_API_SERVER_REPLICAS
              value: "3"
            # Increase gRPC message size for 3000+ app instances
            - name: ARGOCD_GRPC_MAX_SIZE_MB
              value: "400"
```

### Monorepo Optimizations

**Use fully qualified Git references** (much faster for large repos):
```yaml
spec:
  source:
    # Less efficient - requires iterating all refs
    # targetRevision: main

    # More efficient - directly identifies reference type
    targetRevision: refs/heads/main
    # For tags:
    # targetRevision: refs/tags/v1.0.0
```

**Manifest Paths Annotation** to limit what gets copied per app:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/manifest-generate-paths: .
```

**Enable concurrent processing** in `argocd-cm`:
```yaml
data:
  server.allow.concurrent.requests: "true"
```

**Rate Limiting Application Reconciliations** in `argocd-cm`:
```yaml
data:
  # Global rate limit
  server.application.sharding.algorithm: consistent-hashing

  # Rate limit for reconciliations
  controller.app.resync.jitter: 60s
```

### CPU/Memory Profiling

Enable pprof endpoints for profiling:
```bash
# Port-forward to repo-server
kubectl port-forward svc/argocd-repo-server 6060:6060 -n argocd

# Get CPU profile
curl -sK http://localhost:6060/debug/pprof/profile?seconds=30 > profile.out
go tool pprof profile.out
```

### Shallow Clone

Enable shallow clone to speed up large repo clones:
```yaml
# In argocd-cm
data:
  server.allow.concurrent.requests: "true"
```

Or set per-repo via `ARGOCD_GIT_MODULES_ENABLED=false` to disable submodule fetching.

---

## 8. High Availability Setup

### HA Installation

Requires at least 3 nodes due to pod anti-affinity rules:
```bash
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/<version>/manifests/ha/install.yaml
```

### Redis HA

ArgoCD HA uses Redis Sentinel (3 servers/sentinels pre-configured). Redis is a disposable cache only - it can be safely rebuilt without data loss. All persistent state is in Kubernetes etcd.

### Controller Sharding

For large installations managing many clusters:
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: argocd-application-controller
spec:
  replicas: 2    # Number of shards
  template:
    spec:
      containers:
        - name: argocd-application-controller
          env:
            - name: ARGOCD_CONTROLLER_REPLICAS
              value: "2"
          args:
            # Sharding algorithm options:
            # legacy         - UID-based (non-uniform, default)
            # round-robin    - equal distribution (experimental)
            # consistent-hashing - bounded loads (experimental, recommended)
            - --sharding-method=consistent-hashing
```

Or configure via `argocd-cmd-params-cm`:
```yaml
data:
  controller.sharding.algorithm: consistent-hashing
```

**Manually assign a cluster to a shard:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mycluster-secret
  labels:
    argocd.argoproj.io/secret-type: cluster
stringData:
  shard: "1"
  name: mycluster.example.com
  server: https://mycluster.example.com
  config: |
    {
      "bearerToken": "<authentication token>",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64 encoded certificate>"
      }
    }
```

### Application Sync Timeout and Jitter

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  # Polling interval with jitter to spread load
  timeout.reconciliation: 180s
  timeout.reconciliation.jitter: 60s
```

### HTTP Request Retry Strategy

Configure via `argocd-cmd-params-cm`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
data:
  # Number of retries
  controller.k8sclient.retry.max: "3"
  # Initial backoff
  controller.k8sclient.retry.base.backoff: "100ms"
  # Conditions that won't be retried (e.g., auth errors)
  controller.k8sclient.retry.codes: "429,500,502,503,504"
```

---

## 9. Metrics and Monitoring

### Metric Endpoints

| Component | Endpoint |
|-----------|----------|
| Application Controller | `argocd-metrics:8082/metrics` |
| API Server | `argocd-server-metrics:8083/metrics` |
| Repo Server | `argocd-repo-server:8084/metrics` |
| ApplicationSet Controller | `argocd-applicationset-controller:8080/metrics` |

### Application Controller Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `argocd_app_info` | gauge | Application info with sync_status and health_status labels |
| `argocd_app_condition` | gauge | Application conditions (errors, warnings) |
| `argocd_app_reconcile` | histogram | Reconciliation duration in seconds |
| `argocd_app_sync_total` | counter | Application sync history count |
| `argocd_app_sync_duration_seconds_total` | counter | Sync duration in seconds |
| `argocd_app_k8s_request_total` | counter | Kubernetes requests per application |
| `argocd_cluster_api_resource_objects` | gauge | K8s resource objects in cache |
| `argocd_cluster_connection_status` | gauge | Cluster connection status |
| `argocd_redis_request_total` | counter | Redis request count |
| `argocd_kubectl_exec_pending` | gauge | Pending kubectl executions |

### Exposing Application Labels as Metrics

By default disabled. To enable specific labels as Prometheus metrics:
```yaml
containers:
  - command:
      - argocd-application-controller
      - --metrics-application-labels
      - team-name
      - --metrics-application-labels
      - business-unit
```

Result:
```
argocd_app_labels{label_business_unit="bu-id-1",label_team_name="my-team",name="my-app-1",namespace="argocd",project="important-project"} 1
```

### Exposing Application Conditions as Metrics

```yaml
containers:
  - command:
      - argocd-application-controller
      - --metrics-application-conditions
      - OrphanedResourceWarning
      - --metrics-application-conditions
      - ExcludedResourceWarning
```

### Exposing Cluster Labels as Metrics

```yaml
containers:
  - command:
      - argocd-application-controller
      - --metrics-cluster-labels
      - team-name
      - --metrics-cluster-labels
      - environment
```

### API Server Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `argocd_login_request_total` | counter | Login request count |
| `grpc_server_handled_total` | counter | gRPC RPCs completed |
| `argocd_proxy_extension_request_total` | counter | Proxy extension requests |

Enable gRPC time histograms:
```yaml
env:
  - name: ARGOCD_ENABLE_GRPC_TIME_HISTOGRAM
    value: "true"
```

### Metrics Cache Expiration

For installations with many app/project creation/deletions, clean up stale metrics:
```bash
# Application controller flag
--metrics-cache-expiration=24h0m0s
```

### Prometheus Operator Integration

ArgoCD provides ServiceMonitor resources. Install with Prometheus Operator:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-metrics
  endpoints:
    - port: metrics
  namespaceSelector:
    matchNames:
      - argocd
```

### Key Prometheus Alert Rules

```yaml
groups:
  - name: argocd
    rules:
      - alert: ArgoCDAppOutOfSync
        expr: argocd_app_info{sync_status="OutOfSync"} == 1
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "ArgoCD App {{ $labels.name }} is OutOfSync"

      - alert: ArgoCDAppNotHealthy
        expr: argocd_app_info{health_status!="Healthy"} == 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "ArgoCD App {{ $labels.name }} is {{ $labels.health_status }}"

      - alert: ArgoCDSyncFailed
        expr: argocd_app_sync_total{phase="Failed"} > 0
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "ArgoCD sync failed for {{ $labels.name }}"

      - alert: ArgoCDRepoServerHighLatency
        expr: histogram_quantile(0.99, sum(rate(argocd_app_reconcile_bucket[5m])) by (le)) > 60
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "ArgoCD reconciliation P99 latency > 60s"
```

---

## 10. Upgrading ArgoCD

### Upgrade Strategy

ArgoCD uses semver-like versioning:
- **Patch release** (e.g., v2.5.1 → v2.5.3): No breaking changes, safe to apply directly
- **Minor release** (e.g., v2.3 → v2.5): Check upgrading notes for each minor version in between
- **Major release** (e.g., v2.x → v3.x): Backward-incompatible changes, read upgrade guide carefully

### Pre-Upgrade Steps

1. **Read the release notes** for each version between current and target
2. **Take a backup** using the disaster recovery guide
3. **Test in staging** environment first

### Upgrade Command

**Non-HA installation:**
```bash
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/<version>/manifests/install.yaml
```

**HA installation:**
```bash
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/<version>/manifests/ha/install.yaml
```

Note: `--server-side --force-conflicts` flags are required because some CRDs exceed the annotation size limit for client-side apply.

### Important: Apply Full Manifests

Always apply the complete manifest set, not just change the image tag. Manifests may include important parameter modifications and ConfigMap changes.

### Zero-Downtime Upgrades

For `argocd-server`, increase replicas before upgrading:
```yaml
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: argocd-server
          env:
            - name: ARGOCD_API_SERVER_REPLICAS
              value: "3"
```

### Skipping Minor Versions

If skipping minor versions (e.g., v2.3 → v2.6), read the upgrade notes for each intermediate version:
- v2.3 to v2.4
- v2.4 to v2.5
- v2.5 to v2.6

---

## 11. Helm Chart Management

### Basic Helm Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sealed-secrets
  namespace: argocd
spec:
  project: default
  source:
    chart: sealed-secrets
    repoURL: https://bitnami-labs.github.io/sealed-secrets
    targetRevision: 1.16.1
    helm:
      releaseName: sealed-secrets
  destination:
    server: "https://kubernetes.default.svc"
    namespace: kubeseal
```

### OCI Helm Chart

```yaml
spec:
  source:
    chart: nginx
    repoURL: registry-1.docker.io/bitnamicharts  # Note: no oci:// prefix
    targetRevision: 15.9.0
```

### Values Files

```yaml
spec:
  source:
    helm:
      valueFiles:
        - values-production.yaml
        - values-secrets.yaml
      # Ignore missing files instead of erroring
      ignoreMissingValueFiles: true
```

**Glob patterns in value files (v2.9+):**
```yaml
spec:
  source:
    helm:
      valueFiles:
        - values/*.yaml           # Lexical order within directory
        - envs/**/*.yaml          # Recursive matching
        - envs/$ARGOCD_APP_NAME/*.yaml  # Build env variable substitution
```

**Important:** Lexical order determines merge precedence. Files sorted later have higher precedence.

```bash
# CLI: always single-quote glob patterns
argocd app set myapp --values 'envs/*.yaml'
```

### Inline Values

```yaml
spec:
  source:
    helm:
      # Preferred: structured YAML object
      valuesObject:
        ingress:
          enabled: true
          hosts:
            - mydomain.example.com

      # Alternative: string block
      values: |
        ingress:
          enabled: true
          hosts:
            - mydomain.example.com
```

### Helm Parameters

```yaml
spec:
  source:
    helm:
      parameters:
        - name: "service.type"
          value: LoadBalancer
        - name: "replicaCount"
          value: "3"
```

CLI:
```bash
argocd app set helm-guestbook -p service.type=LoadBalancer
```

### Value Precedence (highest to lowest)

```
parameters > valuesObject > values > valueFiles > helm repo values.yaml
```

When multiple `valueFiles`: last file listed wins.
When multiple `parameters` with same key: last one wins.

### Helm Release Name

```yaml
spec:
  source:
    helm:
      releaseName: my-custom-release-name
```

Warning: Overriding the release name can break selectors that use `app.kubernetes.io/instance` label (which ArgoCD sets to the Application name). Configure `application.instanceLabelKey` in `argocd-cm` if needed.

### Helm Hooks Mapping

| Helm Annotation | ArgoCD Equivalent |
|-----------------|-------------------|
| `helm.sh/hook: pre-install` | `argocd.argoproj.io/hook: PreSync` |
| `helm.sh/hook: pre-upgrade` | `argocd.argoproj.io/hook: PreSync` |
| `helm.sh/hook: post-install` | `argocd.argoproj.io/hook: PostSync` |
| `helm.sh/hook: post-upgrade` | `argocd.argoproj.io/hook: PostSync` |
| `helm.sh/hook: pre-delete` | `argocd.argoproj.io/hook: PreDelete` |
| `helm.sh/hook: post-delete` | `argocd.argoproj.io/hook: PostDelete` |
| `helm.sh/hook-delete-policy` | `argocd.argoproj.io/hook-delete-policy` |
| `helm.sh/hook-weight` | `argocd.argoproj.io/sync-wave` |
| `helm.sh/resource-policy: keep` | `argocd.argoproj.io/sync-options: Delete=false` |

**Important:** If any ArgoCD hooks are defined, ALL Helm hooks are ignored.

ArgoCD cannot distinguish install from upgrade - every operation is a "sync". Both `pre-install` and `pre-upgrade` run on every sync.

**Hook best practices:**
- Make hooks idempotent
- Annotate `pre-install`/`post-install` with `helm.sh/hook-weight: "-1"` to run before upgrade hooks
- Annotate `pre-upgrade`/`post-upgrade` with `helm.sh/hook-delete-policy: before-hook-creation`

### Helm Specific Options

```yaml
spec:
  source:
    helm:
      version: v3                    # Force Helm version
      passCredentials: true          # Pass credentials to all domains
      skipCrds: true                 # Skip CRD installation
      skipSchemaValidation: true     # Skip values.schema.json validation
      skipTests: true                # Skip test manifests
      fileParameters:                # --set-file support
        - name: some.key
          path: path/to/file.ext
```

### Multiple Sources (Cross-Repo Values)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  sources:
    - repoURL: https://charts.example.com
      chart: my-chart
      targetRevision: 1.0.0
      helm:
        valueFiles:
          - $values/helm/values.yaml
    - repoURL: https://github.com/myorg/my-configs
      targetRevision: HEAD
      ref: values
```

### Helm Plugins

Using initContainers for custom Helm plugins (e.g., helm-gcs):
```yaml
repoServer:
  initContainers:
    - name: helm-gcp-authentication
      image: alpine/helm:3.16.1
      volumeMounts:
        - name: helm-working-dir
          mountPath: /helm-working-dir
        - name: gcp-credentials
          mountPath: /gcp
      env:
        - name: HELM_CACHE_HOME
          value: /helm-working-dir
        - name: HELM_CONFIG_HOME
          value: /helm-working-dir
        - name: HELM_DATA_HOME
          value: /helm-working-dir
      command: ["/bin/sh", "-c"]
      args:
        - apk --no-cache add curl;
          helm plugin install https://github.com/hayorov/helm-gcs.git;
          helm repo add my-gcs-repo gs://my-private-helm-gcs-repository;
          chmod -R 777 $HELM_DATA_HOME;
```

---

## 12. Kustomize Configuration

### Basic Kustomize Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kustomize-example
spec:
  project: default
  source:
    path: overlays/production   # Point to overlay directory
    repoURL: 'https://github.com/myorg/myrepo'
    targetRevision: HEAD
  destination:
    namespace: production
    server: 'https://kubernetes.default.svc'
```

### Kustomize Options

```yaml
spec:
  source:
    kustomize:
      # Override namePrefix/nameSuffix
      namePrefix: staging-
      nameSuffix: -v1

      # Image overrides
      images:
        - name: myapp
          newTag: "1.2.3"
        - name: myapp
          newName: myrepo/myapp
          newTag: "1.2.3"

      # Replica overrides
      replicas:
        - name: my-deployment
          count: 3

      # Common labels and annotations
      commonLabels:
        env: staging
        team: backend
      commonAnnotations:
        deployment.company.com/version: "1.2.3"

      # Namespace override (preferred over spec.destination.namespace for CRBs)
      namespace: my-namespace

      # Force labels (override existing)
      forceCommonLabels: true
      forceCommonAnnotations: true

      # Enable env variable substitution in annotations
      commonAnnotationsEnvsubst: true
```

### Inline Patches

Apply patches directly in the Application spec without modifying kustomization.yaml:

```yaml
spec:
  source:
    kustomize:
      patches:
        - target:
            kind: Deployment
            name: guestbook-ui
          patch: |-
            - op: replace
              path: /spec/template/spec/containers/0/ports/0/containerPort
              value: 443
        - target:
            kind: Service
            labelSelector: "app=guestbook"
          patch: |-
            - op: add
              path: /metadata/annotations/service.beta.kubernetes.io~1aws-load-balancer-type
              value: nlb
```

### Kustomize Components

```yaml
spec:
  source:
    kustomize:
      components:
        - ../security-component
        - ../monitoring-component
      ignoreMissingComponents: true
```

### Namespace Conflict with ClusterRoleBindings

If resources lack namespace and get errors like:
```
ClusterRoleBinding.rbac.authorization.k8s.io "example" is invalid: subjects[0].namespace: Required value
```
Use `spec.source.kustomize.namespace` instead of `spec.destination.namespace`:
```yaml
spec:
  source:
    kustomize:
      namespace: my-namespace  # Kustomize sets it on all resources
  destination:
    namespace: my-namespace
```

### Custom Kustomize Versions

```yaml
# argocd-cm
data:
  kustomize.path.v3.5.4: /custom-tools/kustomize_3_5_4

# Application spec
spec:
  source:
    kustomize:
      version: v3.5.4
```

### Kustomize Build Options

```yaml
# argocd-cm
data:
  kustomize.buildOptions: --load-restrictor LoadRestrictionsNone
  kustomize.buildOptions.v4.4.0: --output /tmp
  # Enable helm chart rendering via kustomize
  kustomize.buildOptions: --enable-helm
```

### Kustomizing Helm Charts via Kustomize

Two options:
1. Create a custom ArgoCD CMP plugin
2. Enable globally in `argocd-cm`:
```yaml
data:
  kustomize.buildOptions: --enable-helm
```

### ApplicationSet with Inline Kustomize Patches

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: external-dns
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - clusters: {}
  template:
    metadata:
      name: 'external-dns'
    spec:
      project: default
      source:
        repoURL: https://github.com/kubernetes-sigs/external-dns/
        targetRevision: v0.14.0
        path: kustomize
        kustomize:
          patches:
            - target:
                kind: Deployment
                name: external-dns
              patch: |-
                - op: add
                  path: /spec/template/spec/containers/0/args/3
                  value: --txt-owner-id={{.name}}
      destination:
        name: '{{.name}}'
        namespace: default
```

---

## 13. Automated Sync Policy

### Basic Auto Sync

```yaml
spec:
  syncPolicy:
    automated: {}
```

CLI:
```bash
argocd app set <appname> --sync-policy automated
```

### Auto Sync with Pruning

By default, auto sync does NOT delete resources removed from Git. Enable pruning:
```yaml
spec:
  syncPolicy:
    automated:
      prune: true
```

### Prevent Auto Sync When No Resources Remain

Safety guard against accidentally pruning all resources:
```yaml
spec:
  syncPolicy:
    automated:
      prune: true
      allowEmpty: false  # Default: false, prevents pruning to empty state
```

### Self-Healing

Automatically sync when live cluster state deviates from Git:
```yaml
spec:
  syncPolicy:
    automated:
      selfHeal: true
```

Self-heal timeout is 5 seconds by default. Change via `--self-heal-timeout-seconds` flag on the controller.

### Auto Sync Retry

```yaml
spec:
  syncPolicy:
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
    automated:
      selfHeal: true
```

### Automated Sync Semantics

- Only triggered when application is `OutOfSync` (not when `Synced` or `Error`)
- Only one sync per unique commit SHA + parameters combination
- Failed syncs will not be retried automatically unless `selfHeal: true`
- Auto sync will not attempt if the same commit already failed
- Rollback is not possible with auto sync enabled

### Temporarily Disabling Auto Sync

For standalone apps:
```bash
argocd app set <appname> --sync-policy none
# Or
argocd app set <appname> --sync-policy manual
```

For ApplicationSet-managed apps, use `Controlling Resource Modification` in the ApplicationSet spec (individual app changes are overwritten by the ApplicationSet controller).

---

## 14. Sync Options Reference

### Available Sync Options

```yaml
spec:
  syncPolicy:
    syncOptions:
      # Do not prune this resource (also via annotation)
      - Prune=false
      # Require confirmation before pruning
      - Prune=confirm
      # Do not delete resource when app is deleted
      - Delete=false
      # Require confirmation before deletion
      - Delete=confirm
      # Skip kubectl validation
      - Validate=false
      # Skip dry run for missing CRD types
      - SkipDryRunOnMissingResource=true
      # Only sync out-of-sync resources (performance)
      - ApplyOutOfSyncOnly=true
      # Prune only after all other resources are healthy
      - PruneLast=true
      # Use kubectl replace instead of apply
      - Replace=true
      # Force delete and recreate
      - Force=true
      # Use kubectl apply --server-side
      - ServerSideApply=true
      # Disable client-side to server-side migration
      - ClientSideApplyMigration=false
      # Fail sync if a resource is managed by another app
      - FailOnSharedResource=true
      # Apply ignoreDifferences during sync (not just compare)
      - RespectIgnoreDifferences=true
      # Create destination namespace if missing
      - CreateNamespace=true
      # Prune deletion propagation policy
      - PrunePropagationPolicy=foreground  # background, foreground, orphan
```

### Per-Resource Annotations

```yaml
metadata:
  annotations:
    # Multiple options concatenated with comma
    argocd.argoproj.io/sync-options: Prune=false,Validate=false
    # Prevent pruning
    argocd.argoproj.io/sync-options: Prune=false
    # Keep resource when app is deleted
    argocd.argoproj.io/sync-options: Delete=false
    # Use server-side apply for this resource only
    argocd.argoproj.io/sync-options: ServerSideApply=true
    # Use replace for large resources
    argocd.argoproj.io/sync-options: Replace=true
```

### Namespace Creation with Metadata

```yaml
spec:
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
    managedNamespaceMetadata:
      labels:
        pod-security.kubernetes.io/enforce: baseline
      annotations:
        team: backend
```

---

## 15. ApplicationSet Patterns

### Cluster Generator

Deploys to all registered clusters:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - clusters: {}  # All clusters
  template:
    metadata:
      name: '{{.name}}-guestbook'
    spec:
      project: "my-project"
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps/
        targetRevision: HEAD
        path: guestbook
      destination:
        server: '{{.server}}'
        namespace: guestbook
      syncPolicy:
        syncOptions:
          - CreateNamespace=true
```

**With label selector** (filter clusters):
```yaml
generators:
  - clusters:
      selector:
        matchLabels:
          environment: production
        matchExpressions:
          - key: region
            operator: In
            values: ["us-east-1", "eu-west-1"]
```

**Exclude local cluster:**
```yaml
generators:
  - clusters:
      selector:
        matchLabels:
          argocd.argoproj.io/secret-type: cluster
```

**Pass additional values:**
```yaml
generators:
  - clusters:
      selector:
        matchLabels:
          type: staging
      values:
        revision: HEAD
  - clusters:
      selector:
        matchLabels:
          type: production
      values:
        revision: stable
```

**Dynamic K8s version labeling:**
```yaml
# Enable auto-labeling
# metadata.labels.argocd.argoproj.io/auto-label-cluster-info: "true"

generators:
  - clusters:
      selector:
        matchLabels:
          argocd.argoproj.io/kubernetes-version: v1.28.1
```

### Git Directory Generator

Auto-discover apps from Git repository structure:
```yaml
spec:
  generators:
    - git:
        repoURL: https://github.com/myorg/gitops-repo.git
        revision: HEAD
        directories:
          - path: apps/*       # Include all subdirectories of apps/
          - path: apps/legacy  # Exclude legacy directory
            exclude: true
  template:
    metadata:
      name: '{{.path.basename}}'
    spec:
      source:
        path: '{{.path.path}}'
        repoURL: https://github.com/myorg/gitops-repo.git
        targetRevision: HEAD
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.path.basename}}'
```

**Available path parameters:**
- `{{.path.path}}` - full path
- `{{.path.basename}}` - rightmost directory name
- `{{.path.basenameNormalized}}` - basename with invalid chars replaced by `-`
- `{{index .path.segments n}}` - path split into array

### Git File Generator

Use JSON/YAML config files to parameterize deployments:
```yaml
spec:
  generators:
    - git:
        repoURL: https://github.com/myorg/gitops-repo.git
        revision: HEAD
        files:
          - path: "cluster-config/**/config.json"
          # Exclude specific file
          # - path: "cluster-config/dev/config.json"
          #   exclude: true
  template:
    metadata:
      name: '{{.cluster.name}}'
    spec:
      destination:
        server: '{{.cluster.address}}'
        namespace: guestbook
```

Example `config.json`:
```json
{
  "cluster": {
    "owner": "team@company.com",
    "name": "production",
    "address": "https://1.2.3.4"
  },
  "environment": "production"
}
```

### Matrix Generator

Combine two generators (cartesian product):
```yaml
spec:
  generators:
    - matrix:
        generators:
          # Git discovers apps
          - git:
              repoURL: https://github.com/myorg/gitops-repo.git
              revision: HEAD
              directories:
                - path: apps/*
          # Cluster generator for all target clusters
          - clusters:
              selector:
                matchLabels:
                  argocd.argoproj.io/secret-type: cluster
  template:
    metadata:
      name: '{{.path.basename}}-{{.name}}'
    spec:
      source:
        path: '{{.path.path}}'
        repoURL: https://github.com/myorg/gitops-repo.git
        targetRevision: HEAD
      destination:
        server: '{{.server}}'
        namespace: '{{.path.basename}}'
```

**Note:** If both child generators are Git generators, use `pathParamPrefix` to avoid conflicts:
```yaml
generators:
  - git:
      pathParamPrefix: myRepo
      ...
```

### Using Parameters from One Child Generator in Another

```yaml
generators:
  - matrix:
      generators:
        # First generator provides cluster environment label
        - git:
            files:
              - path: "cluster-config/**/config.json"
        # Second generator selects clusters matching first generator's value
        - clusters:
            selector:
              matchLabels:
                kubernetes.io/environment: '{{.path.basename}}'  # From first generator
```

### List Generator

Simple list of values:
```yaml
spec:
  generators:
    - list:
        elements:
          - cluster: staging
            url: https://1.2.3.4
          - cluster: production
            url: https://2.4.6.8
  template:
    metadata:
      name: '{{.cluster}}-app'
    spec:
      destination:
        server: '{{.url}}'
```

### ApplicationSet Security Considerations

**Danger:** If the `project` field is templated, non-admin users can create Applications under any project.

```yaml
# SAFE: static project field
spec:
  template:
    spec:
      project: my-project  # Not templated

# UNSAFE for multi-tenant setups:
# project: {{.values.project}}  # Never template this unless git is admin-controlled
```

---

## 16. App of Apps Pattern

Create a "root" Application that manages other ArgoCD Applications. Each "child" Application is itself a Git-tracked Kubernetes manifest.

### Root Application

```yaml
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
    repoURL: https://github.com/myorg/gitops-root
    targetRevision: HEAD
    path: applications  # Directory containing child Application manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Child Application (in `/applications/` directory)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/my-app
    targetRevision: HEAD
    path: kubernetes/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Cascade Deletion

The `resources-finalizer.argocd.argoproj.io` finalizer on the root app ensures child apps are deleted when the root is deleted. Add it to child apps too for full cascade deletion.

### App of Apps vs ApplicationSet

| Feature | App of Apps | ApplicationSet |
|---------|-------------|----------------|
| Dynamic generation | No (static manifests) | Yes (from generators) |
| Cluster generator | No | Yes |
| Git structure discovery | No | Yes |
| Direct Git to App | Yes | Yes |
| Learning curve | Low | Medium |
| Best for | Static multi-app | Dynamic multi-cluster/multi-app |

---

## 17. Multi-Cluster Management

### Adding a Cluster

```bash
# Using kubectl context
argocd cluster add my-cluster-context

# With explicit server URL
argocd cluster add my-cluster-context --name my-cluster

# In-cluster (for the cluster where ArgoCD is installed)
argocd cluster add my-cluster-context --in-cluster
```

### Declarative Cluster Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: prod-cluster-secret
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: production
    region: us-east-1
type: Opaque
stringData:
  name: production-cluster
  server: https://my-cluster.example.com
  config: |
    {
      "bearerToken": "<token>",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64-ca-cert>"
      }
    }
```

### Listing and Managing Clusters

```bash
argocd cluster list
argocd cluster get https://my-cluster.example.com
argocd cluster rotate-auth https://my-cluster.example.com
argocd cluster rm https://my-cluster.example.com
```

### ApplicationSet for Multi-Cluster Deployment

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infrastructure
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - clusters:
        selector:
          matchLabels:
            argocd.argoproj.io/secret-type: cluster
        values:
          environment: '{{index .metadata.labels "environment"}}'
          region: '{{index .metadata.labels "region"}}'
  template:
    metadata:
      name: 'infrastructure-{{.name}}'
    spec:
      project: infrastructure
      source:
        repoURL: https://github.com/myorg/infrastructure
        targetRevision: HEAD
        path: 'clusters/{{.values.environment}}'
      destination:
        server: '{{.server}}'
        namespace: infrastructure
```

### Dynamic Cluster Distribution

ArgoCD supports dynamic cluster assignment across controller shards. To enable:
```yaml
# argocd-cmd-params-cm
data:
  controller.sharding.algorithm: consistent-hashing
  # Dynamic distribution re-balances when clusters are added/removed
  controller.dynamic.cluster.distribution.enabled: "true"
```

---

## 18. Best Practices

### Separating Config from Source Code

**Strongly recommended:** Use separate Git repositories for:
1. Application source code (CI builds this)
2. Kubernetes manifests / ArgoCD config (ArgoCD deploys this)

**Reasons:**
- Clean separation of concerns
- Cleaner audit log without development noise
- Different access controls (developers can't push to production config repo)
- Prevents infinite CI loop (committing manifests to source repo triggers a new build)

### Leaving Room for Imperativeness

Don't track everything in Git. Example - HPA-managed replicas:
```yaml
# Do NOT set replicas if HPA manages it
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  # replicas: 1  <-- omit this if HPA controls replicas
  template:
    ...
```

Use `ignoreDifferences` for fields managed outside ArgoCD:
```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
```

### Ensuring Manifests Are Truly Immutable

When using Kustomize remote bases or Helm, pin to specific versions:

```yaml
# BAD: remote base at HEAD is not stable
resources:
  - github.com/argoproj/argo-cd//manifests/cluster-install

# GOOD: pin to specific tag
resources:
  - github.com/argoproj/argo-cd//manifests/cluster-install?ref=v2.9.0
```

For Helm:
```yaml
spec:
  source:
    chart: my-chart
    targetRevision: 1.2.3  # Always pin to exact version, not a range
```

### Application Project Isolation

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: my-project
spec:
  description: My team's project
  sourceRepos:
    - 'https://github.com/myorg/*'
  destinations:
    - namespace: 'my-team-*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
  namespaceResourceBlacklist:
    - group: ''
      kind: ResourceQuota
```

### Resource Tracking

ArgoCD tracks resources using the `app.kubernetes.io/instance` label by default. Change tracking method if label conflicts arise:

```yaml
# argocd-cm
data:
  # Options: label (default), annotation, annotation+label
  application.resourceTrackingMethod: annotation
```

### Sync Waves for Ordered Deployment

```yaml
# Deploy infrastructure first (wave -1), then apps (wave 0), then config (wave 1)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"  # Deploys first
```

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # Deploys last
```

### Git Webhook for Faster Sync

Instead of polling every 3 minutes, use webhooks:
```bash
# Configure webhook in GitHub/GitLab pointing to:
https://<argocd-server>/api/webhook
```

Webhook payload URL format and shared secrets are configured in `argocd-secret`.

---

## 19. Operator Troubleshooting Tools

### argocd admin Subcommands

```bash
# Validate settings
argocd admin settings validate

# Test diffing customization
argocd admin settings resource-overrides ignore-differences ./deploy.yaml \
  --argocd-cm-path ./argocd-cm.yaml

# Test health assessment
argocd admin settings resource-overrides health ./deploy.yaml \
  --argocd-cm-path ./argocd-cm.yaml

# Test resource action
argocd admin settings resource-overrides run-action /tmp/deploy.yaml restart \
  --argocd-cm-path /private/tmp/argocd-cm.yaml

# List available actions for a resource
argocd admin settings resource-overrides list-actions /tmp/deploy.yaml \
  --argocd-cm-path /private/tmp/argocd-cm.yaml
```

### Cluster Credentials Troubleshooting

```bash
# 1. SSH into the application-controller pod
kubectl exec -n argocd -it \
  $(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-application-controller \
    -o jsonpath='{.items[0].metadata.name}') -- bash

# 2. Export kubeconfig from Secret
argocd admin cluster kubeconfig https://<api-server-url> /tmp/kubeconfig --namespace argocd

# 3. Test connectivity with verbose output
export KUBECONFIG=/tmp/kubeconfig
kubectl get pods -v 9
```

### Common Log Locations

```bash
# Application controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f

# Repo server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -f

# API server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f

# ApplicationSet controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller -f
```

### Debug Application Reconciliation

```bash
# Check application controller queue metrics
kubectl port-forward svc/argocd-metrics 8082:8082 -n argocd
curl http://localhost:8082/metrics | grep argocd_app_reconcile

# Check repo server latency
kubectl port-forward svc/argocd-repo-server-metrics 8084:8084 -n argocd
curl http://localhost:8084/metrics | grep argocd_git_request_total

# Force an application to refresh immediately
argocd app get <app-name> --hard-refresh

# Enable verbose logging (temporary)
kubectl set env deployment/argocd-application-controller -n argocd \
  ARGOCD_LOG_LEVEL=debug
```

### Notification Troubleshooting

```bash
# Check notification controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-notifications-controller -f

# Test a notification template
argocd admin notifications template notify \
  app-sync-status <app-name> \
  --recipient slack:my-channel

# Trigger test notification
argocd admin notifications trigger run on-sync-failed <app-name>
```

### Useful Debug Commands

```bash
# List all applications with sync status
argocd app list

# Get application details including conditions
argocd app get <app-name>

# Show last sync result
argocd app get <app-name> --show-operation

# Show resource tree
argocd app resources <app-name>

# Show diff
argocd app diff <app-name>

# Manually sync
argocd app sync <app-name> --prune

# Rollback to previous version
argocd app rollback <app-name> <history-id>

# Delete application (without deleting resources)
argocd app delete <app-name> --cascade=false

# Export application as YAML
argocd app get <app-name> -o yaml > app.yaml

# List history
argocd app history <app-name>
```

---

## Quick Reference: Common Error Messages and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `context deadline exceeded` | Manifest generation timeout | Increase `--repo-server-timeout-seconds` |
| `x509: certificate signed by unknown authority` | Untrusted TLS cert | `argocd cert add-tls <host> --from /path/to/ca.pem` |
| `ssh: unable to authenticate` | SSH key issue / known hosts | Add SSH keys and known hosts |
| `the server could not find the requested resource` | CRD not yet applied | Use `SkipDryRunOnMissingResource=true` sync option |
| `Too long: must have at most 262144 bytes` | Resource too large for annotation | Use `ServerSideApply=true` sync option |
| `rpc error: code = Unknown desc = authentication required` | Repo credentials missing | Add repo credentials with `argocd repo add` |
| `application is OutOfSync immediately after sync` | Mutating webhook / randAlphaNum / managed fields | Use `ignoreDifferences` |
| `Namespace not found` | Destination namespace missing | Add `CreateNamespace=true` sync option |
| `continue parameter is too old` | etcd compaction during large list | Increase `ARGOCD_CLUSTER_CACHE_LIST_PAGE_BUFFER_SIZE` |
| `randAlphaNum` causing OutOfSync | Helm random function | Pin value explicitly in values.yaml or via `argocd app set -p` |
| `JQ patch execution timed out` | Complex JQ expression | Increase `ignore.normalizer.jq.timeout` in `argocd-cmd-params-cm` |
