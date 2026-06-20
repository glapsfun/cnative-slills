# ArgoCD Installation and Core Concepts

## What is ArgoCD?

ArgoCD is a **declarative, GitOps continuous delivery tool for Kubernetes**. It operates as a Kubernetes controller that continuously monitors running applications and compares the current live state against the desired target state specified in Git repositories.

When applications deviate from their intended configuration, they are marked as `OutOfSync`. ArgoCD can automatically or manually synchronize the live state back to the desired state defined in Git.

### Key Features

- Automated application deployment across multiple target environments
- Multi-cluster management from a single control plane
- Rollback functionality to any committed Git configuration
- Configuration drift detection and visualization
- SSO support (OIDC, OAuth2, LDAP, SAML 2.0, GitHub, GitLab, Microsoft, LinkedIn)
- Multi-tenancy with RBAC policies
- Webhook integration (GitHub, BitBucket, GitLab)
- Web UI with real-time application activity visibility
- CLI for automation and CI pipeline integration
- PreSync, Sync, PostSync hooks for complex rollouts
- Audit trails and Prometheus metrics

### Supported Configuration Methods

- Kustomize applications
- Helm charts
- Jsonnet files
- Plain YAML/JSON manifests
- Custom config management plugins

---

## Architecture

ArgoCD consists of several core components that work together:

### API Server

The primary interface — a gRPC/REST server that exposes the API consumed by the Web UI, CLI, and CI/CD systems. Responsibilities:

- Application management and status reporting
- Sync operation invocation
- Credential storage and management
- Authentication delegation to external identity providers
- RBAC enforcement
- Git webhook event handling
- Listens on port `8080` (HTTP) and `8443` (HTTPS/gRPC)

### Repository Server

An internal service that maintains a cached copy of Git repositories. When asked, it generates and returns Kubernetes manifests given:

- Repository URL
- Revision (commit, tag, branch)
- Application path
- Template-specific configuration (e.g., Helm values, Kustomize overlays)

Listens on port `8081`.

### Application Controller

A Kubernetes controller that continuously monitors running applications. It:

- Compares actual cluster state against the desired target state from Git
- Detects OutOfSync conditions
- Invokes corrective sync actions
- Triggers lifecycle hook workflows (PreSync, Sync, PostSync)
- Uses a work queue to process application reconciliation

### Dex (optional)

An OpenID Connect identity provider bundled with ArgoCD for SSO integration. Used when delegating authentication to external providers like GitHub, LDAP, SAML. Can be disabled if using an external OIDC provider directly.

Listens on port `5556`.

### Redis

Used as a caching layer to reduce load on the API server and repository server. Stores:

- Repository manifest caches
- Cluster connection state
- Application state diffs

Listens on port `6379`.

### ApplicationSet Controller

An optional controller that manages the `ApplicationSet` CRD, enabling templated generation of multiple ArgoCD Applications from a single manifest. Supports generators for clusters, Git directories, lists, and more.

### Notification Controller

Sends notifications about application events (sync status, health changes) to external systems like Slack, PagerDuty, email, etc.

---

## Core Concepts

### Application

A group of Kubernetes resources as defined by a manifest. This is a Custom Resource Definition (CRD) — the fundamental unit in ArgoCD.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
```

### AppProject

A logical grouping of Applications, particularly useful in multi-team environments. Projects enforce access controls via:

1. **Source Repository Restrictions** — which Git repos may be used
2. **Destination Constraints** — target clusters and namespaces
3. **Resource Kind Controls** — which Kubernetes object types can be deployed
4. **Role-Based Access** — project-specific RBAC policies

Every Application belongs to a project (defaults to `default` if unspecified). The `default` project allows all sources, destinations, and resource kinds.

### Application Source Type

Which configuration management tool is used to build the application (Kustomize, Helm, Jsonnet, plain YAML).

### Target State

The desired state of an application, as represented by files in a Git repository.

### Live State

The actual current state of that application — what Pods, Services, etc. are actually deployed in the cluster.

### Sync Status

Whether or not the live state matches the target state. Possible values:

- **Synced** — live state matches Git
- **OutOfSync** — live state differs from Git
- **Unknown** — status cannot be determined

### Sync

The process of making an application move to its target state by applying changes to a Kubernetes cluster.

### Sync Operation Status

Whether a synchronization operation succeeded or failed.

### Refresh

Compare the latest code in Git with the live state to figure out what is different. ArgoCD polls every 3 minutes by default, or can be triggered by webhooks.

### Health

The health of the application — is it running correctly? Can it serve requests? Health statuses:

- **Healthy** — resource is 100% healthy
- **Progressing** — resource is not yet healthy but still making progress
- **Degraded** — resource is degraded or failed
- **Suspended** — resource is suspended/paused (e.g., a CronJob)
- **Missing** — resource is not present in the cluster
- **Unknown** — health status cannot be determined

### Repository

A Git repository (or Helm chart repository) that contains application manifests. Represented as Kubernetes Secrets with the label `argocd.argoproj.io/secret-type: repository`.

### Cluster

A Kubernetes cluster where ArgoCD deploys applications. Represented as Kubernetes Secrets with the label `argocd.argoproj.io/secret-type: cluster`. The cluster hosting ArgoCD itself is available at `https://kubernetes.default.svc`.

---

## Prerequisites and System Requirements

- Kubernetes cluster v1.32+ (ArgoCD v3.4/v3.3 supports Kubernetes v1.32–v1.35)
- `kubectl` CLI configured with cluster access
- `argocd` CLI (for interactive usage)
- Minimum 2 GB RAM for the ArgoCD namespace (production HA requires more)
- Outbound network access from the cluster to Git repositories

---

## Installation Methods

### Method 1: kubectl apply (Recommended / Quickstart)

Install ArgoCD using server-side apply (required because some CRDs exceed the 262KB annotation size limit of client-side apply):

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

The `--force-conflicts` flag allows ArgoCD to take ownership of previously-managed fields.

### Installation Types

#### Non-HA (Standard) — `install.yaml`

Deploys single replicas of each component. Suitable for development, testing, and small teams.

- Includes cluster-admin ClusterRoleBinding for deploying to the same cluster
- All components run as single Pods

```bash
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

#### Non-HA Namespace-Scoped — `namespace-install.yaml`

Same as standard but restricted to namespace-level privileges. Suitable when ArgoCD only manages resources within its own namespace.

**Important**: Requires separate CRD installation first:

```bash
kubectl apply --server-side --force-conflicts \
  -k https://github.com/argoproj/argo-cd/manifests/crds?ref=stable

kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/namespace-install.yaml
```

#### High Availability (HA) — `ha/install.yaml`

Multi-replica installation for production workloads. Deploys:

- Multiple replicas of the API server
- Multiple replicas of the repo server
- Multiple replicas of the application controller
- Redis in HA mode (with Redis Sentinel or cluster)

```bash
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/ha/install.yaml
```

#### HA Namespace-Scoped — `ha/namespace-install.yaml`

Multi-replica with namespace-only permissions:

```bash
kubectl apply --server-side --force-conflicts \
  -k https://github.com/argoproj/argo-cd/manifests/crds?ref=stable

kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/ha/namespace-install.yaml
```

#### Core Installation (Headless) — `core-install.yaml`

Lightweight mode for cluster administrators. No Web UI, no multi-tenancy, no API server. Managed entirely via `kubectl` and the ArgoCD CLI in local mode:

```bash
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/core-install.yaml
```

Usage with core install: `argocd admin app get --core <appname>`

### HA vs Non-HA Differences

| Feature | Non-HA | HA |
|---------|--------|----|
| API Server replicas | 1 | 2+ |
| Repo Server replicas | 1 | 2+ |
| Application Controller | 1 | 1 (sharded) |
| Redis | Single instance | Redis HA (Sentinel) |
| Use case | Dev/test, small teams | Production |
| Resource requirements | Low | Higher |

### Namespace vs Cluster-Scoped Install

| Feature | Cluster-Scoped (`install.yaml`) | Namespace-Scoped (`namespace-install.yaml`) |
|---------|--------------------------------|---------------------------------------------|
| ClusterRole | cluster-admin | Namespace-only |
| Can deploy to other namespaces | Yes | No (restricted to own namespace) |
| Can manage cluster resources | Yes | No |
| CRDs bundled | Yes | No (install separately) |
| Multi-cluster support | Full | Limited |

---

### Method 2: Kustomize

Basic Kustomize overlay pointing to upstream manifests:

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd
resources:
  - https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Apply with:

```bash
kubectl apply -n argocd --server-side -k ./
```

#### Custom Namespace with Kustomize

When installing into a non-default namespace, apply a patch to update the ClusterRoleBinding namespace reference:

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: my-argocd
resources:
  - https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
patches:
  - target:
      kind: ClusterRoleBinding
    patch: |-
      - op: replace
        path: /subjects/0/namespace
        value: my-argocd
```

### Method 3: Helm Chart

Community-maintained Helm chart from `argoproj/argo-helm`:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 7.x.x
```

With custom values:

```bash
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f values.yaml
```

Example `values.yaml` for HA:

```yaml
replicaCount: 2
server:
  replicas: 2
repoServer:
  replicas: 2
redis-ha:
  enabled: true
```

---

## Getting Started Workflow

### Step 1: Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for pods to be ready:

```bash
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd
```

### Step 2: Install the ArgoCD CLI

**macOS (Homebrew):**

```bash
brew install argocd
```

**Linux:**

```bash
curl -sSL -o argocd-linux-amd64 \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

**Windows (PowerShell):**

```powershell
$version = (Invoke-RestMethod https://api.github.com/repos/argoproj/argo-cd/releases/latest).tag_name
Invoke-WebRequest -Uri https://github.com/argoproj/argo-cd/releases/download/$version/argocd-windows-amd64.exe -OutFile argocd.exe
```

### Step 3: Access the ArgoCD API Server

**Option A: Port Forwarding (simplest)**

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Access at https://localhost:8080
```

**Option B: Expose via LoadBalancer**

```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Wait for external IP
kubectl get svc argocd-server -n argocd -w

# Get IP
kubectl get svc argocd-server -n argocd \
  -o=jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Step 4: Login

Get the initial admin password (auto-generated during install):

```bash
argocd admin initial-password -n argocd
```

Login:

```bash
argocd login <ARGOCD_SERVER>
# e.g.: argocd login localhost:8080 --insecure
```

Change the password immediately:

```bash
argocd account update-password
```

Delete the initial password secret after changing:

```bash
kubectl delete secret argocd-initial-admin-secret -n argocd
```

### Step 5: Register an External Cluster (Optional)

To deploy to clusters other than the one hosting ArgoCD:

```bash
# List available contexts
kubectl config get-contexts -o name

# Add a cluster (installs a ServiceAccount with cluster-admin binding)
argocd cluster add <CONTEXT_NAME>

# List registered clusters
argocd cluster list
```

### Step 6: Add a Repository

**Via CLI (public repo):**

```bash
argocd repo add https://github.com/argoproj/argocd-example-apps.git
```

**Via CLI (private HTTPS repo):**

```bash
argocd repo add https://github.com/myorg/private-repo.git \
  --username myuser \
  --password mypassword
```

**Via CLI (private SSH repo):**

```bash
argocd repo add git@github.com:myorg/private-repo.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

**Via declarative Secret:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: private-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/myorg/private-repo
  username: myuser
  password: mypassword
```

### Step 7: Create an Application

**Via CLI:**

```bash
# Set default namespace to argocd for convenience
kubectl config set-context --current --namespace=argocd

argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default
```

**Via UI:**

1. Navigate to ArgoCD UI and log in
2. Click "+ New App"
3. Set application name: `guestbook`
4. Set project: `default`
5. Set sync policy (manual or automatic)
6. Set repository URL
7. Set path: `guestbook`
8. Set destination server: `https://kubernetes.default.svc`
9. Set namespace: `default`
10. Click Create

### Step 8: Sync the Application

**Via CLI:**

```bash
argocd app sync guestbook
```

**Via UI:**

Click the Sync button on the application card, then confirm with Synchronize.

**Check application status:**

```bash
argocd app get guestbook
argocd app list
```

---

## AppProject: Detailed Configuration

### Basic AppProject

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: my-project
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  description: Example Project
  sourceRepos:
    - 'https://github.com/myorg/*'
  destinations:
    - namespace: my-namespace
      server: https://kubernetes.default.svc
    - namespace: staging-*
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
  namespaceResourceBlacklist:
    - group: ''
      kind: ResourceQuota
    - group: ''
      kind: LimitRange
    - group: ''
      kind: NetworkPolicy
  roles:
    - name: read-only
      description: Read-only privileges
      policies:
        - p, proj:my-project:read-only, applications, get, my-project/*, allow
      groups:
        - my-oidc-group
    - name: ci-role
      description: Sync privileges for specific app
      policies:
        - p, proj:my-project:ci-role, applications, sync, my-project/guestbook-dev, allow
      jwtTokens:
        - iat: 1535390316
```

### Default Project (Lock-Down)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
spec:
  sourceRepos: []
  sourceNamespaces: []
  destinations: []
  namespaceResourceBlacklist:
  - group: '*'
    kind: '*'
```

### Project CLI Commands

```bash
# Create project
argocd proj create myproject \
  -d https://kubernetes.default.svc,mynamespace \
  -s https://github.com/argoproj/argocd-example-apps.git

# Add/remove sources
argocd proj add-source myproject https://github.com/myorg/repo.git
argocd proj remove-source myproject https://github.com/myorg/repo.git

# Add negation (deny specific repo)
argocd proj add-source myproject '!https://github.com/myorg/forbidden.git'

# Add/remove destinations
argocd proj add-destination myproject https://kubernetes.default.svc,production
argocd proj remove-destination myproject https://kubernetes.default.svc,production

# Resource kind management
argocd proj allow-cluster-resource myproject '' Namespace
argocd proj deny-cluster-resource myproject '*' '*'
argocd proj allow-namespace-resource myproject apps Deployment

# Role management
argocd proj role create myproject ci-role
argocd proj role create-token myproject ci-role
argocd proj role add-policy myproject ci-role \
  -a sync -o '*' -p allow

# Assign application to project
argocd app set guestbook --project myproject
```

### Source Negation Rules

```yaml
spec:
  sourceRepos:
    - '!ssh://git@github.com:argoproj/forbidden'
    - '!https://gitlab.com/group/**'
    - '*'
```

Validation: a source is valid if any allow rule permits it AND no deny rule rejects it.

---

## Repository Configuration (Declarative)

### HTTPS Repository

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: private-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/argoproj/private-repo
  username: my-username
  password: my-password
  project: my-project   # optional: makes it project-scoped
```

### SSH Repository

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: private-repo-ssh
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: git@github.com:argoproj/my-private-repository.git
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    [key content]
    -----END OPENSSH PRIVATE KEY-----
```

### GitHub App Authentication

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/argoproj/my-private-repository
  githubAppID: "1"
  githubAppInstallationID: "2"
  githubAppPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    [key content]
    -----END OPENSSH PRIVATE KEY-----
```

### Helm Repository

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argo-helm
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  name: argo
  url: https://argoproj.github.io/argo-helm
  type: helm
  username: my-username
  password: my-password
  tlsClientCertData: ...
  tlsClientCertKey: ...
```

### OCI Helm Registry

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: oci-helm-chart
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  name: oci-helm-chart
  url: myregistry.example.com
  type: helm
  enableOCI: "true"
```

### Repository Credential Templates

Share credentials across multiple repos with the same URL prefix:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: private-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  type: git
  url: https://github.com/argoproj
  username: my-username
  password: my-password
```

Any repo starting with `https://github.com/argoproj` will use these credentials.

---

## Cluster Configuration (Declarative)

### Basic Cluster Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mycluster-secret
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
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

### EKS with IRSA

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: eks-cluster-secret
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: "my-eks-cluster"
  server: "https://xxxyyyzzz.xyz.us-east-1.eks.amazonaws.com"
  config: |
    {
      "awsAuthConfig": {
        "clusterName": "my-eks-cluster",
        "roleARN": "arn:aws:iam::ACCOUNT:role/ROLE_NAME"
      },
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64 encoded certificate>"
      }
    }
```

### GKE with Workload Identity

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gke-cluster-secret
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: mycluster.example.com
  server: https://mycluster.example.com
  config: |
    {
      "execProviderConfig": {
        "command": "argocd-k8s-auth",
        "args": ["gcp"],
        "apiVersion": "client.authentication.k8s.io/v1beta1"
      },
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64 encoded certificate>"
      }
    }
```

### Skip Cluster Reconciliation

```yaml
metadata:
  annotations:
    argocd.argoproj.io/skip-reconcile: "true"
```

---

## Sync Policies and Options

### Manual vs Automated Sync

**Enable automated sync (CLI):**

```bash
argocd app set <APPNAME> --sync-policy automated
```

**Enable automated sync (YAML):**

```yaml
spec:
  syncPolicy:
    automated: {}
```

### Auto-Prune

By default, automated sync will NOT delete resources removed from Git. Enable pruning:

```bash
argocd app set <APPNAME> --auto-prune
```

```yaml
spec:
  syncPolicy:
    automated:
      prune: true
```

### Self-Heal

Resync when live state deviates from Git:

```bash
argocd app set <APPNAME> --self-heal
```

```yaml
spec:
  syncPolicy:
    automated:
      selfHeal: true
```

### Full Automated Sync Policy Example

```yaml
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### Sync Options Reference

| Option | Scope | Description |
|--------|-------|-------------|
| `CreateNamespace=true` | App | Auto-create destination namespace |
| `ServerSideApply=true` | App/Resource | Use Kubernetes server-side apply |
| `Replace=true` | App/Resource | Use `kubectl replace` instead of apply |
| `Prune=false` | Resource annotation | Never prune this specific resource |
| `Prune=confirm` | App | Require manual confirmation before pruning |
| `ApplyOutOfSyncOnly=true` | App | Only sync out-of-sync resources (performance) |
| `PruneLast=true` | App | Prune only after all other resources synced |
| `PrunePropagationPolicy=foreground` | App | Deletion propagation (background/foreground/orphan) |
| `FailOnSharedResource=true` | App | Fail if a resource is managed by another App |
| `RespectIgnoreDifferences=true` | App | Honor ignoreDifferences during sync |
| `SkipDryRunOnMissingResource=true` | App | Skip dry-run for unknown CRDs |
| `Validate=false` | Resource annotation | Skip kubectl validation for this resource |
| `Force=true` | Resource annotation | Force delete/recreate (destructive) |
| `Delete=false` | App | Retain resources when application is deleted |

### Namespace Metadata Management

```yaml
spec:
  destination:
    namespace: some-namespace
  syncPolicy:
    managedNamespaceMetadata:
      labels:
        env: production
        team: platform
      annotations:
        contact: platform-team@example.com
    syncOptions:
    - CreateNamespace=true
```

### Ignore Differences

```yaml
spec:
  ignoreDifferences:
  - group: "apps"
    kind: "Deployment"
    jsonPointers:
    - /spec/replicas
  - group: ""
    kind: "ConfigMap"
    name: "my-config"
    jsonPointers:
    - /data/generated-field
  syncPolicy:
    syncOptions:
    - RespectIgnoreDifferences=true
```

---

## Resource Hooks and Sync Waves

### Hook Types

| Hook | Description |
|------|-------------|
| `PreSync` | Executes before manifests are applied |
| `Sync` | Runs concurrently with manifest application (after PreSync succeeds) |
| `PostSync` | Executes after all Sync hooks completed successfully |
| `SyncFail` | Triggered when sync operations fail |
| `Skip` | Tells ArgoCD to skip application of this manifest |
| `PreDelete` | Runs before Application deletion |
| `PostDelete` | Executes after Application resources are deleted (v2.10+) |

### Hook Annotations

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

Multiple hooks: `argocd.argoproj.io/hook: PreSync,Sync`

### Hook Deletion Policies

| Policy | Description |
|--------|-------------|
| `HookSucceeded` | Delete hook resource after it succeeds |
| `HookFailed` | Delete hook resource after it fails |
| `BeforeHookCreation` | Delete any existing hook resource before creating new one (default) |

### PreSync Database Migration Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
    argocd.argoproj.io/sync-wave: '-1'
spec:
  ttlSecondsAfterFinished: 360
  template:
    spec:
      containers:
        - name: postgresql-client
          image: 'my-postgres-data:11.5'
          command:
            - psql
            - '-h=my_postgresql_db'
            - '-U postgres'
            - '-f preload.sql'
      restartPolicy: Never
  backoffLimit: 1
```

### PostSync Notification Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  generateName: app-slack-notification-
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: slack-notification
          image: curlimages/curl
          command:
            - curl
            - '-X'
            - POST
            - '--data-urlencode'
            - 'payload={"channel": "#deployments", "text": "App Sync succeeded"}'
            - 'https://hooks.slack.com/services/...'
      restartPolicy: Never
  backoffLimit: 2
```

### Sync Waves

Control the order resources are applied within a sync operation. Lower wave numbers apply first. Waves can be negative.

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "5"
```

Processing order: **phase → wave number (lowest first) → kind → name**

- Wave -1: runs before wave 0
- Default wave is 0
- A 2-second delay separates each wave

---

## ApplicationSet

ApplicationSet extends ArgoCD to template the creation of multiple Applications from a single manifest.

### List Generator

Creates Applications from a static list:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: engineering-dev
        url: https://dev.example.com
      - cluster: engineering-prod
        url: https://prod.example.com
  template:
    metadata:
      name: '{{.cluster}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps.git
        targetRevision: HEAD
        path: guestbook
      destination:
        server: '{{.url}}'
        namespace: guestbook
```

### Cluster Generator

Automatically generates Applications for all clusters registered in ArgoCD:

```yaml
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          env: production
  template:
    metadata:
      name: '{{.name}}-app'
    spec:
      destination:
        server: '{{.server}}'
        namespace: my-app
```

### Git Directory Generator

Creates Applications for each directory in a Git repo:

```yaml
spec:
  generators:
  - git:
      repoURL: https://github.com/myorg/my-apps.git
      revision: HEAD
      directories:
      - path: apps/*
  template:
    metadata:
      name: '{{.path.basename}}'
    spec:
      source:
        repoURL: https://github.com/myorg/my-apps.git
        targetRevision: HEAD
        path: '{{.path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.path.basename}}'
```

---

## Ingress Configuration

ArgoCD exposes both HTTP/HTTPS and gRPC on the same port (8080/443). Most ingress controllers need special configuration to handle this.

**Key principle**: Either let ArgoCD handle TLS (SSL passthrough), or terminate TLS at the ingress and run ArgoCD in insecure mode.

Enable insecure mode for ingress termination:

```yaml
# In argocd-cmd-params-cm ConfigMap
data:
  server.insecure: "true"
```

Or via command flag: `--insecure`

### NGINX — SSL Passthrough (Simplest)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: https
```

Requires `--enable-ssl-passthrough` flag on the NGINX Ingress Controller.

### NGINX — SSL Termination at Ingress

Requires two Ingress objects (HTTP and gRPC use different backend protocols):

```yaml
# HTTP/HTTPS Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-http-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: http
  tls:
  - hosts:
    - argocd.example.com
    secretName: argocd-ingress-http
---
# gRPC Ingress (separate hostname)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-grpc-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
spec:
  ingressClassName: nginx
  rules:
  - host: grpc.argocd.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: https
  tls:
  - hosts:
    - grpc.argocd.example.com
    secretName: argocd-ingress-grpc
```

### Traefik v3.0

Handles gRPC and HTTP on a single hostname via IngressRoute CRD:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: argocd-server
  namespace: argocd
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`argocd.example.com`)
      priority: 10
      services:
        - name: argocd-server
          port: 80
    - kind: Rule
      match: Host(`argocd.example.com`) && Header(`Content-Type`, `application/grpc`)
      priority: 11
      services:
        - name: argocd-server
          port: 80
          scheme: h2c
  tls:
    certResolver: default
```

### AWS ALB

Requires a separate NodePort service for gRPC:

```yaml
# gRPC Service
apiVersion: v1
kind: Service
metadata:
  annotations:
    alb.ingress.kubernetes.io/backend-protocol-version: GRPC
  name: argogrpc
  namespace: argocd
spec:
  ports:
  - name: "443"
    port: 443
    protocol: TCP
    targetPort: 8080
  selector:
    app.kubernetes.io/name: argocd-server
  type: NodePort
---
# ALB Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
    alb.ingress.kubernetes.io/conditions.argogrpc: |
      [{"field":"http-header","httpHeaderConfig":{"httpHeaderName":"Content-Type","values":["application/grpc"]}}]
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/healthcheck-path: /grpc.health.v1.Health/Check
    alb.ingress.kubernetes.io/success-codes: '0'
  name: argocd
  namespace: argocd
spec:
  rules:
  - host: argocd.example.com
    http:
      paths:
      - path: /
        backend:
          service:
            name: argogrpc
            port:
              number: 443
        pathType: Prefix
      - path: /
        backend:
          service:
            name: argocd-server
            port:
              number: 443
        pathType: Prefix
```

### GKE Native Ingress

```yaml
# BackendConfig for health checks
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: argocd-backend-config
  namespace: argocd
spec:
  healthCheck:
    checkIntervalSec: 30
    timeoutSec: 5
    healthyThreshold: 1
    unhealthyThreshold: 2
    type: HTTP
    requestPath: /healthz
    port: 8080
---
# Annotate the argocd-server Service
apiVersion: v1
kind: Service
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
    cloud.google.com/backend-config: '{"ports": {"http":"argocd-backend-config"}}'
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    app.kubernetes.io/name: argocd-server
---
# FrontendConfig for HTTPS redirect
apiVersion: networking.gke.io/v1beta1
kind: FrontendConfig
metadata:
  name: argocd-frontend-config
  namespace: argocd
spec:
  redirectToHttps:
    enabled: true
---
# Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd
  namespace: argocd
  annotations:
    networking.gke.io/v1beta1.FrontendConfig: argocd-frontend-config
spec:
  tls:
    - secretName: argocd-tls-secret
  rules:
    - host: argocd.example.com
      http:
        paths:
        - pathType: Prefix
          path: "/"
          backend:
            service:
              name: argocd-server
              port:
                number: 80
```

### Gateway API (Kubernetes Gateway API)

```yaml
# Gateway
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: cluster-gateway
  namespace: gateway
spec:
  gatewayClassName: example
  listeners:
    - protocol: HTTPS
      port: 443
      hostname: "*.example.com"
      tls:
        mode: Terminate
        certificateRefs:
          - name: cluster-gateway-tls
---
# HTTP Route
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-http-route
  namespace: argocd
spec:
  parentRefs:
    - name: cluster-gateway
      namespace: gateway
  hostnames:
    - "argocd.example.com"
  rules:
    - backendRefs:
        - name: argocd-server
          port: 80
---
# gRPC Route (separate hostname)
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: argocd-grpc-route
  namespace: argocd
spec:
  parentRefs:
    - name: cluster-gateway
      namespace: gateway
  hostnames:
    - "grpc.argocd.example.com"
  rules:
    - backendRefs:
        - name: argocd-server
          port: 443
```

For Gateway API, enable HTTP/2 in Helm values:

```yaml
server:
  service:
    servicePortHttpsAppProtocol: kubernetes.io/h2c
```

---

## Additional Declarative Resources

### SSH Known Hosts

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-ssh-known-hosts-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-ssh-known-hosts-cm
    app.kubernetes.io/part-of: argocd
data:
  ssh_known_hosts: |
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
    gitlab.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsj2bNKTBSpIYDEGk9KxsGh3mySTRgMtXL583qmBpzeQ+jqCMRgBqB98u3z++J1sKlXHWfM9dyhSevkMwSbhoR8XIq/U0tCNyokEi/ueaBMCvbcTHhO7FcwzY92WK4Yt0aGROY5qX2UKSeOvuP4D6TPqKF1onrSzH9bx9XUf2lEdWT/ia1NEKjunUqu1xOB/StKDHMoX4/OKyIzuS0q/T1zOATthvasJFoPrAjkohTyaDUz2LN5JoH839hViyEG82yB+MjcFV5MU3N1l1QL3cVUCh93xSaua1N85qivl+siMkPGbO5xR/En4iEY6K2XPASUEMaieWVNTRCtJ4S8H+9
```

### TLS Certificates

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-tls-certs-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  my-git-server.example.com: |
    -----BEGIN CERTIFICATE-----
    [certificate content]
    -----END CERTIFICATE-----
```

---

## Version Compatibility Matrix

| ArgoCD Version | Kubernetes Support |
|---------------|-------------------|
| v3.4 | v1.32, v1.33, v1.34, v1.35 |
| v3.3 | v1.32, v1.33, v1.34, v1.35 |

---

## Key Behavioral Notes

- ArgoCD polls Git repositories every 3 minutes by default (configurable)
- Self-heal timeout defaults to 5 seconds
- Default reconciliation interval is 120 seconds with up to 60 seconds jitter
- Automated sync only runs once per commit SHA + parameter combination (no infinite loops)
- Rollback is disabled for applications with automated sync enabled
- Failed syncs do NOT automatically retry (unless retry policy is configured)
- `kubectl apply --server-side` is required for CRDs with large annotations (>262KB)
- All ArgoCD resources must be in the ArgoCD namespace (default: `argocd`)
- ConfigMaps must have label `app.kubernetes.io/part-of: argocd` for discovery
