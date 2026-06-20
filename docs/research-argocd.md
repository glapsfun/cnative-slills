# ArgoCD Research Document

Comprehensive research on ArgoCD — installation, CRDs, CLI, security, troubleshooting, and best practices.

---

## Source Links

All research is based on the following official sources:

- https://argo-cd.readthedocs.io/en/stable/
- https://argo-cd.readthedocs.io/en/stable/core_concepts/
- https://argo-cd.readthedocs.io/en/stable/user-guide/
- https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/
- https://argo-cd.readthedocs.io/en/stable/user-guide/projects/
- https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd/
- https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/
- https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/
- https://argo-cd.readthedocs.io/en/stable/user-guide/helm/
- https://argo-cd.readthedocs.io/en/stable/user-guide/kustomize/
- https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/
- https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/
- https://argo-cd.readthedocs.io/en/stable/user-guide/troubleshooting/
- https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/
- https://argo-cd.readthedocs.io/en/stable/user-guide/app_deletion/
- https://argo-cd.readthedocs.io/en/stable/developer-guide/
- https://argo-cd.readthedocs.io/en/stable/getting_started/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/metrics/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/overview/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/troubleshooting/
- https://argo-cd.readthedocs.io/en/stable/security_considerations/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/security/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/secret-management/
- https://github.com/argoproj/argo-cd
- https://github.com/argoproj/argo-cd/tree/master/docs/
- https://github.com/argoproj/argo-cd/tree/master/examples/
- https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/application.yaml
- https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/project.yaml

---


---

# Part 1: Installation, Architecture & Core Concepts

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

---

# Part 2: CRDs, Application Configuration & ApplicationSet

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

---

# Part 3: CLI Reference & Best Practices

# ArgoCD CLI Reference and Best Practices

> Source: ArgoCD stable documentation (https://argo-cd.readthedocs.io/en/stable/)
> Covers: CLI reference, sync waves, resource hooks, diffing, app deletion

---

## Table of Contents

1. [Installation and Global Flags](#1-installation-and-global-flags)
2. [argocd login / logout / context](#2-argocd-login--logout--context)
3. [argocd app — Application Management](#3-argocd-app--application-management)
4. [argocd cluster — Cluster Management](#4-argocd-cluster--cluster-management)
5. [argocd repo — Repository Management](#5-argocd-repo--repository-management)
6. [argocd proj — Project Management](#6-argocd-proj--project-management)
7. [argocd account — Account Management](#7-argocd-account--account-management)
8. [argocd admin — Admin Commands](#8-argocd-admin--admin-commands)
9. [Sync Waves](#9-sync-waves)
10. [Resource Hooks](#10-resource-hooks)
11. [Diffing Configuration](#11-diffing-configuration)
12. [App Deletion](#12-app-deletion)
13. [CI/CD Pipeline Best Practices](#13-cicd-pipeline-best-practices)

---

## 1. Installation and Global Flags

### Installation

```bash
# macOS via Homebrew
brew install argocd

# Linux — download binary
curl -sSL -o argocd-linux-amd64 \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd-linux-amd64
sudo mv argocd-linux-amd64 /usr/local/bin/argocd

# Verify
argocd version
```

### Global Flags (available on every subcommand)

| Flag | Description |
|------|-------------|
| `--server <host:port>` | ArgoCD server address |
| `--auth-token <token>` | Authentication token (alternative to login) |
| `--insecure` | Disable TLS certificate verification |
| `--plaintext` | Use plaintext (non-TLS) connection |
| `--grpc-web` | Use gRPC-web protocol (for reverse proxies that block HTTP/2) |
| `--grpc-web-root-path <path>` | Set root path for gRPC-web calls |
| `--config <path>` | Path to argocd config file (default: ~/.config/argocd/config) |
| `--port-forward` | Use port-forwarding to connect to argocd-server |
| `--port-forward-namespace <ns>` | Namespace to port-forward into (default: argocd) |
| `--proxy-superscript <url>` | HTTP proxy URL |
| `-v, --verbose` | Verbose output |
| `-h, --help` | Show help |

---

## 2. argocd login / logout / context

### argocd login

Authenticate against an ArgoCD server and store credentials in the local config.

```bash
# Basic login (prompts for username/password)
argocd login <ARGOCD_SERVER>

# Login with credentials inline (non-interactive — for CI/CD)
argocd login <ARGOCD_SERVER> \
  --username admin \
  --password <password> \
  --insecure

# Login with SSO (opens browser)
argocd login <ARGOCD_SERVER> --sso

# Login with an auth token directly
argocd login <ARGOCD_SERVER> --auth-token <token>

# Skip TLS verification (useful for self-signed certs)
argocd login <ARGOCD_SERVER> \
  --username admin \
  --password <password> \
  --insecure \
  --grpc-web
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--username <user>` | Username (default: admin) |
| `--password <pass>` | Password |
| `--sso` | Use SSO login |
| `--sso-port <port>` | Port for local SSO callback (default: 8085) |
| `--insecure` | Skip TLS verification |
| `--plaintext` | Use plaintext gRPC |
| `--grpc-web` | Enable gRPC-web transport |
| `--skip-test-tls` | Skip TLS connection test |

### argocd logout

```bash
argocd logout <ARGOCD_SERVER>
```

### argocd context

Manage multiple ArgoCD server contexts (like kubectl contexts).

```bash
# List all contexts
argocd context

# Switch to a context
argocd context <context-name>

# Delete a context
argocd context --delete <context-name>
```

### CI/CD: Authenticating Without Storing Credentials

In pipelines, prefer environment variables and `--auth-token` to avoid interactive login:

```bash
# Set ARGOCD_SERVER and ARGOCD_AUTH_TOKEN env vars
export ARGOCD_SERVER=argocd.example.com
export ARGOCD_AUTH_TOKEN=$(argocd account generate-token --account ci-bot)

# Then all commands use these automatically — no login step needed
argocd app sync my-app --auth-token "$ARGOCD_AUTH_TOKEN" --server "$ARGOCD_SERVER"
```

---

## 3. argocd app — Application Management

### argocd app create

Create or update an ArgoCD Application.

```bash
# Minimal example — Git source, auto-sync disabled
argocd app create my-app \
  --repo https://github.com/org/repo.git \
  --path manifests/overlays/production \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace production

# With Helm
argocd app create my-helm-app \
  --repo https://charts.example.com \
  --helm-chart my-chart \
  --revision 1.2.3 \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace staging \
  --helm-set image.tag=v1.5.0 \
  --helm-set replicas=3 \
  --helm-values values-staging.yaml

# With Kustomize
argocd app create my-kustomize-app \
  --repo https://github.com/org/repo.git \
  --path kustomize/overlays/prod \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace production \
  --kustomize-image nginx:1.21

# With auto-sync and self-heal
argocd app create my-app \
  --repo https://github.com/org/repo.git \
  --path manifests/ \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# In a specific project
argocd app create my-app \
  --repo https://github.com/org/repo.git \
  --path manifests/ \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace production \
  --project my-project

# Using an app-of-apps pattern (Application from a file)
argocd app create -f application.yaml
```

**Key Flags for `argocd app create`:**

| Flag | Description |
|------|-------------|
| `--repo <url>` | Git repo URL |
| `--revision <ref>` | Branch, tag, or commit SHA (default: HEAD) |
| `--path <path>` | Path within the repo |
| `--helm-chart <name>` | Helm chart name (for Helm repo source) |
| `--dest-server <url>` | Destination cluster API URL |
| `--dest-namespace <ns>` | Destination namespace |
| `--project <proj>` | ArgoCD project (default: default) |
| `--sync-policy automated` | Enable auto-sync |
| `--auto-prune` | Prune resources removed from Git |
| `--self-heal` | Revert manual changes in cluster |
| `--sync-option <opt>` | Sync options (e.g. `CreateNamespace=true`) |
| `--helm-set <key=val>` | Helm value override |
| `--helm-set-string <key=val>` | Helm string value override |
| `--helm-values <file>` | Helm values file path (relative to repo) |
| `--kustomize-image <img>` | Override Kustomize image |
| `--nameprefix <prefix>` | Kustomize name prefix |
| `--namesuffix <suffix>` | Kustomize name suffix |
| `--directory-recurse` | Recurse into subdirectories |
| `--config-management-plugin <name>` | Config management plugin name |
| `-f, --file <path>` | Create from Application YAML file |
| `--upsert` | Update existing app instead of failing |
| `--validate` | Validate manifests before creating |
| `--label <key=val>` | Labels to apply to the Application |
| `--annotations <key=val>` | Annotations to apply to the Application |

### argocd app get

Get details of an application.

```bash
# Basic get
argocd app get my-app

# Show resource tree
argocd app get my-app --show-params

# Output as JSON
argocd app get my-app -o json

# Output as YAML
argocd app get my-app -o yaml

# Show operation (last sync) details
argocd app get my-app --show-operation
```

### argocd app list

List all applications.

```bash
# List all apps
argocd app list

# Filter by project
argocd app list --project my-project

# Filter by labels
argocd app list --selector app=frontend,env=prod

# Filter by namespace
argocd app list --app-namespace argocd

# Output as JSON
argocd app list -o json

# List with wide output
argocd app list -o wide
```

**Output fields:** NAME, CLUSTER, NAMESPACE, PROJECT, STATUS, HEALTH, SYNCPOLICY, CONDITIONS, REPO, PATH, TARGET

### argocd app sync

Trigger a sync (deploy) for one or more applications.

```bash
# Sync an application (uses current HEAD)
argocd app sync my-app

# Sync to a specific revision
argocd app sync my-app --revision v1.2.3

# Sync and wait for completion
argocd app sync my-app --wait

# Sync with timeout
argocd app sync my-app --timeout 300

# Dry run (preview what would change)
argocd app sync my-app --dry-run

# Force sync (ignore diff cache)
argocd app sync my-app --force

# Prune resources not in Git
argocd app sync my-app --prune

# Sync only specific resources
argocd app sync my-app --resource apps:Deployment:my-deployment
argocd app sync my-app --resource :Service:my-svc

# Apply resources only (skip hooks)
argocd app sync my-app --apply-out-of-sync-only

# Sync multiple apps
argocd app sync app1 app2 app3

# Sync with sync strategy (replace instead of apply)
argocd app sync my-app --replace

# Async sync (don't wait for result)
argocd app sync my-app --async

# Server-side apply
argocd app sync my-app --server-side
```

**Key Flags for `argocd app sync`:**

| Flag | Description |
|------|-------------|
| `--revision <ref>` | Git revision to sync to |
| `--dry-run` | Preview changes without applying |
| `--prune` | Delete resources removed from Git |
| `--force` | Force sync regardless of diff cache |
| `--async` | Submit sync and return immediately |
| `--timeout <sec>` | Time to wait for sync (default: 0 = no timeout) |
| `--wait` | Wait until sync completes |
| `--resource <group:kind:name>` | Sync only specific resources |
| `--replace` | Use kubectl replace instead of apply |
| `--server-side` | Use server-side apply |
| `--apply-out-of-sync-only` | Only apply out-of-sync resources |
| `--retry-limit <n>` | Max sync retries |
| `--retry-backoff-duration <dur>` | Initial backoff between retries |
| `--retry-backoff-max-duration <dur>` | Max backoff duration |
| `--retry-backoff-factor <n>` | Backoff multiplier |
| `--local <dir>` | Sync from local directory (bypass Git) |
| `--local-repo-root <path>` | Relative path within local dir to app root |
| `--preview-changes` | Preview changes (like --dry-run but shows diff) |

### argocd app wait

Wait for an application to reach a target state.

```bash
# Wait for sync to complete
argocd app wait my-app

# Wait for health to be Healthy
argocd app wait my-app --health

# Wait for sync status
argocd app wait my-app --sync

# Wait for operation to complete
argocd app wait my-app --operation

# Wait with timeout
argocd app wait my-app --timeout 120

# Wait for specific condition
argocd app wait my-app --health --sync --timeout 300

# Wait for multiple apps
argocd app wait app1 app2 --health
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--health` | Wait for Healthy health status |
| `--sync` | Wait for Synced sync status |
| `--operation` | Wait for pending operation to finish |
| `--timeout <sec>` | Max wait time in seconds |
| `--suspended` | Wait for Suspended app (Rollouts) |
| `--degraded` | Consider Degraded health as success (for skip) |

### argocd app delete

Delete an application.

```bash
# Delete app (keeps live resources by default)
argocd app delete my-app

# Cascade delete (also deletes live Kubernetes resources)
argocd app delete my-app --cascade

# Non-cascade delete (keeps resources in cluster)
argocd app delete my-app --cascade=false

# Skip confirmation prompt
argocd app delete my-app --yes

# Delete multiple apps
argocd app delete app1 app2 --yes
```

See Section 12 for full deletion details including finalizers.

### argocd app set

Update application settings without recreating.

```bash
# Change the Git revision
argocd app set my-app --revision main

# Update Helm values
argocd app set my-app --helm-set image.tag=v2.0.0

# Enable auto-sync
argocd app set my-app --sync-policy automated

# Enable auto-prune
argocd app set my-app --auto-prune

# Enable self-heal
argocd app set my-app --self-heal

# Disable auto-sync
argocd app set my-app --sync-policy none

# Change destination namespace
argocd app set my-app --dest-namespace new-namespace

# Add sync option
argocd app set my-app --sync-option CreateNamespace=true

# Remove sync option
argocd app set my-app --sync-option CreateNamespace=false
```

### argocd app patch

Patch an application using JSON patch or merge patch.

```bash
# JSON patch
argocd app patch my-app \
  --patch '[{"op":"replace","path":"/spec/source/targetRevision","value":"v2.0.0"}]' \
  --type json

# Merge patch
argocd app patch my-app \
  --patch '{"spec":{"source":{"targetRevision":"v2.0.0"}}}' \
  --type merge
```

### argocd app rollback

Roll back an application to a previous deployment.

```bash
# List history first
argocd app history my-app

# Rollback to a specific history ID
argocd app rollback my-app <history-id>

# Rollback and wait
argocd app rollback my-app <history-id> --timeout 120

# Prune during rollback
argocd app rollback my-app <history-id> --prune
```

### argocd app history

View sync history for an application.

```bash
# Show history
argocd app history my-app

# Output as JSON
argocd app history my-app -o json
```

Output includes: ID, DATE, REVISION (commit SHA), INITIATOR

### argocd app manifests

Display manifests for an application as ArgoCD would render them.

```bash
# Show rendered manifests
argocd app manifests my-app

# Show manifests for a specific revision
argocd app manifests my-app --revision v1.2.3

# Show live manifests (from cluster)
argocd app manifests my-app --source live

# Show Git manifests (desired state)
argocd app manifests my-app --source git

# Output as JSON
argocd app manifests my-app -o json
```

### argocd app logs

Stream logs from application pods.

```bash
# Stream all logs
argocd app logs my-app

# Logs for a specific pod
argocd app logs my-app --pod my-pod-name

# Logs for a specific container
argocd app logs my-app --container main

# Follow logs
argocd app logs my-app --follow

# Show previous container logs
argocd app logs my-app --previous

# Tail N lines
argocd app logs my-app --tail 100

# Since a time
argocd app logs my-app --since-time 2024-01-01T00:00:00Z

# Since duration
argocd app logs my-app --since 1h

# Filter by group/kind/name
argocd app logs my-app --group apps --kind Deployment --resource-name my-deployment

# Filter by namespace
argocd app logs my-app --namespace production
```

### argocd app diff

Show diff between live and desired state.

```bash
# Show diff for an app
argocd app diff my-app

# Diff against a specific revision
argocd app diff my-app --revision HEAD~1

# Diff from local directory
argocd app diff my-app --local ./manifests

# Hard refresh before diff (re-fetch from Git)
argocd app diff my-app --hard-refresh

# Refresh before diff
argocd app diff my-app --refresh

# Exit code reflects diff presence (useful in CI)
argocd app diff my-app; echo "Exit: $?"
# 0 = no diff, 1 = diff exists, 2 = error
```

### argocd app actions

Trigger resource actions defined by resource hooks or custom actions.

```bash
# List available actions for a resource
argocd app actions list my-app --kind Rollout --resource-name my-rollout

# Run a specific action
argocd app actions run my-app restart --kind Deployment --resource-name my-deployment

# Run Argo Rollouts action
argocd app actions run my-app resume --kind Rollout --resource-name my-rollout
```

### argocd app patch-resource

Patch a specific resource managed by an app.

```bash
argocd app patch-resource my-app \
  --kind Deployment \
  --resource-name my-deployment \
  --namespace production \
  --patch '{"spec":{"replicas":5}}' \
  --patch-type merge
```

### argocd app terminate-op

Terminate a running sync operation.

```bash
argocd app terminate-op my-app
```

### argocd app unset

Remove application settings.

```bash
# Remove a Helm parameter override
argocd app unset my-app --helm-set image.tag

# Remove a values file
argocd app unset my-app --values values-override.yaml

# Remove all Helm parameters
argocd app unset my-app --all-helm-set

# Remove a sync option
argocd app unset my-app --sync-option CreateNamespace
```

### argocd app enable-autosync / disable-autosync

```bash
argocd app enable-autosync my-app
argocd app disable-autosync my-app
```

---

## 4. argocd cluster — Cluster Management

### argocd cluster add

Register a cluster with ArgoCD.

```bash
# Add current kubeconfig context as a cluster
argocd cluster add my-k8s-context

# Add with a custom name
argocd cluster add my-k8s-context --name production-us-east

# Add with a service account (instead of using admin kubeconfig)
argocd cluster add my-k8s-context --service-account argocd-manager

# Add an in-cluster reference (the cluster ArgoCD runs in)
argocd cluster add --in-cluster

# Add with annotation
argocd cluster add my-k8s-context \
  --annotation environment=production

# Skip TLS verification for cluster
argocd cluster add my-k8s-context --insecure-skip-server-verification

# Use custom namespace for RBAC (default: kube-system)
argocd cluster add my-k8s-context --system-namespace kube-system
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--name <name>` | Display name for the cluster |
| `--service-account <sa>` | Use specific service account for auth |
| `--system-namespace <ns>` | Namespace for ArgoCD resources on target (default: kube-system) |
| `--namespace <ns>` | Restrict cluster to specific namespaces (comma-separated) |
| `--in-cluster` | Configure as in-cluster (loopback) |
| `--insecure-skip-server-verification` | Skip TLS verification |
| `--annotation <key=val>` | Annotations for the cluster |
| `--label <key=val>` | Labels for the cluster |
| `--kubeconfig <path>` | Path to kubeconfig file |
| `--exec-command <cmd>` | Exec command for authentication |

### argocd cluster list

```bash
# List all registered clusters
argocd cluster list

# Output as JSON
argocd cluster list -o json

# Output as YAML
argocd cluster list -o yaml
```

### argocd cluster get

```bash
# Get details for a specific cluster
argocd cluster get https://k8s.example.com

# Get by name
argocd cluster get production-cluster

# Output as JSON
argocd cluster get production-cluster -o json
```

### argocd cluster rm

```bash
# Remove a cluster
argocd cluster rm https://k8s.example.com

# Remove by name
argocd cluster rm production-cluster

# Remove in-cluster
argocd cluster rm https://kubernetes.default.svc
```

### argocd cluster rotate-auth

Rotate authentication credentials for a cluster.

```bash
argocd cluster rotate-auth https://k8s.example.com
```

---

## 5. argocd repo — Repository Management

### argocd repo add

Register a Git or Helm repository.

```bash
# Add a public Git repo
argocd repo add https://github.com/org/repo.git

# Add a private Git repo with HTTPS credentials
argocd repo add https://github.com/org/private-repo.git \
  --username myuser \
  --password mytoken

# Add a private Git repo with SSH key
argocd repo add git@github.com:org/private-repo.git \
  --ssh-private-key-path ~/.ssh/id_rsa

# Add a private Git repo with SSH key content
argocd repo add git@github.com:org/repo.git \
  --ssh-private-key-path /path/to/key \
  --insecure-skip-server-verification

# Add a Helm repo
argocd repo add https://charts.example.com \
  --type helm \
  --name my-charts

# Add a Helm repo with credentials
argocd repo add https://charts.example.com \
  --type helm \
  --name my-charts \
  --username user \
  --password pass

# Add with TLS client certificate
argocd repo add https://git.example.com/org/repo.git \
  --tls-client-cert-path /path/to/cert.pem \
  --tls-client-cert-key-path /path/to/key.pem

# Add with GitHub App authentication
argocd repo add https://github.com/org/repo.git \
  --github-app-id 12345 \
  --github-app-installation-id 67890 \
  --github-app-private-key-path /path/to/private-key.pem

# Add OCI Helm repo
argocd repo add registry-1.docker.io/myorg \
  --type helm \
  --enable-oci \
  --username user \
  --password pass
```

**Key Flags:**

| Flag | Description |
|------|-------------|
| `--type <type>` | `git` (default) or `helm` |
| `--name <name>` | Repository name/alias |
| `--username <user>` | Username for authentication |
| `--password <pass>` | Password/token for authentication |
| `--ssh-private-key-path <path>` | Path to SSH private key |
| `--insecure-skip-server-verification` | Skip TLS verification |
| `--tls-client-cert-path <path>` | TLS client certificate |
| `--tls-client-cert-key-path <path>` | TLS client certificate key |
| `--github-app-id <id>` | GitHub App ID |
| `--github-app-installation-id <id>` | GitHub App installation ID |
| `--github-app-private-key-path <path>` | GitHub App private key |
| `--github-app-enterprise-base-url <url>` | GitHub Enterprise base URL |
| `--enable-oci` | Enable OCI support |
| `--force-http-basic-auth` | Force HTTP basic auth |
| `--project <project>` | Scope repo to a specific project |

### argocd repo list

```bash
# List all repos
argocd repo list

# Output as JSON
argocd repo list -o json

# Output as YAML
argocd repo list -o yaml

# Show wide output (includes more fields)
argocd repo list -o wide
```

### argocd repo rm

```bash
# Remove a repository
argocd repo rm https://github.com/org/repo.git
```

### argocd repo get

```bash
# Get details for a specific repo
argocd repo get https://github.com/org/repo.git
```

---

## 6. argocd proj — Project Management

### argocd proj create

```bash
# Create a basic project
argocd proj create my-project \
  --description "My production project"

# Create with allowed sources
argocd proj create my-project \
  --src https://github.com/org/repo.git \
  --description "Production project"

# Create with allowed destinations
argocd proj create my-project \
  --dest https://kubernetes.default.svc,production

# Full project creation
argocd proj create my-project \
  --description "Production workloads" \
  --src https://github.com/org/repo.git \
  --src https://charts.example.com \
  --dest https://kubernetes.default.svc,production \
  --dest https://k8s2.example.com,staging

# Create from file
argocd proj create -f project.yaml
```

### argocd proj list

```bash
argocd proj list

argocd proj list -o json
```

### argocd proj get

```bash
argocd proj get my-project

argocd proj get my-project -o json
```

### argocd proj delete

```bash
argocd proj delete my-project
```

### argocd proj allow-cluster-resource

Control which cluster-scoped resources the project can manage.

```bash
# Allow managing ClusterRoles
argocd proj allow-cluster-resource my-project rbac.authorization.k8s.io ClusterRole

# Allow all resources in a group
argocd proj allow-cluster-resource my-project '*' '*'

# Deny a resource
argocd proj deny-cluster-resource my-project '*' ClusterRole
```

### argocd proj allow-namespace-scoped-resource

Control which namespace-scoped resources the project can manage.

```bash
# Allow Deployments
argocd proj allow-namespace-scoped-resource my-project apps Deployment

# Allow all resources
argocd proj allow-namespace-scoped-resource my-project '*' '*'

# Deny a resource
argocd proj deny-namespace-scoped-resource my-project '*' PodDisruptionBudget
```

### argocd proj add-source / remove-source

```bash
# Add allowed source repo
argocd proj add-source my-project https://github.com/org/repo.git

# Add wildcard source
argocd proj add-source my-project '*'

# Remove source
argocd proj remove-source my-project https://github.com/org/repo.git
```

### argocd proj add-destination / remove-destination

```bash
# Add allowed destination
argocd proj add-destination my-project https://kubernetes.default.svc production

# Wildcard namespace
argocd proj add-destination my-project https://kubernetes.default.svc '*'

# Remove destination
argocd proj remove-destination my-project https://kubernetes.default.svc production
```

### argocd proj role

Manage project roles (RBAC within a project).

```bash
# Create a role
argocd proj role create my-project ci-role

# Add a policy to a role
argocd proj role add-policy my-project ci-role \
  --action sync \
  --permission allow \
  --object my-project/*

# List roles
argocd proj role list my-project

# Get role details
argocd proj role get my-project ci-role

# Create a JWT token for a role
argocd proj role create-token my-project ci-role

# Create a token with expiration
argocd proj role create-token my-project ci-role \
  --expires-in 24h

# Delete a token
argocd proj role delete-token my-project ci-role <issued-at-epoch>

# Delete a role
argocd proj role delete my-project ci-role
```

### argocd proj windows

Sync windows restrict when syncs can occur.

```bash
# Add a sync window (deny syncs Mon-Fri 08:00-17:00 UTC)
argocd proj windows add my-project \
  --kind deny \
  --schedule "0 8 * * 1-5" \
  --duration 9h

# Add an allow window
argocd proj windows add my-project \
  --kind allow \
  --schedule "0 22 * * *" \
  --duration 4h \
  --applications my-app \
  --namespaces production

# List windows
argocd proj windows list my-project

# Enable manual sync during deny window
argocd proj windows add my-project \
  --kind deny \
  --schedule "0 8 * * 1-5" \
  --duration 9h \
  --manual-sync

# Delete a window
argocd proj windows delete my-project <window-id>
```

---

## 7. argocd account — Account Management

### argocd account list

```bash
# List all accounts
argocd account list

# Output as JSON
argocd account list -o json
```

### argocd account get

```bash
# Get current user account
argocd account get

# Get specific account
argocd account get --account myuser
```

### argocd account update-password

```bash
# Update current user's password
argocd account update-password

# Update another user's password (admin only)
argocd account update-password \
  --account myuser \
  --current-password <admin-pass> \
  --new-password <new-pass>
```

### argocd account generate-token

Generate API tokens for automation (used in CI/CD).

```bash
# Generate a token for the current user (no expiry)
argocd account generate-token

# Generate a token with expiration
argocd account generate-token --expires-in 720h

# Generate a token for a specific account (admin only)
argocd account generate-token --account ci-bot

# Generate a token for a specific account with expiry
argocd account generate-token \
  --account ci-bot \
  --expires-in 8760h  # 1 year

# Generate a token and export for CI/CD
export ARGOCD_AUTH_TOKEN=$(argocd account generate-token --account ci-bot)
```

### argocd account can-i

Check RBAC permissions.

```bash
# Can current user sync an app?
argocd account can-i sync applications 'my-project/my-app'

# Can current user create apps?
argocd account can-i create applications 'my-project/*'

# Can current user delete apps?
argocd account can-i delete applications 'my-project/my-app'
```

---

## 8. argocd admin — Admin Commands

Admin commands require ArgoCD admin privileges.

### argocd admin app

```bash
# Generate manifests for an app locally (without server)
argocd admin app generate-spec my-app

# Export all apps
argocd admin app export > all-apps.yaml

# Import apps from a file
argocd admin app import < all-apps.yaml
```

### argocd admin cluster

```bash
# Generate cluster RBAC manifests
argocd admin cluster generate-spec https://k8s.example.com

# Print ArgoCD cluster stats
argocd admin cluster stats

# Namespaced stats
argocd admin cluster stats https://k8s.example.com
```

### argocd admin settings

```bash
# Validate ArgoCD settings/config
argocd admin settings validate

# Show resource overrides configuration
argocd admin settings resource-overrides ignore-differences \
  apps/Deployment \
  --live-yaml live.yaml \
  --target-yaml target.yaml
```

### argocd admin repo

```bash
# Get repo HTTPS credentials
argocd admin repo generate-spec https://github.com/org/repo.git
```

### argocd admin dashboard

```bash
# Open ArgoCD UI in browser
argocd admin dashboard
```

### argocd admin notifications

Test and troubleshoot notification templates.

```bash
# Trigger a notification manually
argocd admin notifications trigger run on-sync-succeeded my-app

# List notification services
argocd admin notifications service list

# Test a template
argocd admin notifications template notify my-app \
  --trigger on-sync-succeeded
```

### argocd admin export / import

```bash
# Export all ArgoCD objects (for backup/migration)
argocd admin export > backup.yaml

# Export to a specific namespace
argocd admin export --namespace argocd > backup.yaml

# Import from backup
argocd admin import < backup.yaml
```

---

## 9. Sync Waves

Sync waves control the ORDER in which resources are deployed during a sync operation. Resources are deployed in ascending wave order. ArgoCD waits for all resources in one wave to become healthy before moving to the next.

### How Sync Waves Work

1. Resources are grouped by their wave number
2. Wave 0 is deployed first (default wave is 0)
3. ArgoCD waits for all resources in wave N to be **Healthy** before starting wave N+1
4. Negative wave numbers are allowed (deploy before wave 0)
5. Resources with the same wave number are deployed in parallel

### Annotation

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "5"
```

### Example: Database before Application

```yaml
# 1. Create namespace first (wave -2)
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  annotations:
    argocd.argoproj.io/sync-wave: "-2"

---
# 2. Deploy secrets/configmaps (wave -1)
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
type: Opaque
data:
  password: dXNlcjpwYXNz

---
# 3. Deploy database (wave 0 — default)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  # ...

---
# 4. Run database migrations (wave 1)
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  annotations:
    argocd.argoproj.io/sync-wave: "1"
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: migrate
        image: my-app:latest
        command: ["./migrate.sh"]
      restartPolicy: Never

---
# 5. Deploy application (wave 2)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  # ...
```

### Sync Wave Rules

- Default wave is `0` if annotation is absent
- Waves can be negative integers (e.g., `-1`, `-2`)
- Resources in the same wave deploy concurrently
- Health check determines readiness before next wave
- If a resource in a wave fails health check, the sync stops
- Custom health checks can be defined for CRDs

### CLI Interaction with Sync Waves

```bash
# Sync normally (waves are honored automatically)
argocd app sync my-app

# Monitor wave progression
argocd app wait my-app --health --timeout 300

# Sync only specific resources in a specific wave
argocd app sync my-app --resource batch:Job:db-migrate

# If a wave hangs, check which resources are not healthy
argocd app get my-app --show-params
```

---

## 10. Resource Hooks

Resource hooks are Kubernetes resources (typically Jobs or Pods) that run at specific points during sync. They are NOT subject to sync wave ordering in the same way — hooks run at defined lifecycle phases.

### Hook Types (Phases)

| Hook | When it runs |
|------|-------------|
| `PreSync` | Before any resources are applied |
| `Sync` | During sync, alongside other resources |
| `PostSync` | After all resources are healthy and synced |
| `SyncFail` | If the sync operation fails |
| `PostDelete` | After the application is deleted (cascade) |
| `Skip` | Resource is skipped entirely during sync |

### Annotation

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
```

### Hook Delete Policies

Control when hooks are cleaned up after execution.

| Policy | Description |
|--------|-------------|
| `HookSucceeded` | Delete hook after successful completion |
| `HookFailed` | Delete hook after failure |
| `BeforeHookCreation` | Delete previous hook before creating new one |

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

### Example: PreSync Database Migration

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  template:
    spec:
      containers:
      - name: migration
        image: myapp:{{ .Values.image.tag }}
        command: ["python", "manage.py", "migrate"]
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
      restartPolicy: Never
  backoffLimit: 3
```

### Example: PostSync Smoke Test

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: smoke-test
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: test
        image: curlimages/curl:latest
        command:
          - /bin/sh
          - -c
          - |
            curl -f http://my-service/health || exit 1
      restartPolicy: Never
  backoffLimit: 2
```

### Example: SyncFail Notification Hook

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: slack-notify-failure
  annotations:
    argocd.argoproj.io/hook: SyncFail
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: notify
        image: curlimages/curl:latest
        command:
          - /bin/sh
          - -c
          - |
            curl -X POST "$SLACK_WEBHOOK" \
              -H 'Content-type: application/json' \
              --data '{"text":"Sync failed for my-app!"}'
        env:
        - name: SLACK_WEBHOOK
          valueFrom:
            secretKeyRef:
              name: slack-webhook
              key: url
      restartPolicy: Never
```

### Combining Hooks and Sync Waves

Hooks run at phase level (PreSync, Sync, PostSync). Within a phase, sync waves apply:

```yaml
# This hook runs FIRST in PreSync phase (wave -1)
apiVersion: batch/v1
kind: Job
metadata:
  name: create-db
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/sync-wave: "-1"

---
# This hook runs SECOND in PreSync phase (wave 0)
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate-db
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/sync-wave: "0"
```

### Hook Status Check via CLI

```bash
# See hook status during sync
argocd app get my-app

# Watch running hooks
argocd app get my-app --show-operation

# Wait for sync with hooks to complete
argocd app wait my-app --operation --timeout 600
```

---

## 11. Diffing Configuration

ArgoCD can be configured to ignore certain differences to reduce noise. This is configured at the application or resource level.

### Ignore Differences in Application Spec

Add `ignoreDifferences` to the Application manifest:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  ignoreDifferences:
  # Ignore entire fields
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas          # Ignore HPA-managed replicas
    - /spec/template/spec/initContainers

  # Ignore by JQ path expression
  - group: apps
    kind: Deployment
    jqPathExpressions:
    - .spec.template.spec.containers[].resources.limits

  # Ignore fields managed by admission controllers
  - group: ""
    kind: ServiceAccount
    jsonPointers:
    - /secrets

  # Ignore across all resources of a type
  - group: "*"
    kind: "*"
    managedFieldsManagers:
    - kube-controller-manager
    - kube-scheduler
```

### Global Ignore Differences (in ArgoCD ConfigMap)

Edit `argocd-cm` ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  resource.customizations.ignoreDifferences.apps_Deployment: |
    jsonPointers:
    - /spec/replicas
  resource.customizations.ignoreDifferences.all: |
    managedFieldsManagers:
    - kube-controller-manager
```

### Resource Actions and Health Checks

Custom health checks for CRDs:

```yaml
# In argocd-cm
data:
  resource.customizations.health.argoproj.io_Rollout: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.phase == "Paused" then
        hs.status = "Suspended"
        hs.message = "Rollout is paused"
        return hs
      end
      if obj.status.phase == "Degraded" then
        hs.status = "Degraded"
        hs.message = obj.status.message
        return hs
      end
    end
    hs.status = "Healthy"
    return hs
```

### CLI Commands for Diffing

```bash
# View current diff
argocd app diff my-app

# Diff with refresh (re-fetch from Git)
argocd app diff my-app --refresh

# Hard refresh (bypass cache)
argocd app diff my-app --hard-refresh

# Diff against a specific revision
argocd app diff my-app --revision abc123

# Diff from local manifests
argocd app diff my-app --local ./manifests/

# Validate admin settings for ignoreDifferences
argocd admin settings resource-overrides ignore-differences \
  apps/Deployment \
  --live-yaml live.yaml \
  --target-yaml target.yaml
```

---

## 12. App Deletion

ArgoCD supports two deletion modes: cascade (deletes Kubernetes resources) and non-cascade (only removes the ArgoCD Application record).

### Non-Cascade Deletion (Orphan Resources)

Removes the Application from ArgoCD but leaves Kubernetes resources running:

```bash
# Remove the Application record only
argocd app delete my-app --cascade=false

# Skip confirmation
argocd app delete my-app --cascade=false --yes
```

### Cascade Deletion (Delete All Resources)

Removes the Application AND all managed Kubernetes resources:

```bash
# Cascade delete (default behavior in CLI when --cascade is set)
argocd app delete my-app --cascade

# Skip confirmation
argocd app delete my-app --cascade --yes
```

### The Finalizer

ArgoCD uses a finalizer to control cascade deletion. When a finalizer is present, deleting the Application triggers cascade deletion.

**Finalizer name:** `resources-finalizer.argocd.argoproj.io`

```yaml
# Application with cascade finalizer
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  # ...
```

**Background deletion finalizer** (delete resources in background):

```yaml
metadata:
  finalizers:
    - resources-finalizer.argocd.argoproj.io/background
```

### Stuck Deletion: Removing the Finalizer

If cascade deletion gets stuck (e.g., a namespace won't delete), remove the finalizer manually:

```bash
# Option 1: Using kubectl patch
kubectl patch app my-app \
  -n argocd \
  --type json \
  --patch='[{"op":"remove","path":"/metadata/finalizers"}]'

# Option 2: Using kubectl edit
kubectl edit app my-app -n argocd
# Remove the finalizers section and save

# Option 3: Via ArgoCD CLI (non-cascade)
argocd app delete my-app --cascade=false
```

### Propagation Policy for Cascade Deletion

Control how Kubernetes garbage-collects resources:

```yaml
# In the CLI
argocd app delete my-app --cascade \
  --propagation-policy foreground  # or background, orphan
```

### App-of-Apps Deletion

When using App-of-Apps pattern, delete in order:

```bash
# 1. Disable auto-sync on children first
argocd app set child-app-1 --sync-policy none
argocd app set child-app-2 --sync-policy none

# 2. Delete child apps
argocd app delete child-app-1 --cascade --yes
argocd app delete child-app-2 --cascade --yes

# 3. Delete parent app
argocd app delete parent-app --cascade --yes
```

---

## 13. CI/CD Pipeline Best Practices

### Pattern 1: Authenticate Once Per Pipeline

```bash
#!/bin/bash
# Use environment variables — no login step needed in each stage

export ARGOCD_SERVER="${ARGOCD_SERVER:-argocd.example.com}"
# ARGOCD_AUTH_TOKEN should be a CI secret

# All argocd commands will pick up ARGOCD_SERVER and ARGOCD_AUTH_TOKEN
argocd app sync my-app --insecure
argocd app wait my-app --health --timeout 300 --insecure
```

### Pattern 2: Generate a CI Bot Token

```bash
# As ArgoCD admin, create a service account and generate a long-lived token
argocd account generate-token \
  --account ci-bot \
  --expires-in 8760h  # 1 year

# Store in CI secrets as ARGOCD_AUTH_TOKEN
```

### Pattern 3: Update Image and Sync

```bash
#!/bin/bash
set -euo pipefail

APP_NAME="my-app"
IMAGE_TAG="${CI_COMMIT_SHA:0:8}"
NAMESPACE="production"

echo "Updating image tag to ${IMAGE_TAG}..."
argocd app set "${APP_NAME}" \
  --helm-set image.tag="${IMAGE_TAG}" \
  --insecure

echo "Triggering sync..."
argocd app sync "${APP_NAME}" \
  --timeout 30 \
  --insecure

echo "Waiting for health..."
argocd app wait "${APP_NAME}" \
  --health \
  --timeout 300 \
  --insecure

echo "Deployment complete!"
```

### Pattern 4: Diff Before Sync (Preview Changes)

```bash
#!/bin/bash
# Show diff and exit 1 if there are unexpected changes

argocd app diff my-app --insecure
DIFF_EXIT=$?

if [ $DIFF_EXIT -eq 1 ]; then
  echo "Diff detected — proceeding with sync"
  argocd app sync my-app --insecure
elif [ $DIFF_EXIT -eq 0 ]; then
  echo "No diff — application is already in sync"
elif [ $DIFF_EXIT -eq 2 ]; then
  echo "Error computing diff" && exit 1
fi
```

### Pattern 5: Sync with Retry

```bash
argocd app sync my-app \
  --retry-limit 3 \
  --retry-backoff-duration 10s \
  --retry-backoff-max-duration 60s \
  --retry-backoff-factor 2 \
  --timeout 300 \
  --insecure
```

### Pattern 6: Blue-Green / Canary with Argo Rollouts

```bash
#!/bin/bash
# Sync the application (this triggers a Rollout)
argocd app sync my-app --insecure

# Wait for the rollout to be paused (at canary step)
argocd app wait my-app --suspended --timeout 300 --insecure

echo "Rollout paused — run manual validation..."
# ... run integration tests here ...

# Promote the rollout
argocd app actions run my-app promote \
  --kind Rollout \
  --resource-name my-rollout \
  --insecure

# Wait for healthy
argocd app wait my-app --health --timeout 300 --insecure
```

### Pattern 7: Multi-Cluster Deploy with Parallel Sync

```bash
#!/bin/bash
# Deploy to staging first, then production

# Sync staging
argocd app sync my-app-staging --async --insecure
argocd app wait my-app-staging --health --timeout 300 --insecure

# Run E2E tests against staging
./run-e2e-tests.sh staging

# Only proceed to production if tests pass
argocd app sync my-app-production --insecure
argocd app wait my-app-production --health --timeout 300 --insecure
```

### Pattern 8: ApplicationSet for Multi-Env

Rather than managing many apps with the CLI, use ApplicationSet:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: my-app-environments
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - env: staging
        cluster: https://staging-k8s.example.com
        namespace: staging
      - env: production
        cluster: https://prod-k8s.example.com
        namespace: production
  template:
    metadata:
      name: "my-app-{{env}}"
    spec:
      project: my-project
      source:
        repoURL: https://github.com/org/repo.git
        targetRevision: main
        path: "overlays/{{env}}"
      destination:
        server: "{{cluster}}"
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Pattern 9: Wait with Health Checks in Stages

```bash
#!/bin/bash
# Structured deployment with health verification at each stage

deploy_and_verify() {
  local APP=$1
  local TIMEOUT=${2:-300}

  echo "[$(date)] Starting sync for ${APP}..."
  argocd app sync "${APP}" \
    --prune \
    --insecure \
    --timeout 60

  echo "[$(date)] Waiting for operation to complete..."
  argocd app wait "${APP}" \
    --operation \
    --timeout "${TIMEOUT}" \
    --insecure

  echo "[$(date)] Waiting for health..."
  argocd app wait "${APP}" \
    --health \
    --timeout "${TIMEOUT}" \
    --insecure

  echo "[$(date)] ${APP} deployed and healthy!"
}

deploy_and_verify "my-infra-app" 120
deploy_and_verify "my-db-app" 300
deploy_and_verify "my-backend-app" 180
deploy_and_verify "my-frontend-app" 120
```

### Pattern 10: CI/CD Using `--local` for Manifest Preview

```bash
#!/bin/bash
# Build manifests locally and preview against live cluster

# Generate manifests locally (e.g., with Helm or Kustomize)
helm template my-app ./chart -f values-prod.yaml > /tmp/rendered.yaml

# Preview diff without pushing to Git
argocd app diff my-app \
  --local /tmp \
  --insecure

# Then sync from Git as usual after review
argocd app sync my-app --insecure
```

### Key Environment Variables

| Variable | Description |
|----------|-------------|
| `ARGOCD_SERVER` | ArgoCD server hostname (replaces `--server`) |
| `ARGOCD_AUTH_TOKEN` | Bearer token (replaces `--auth-token`) |
| `ARGOCD_OPTS` | Additional global flags |

Example `ARGOCD_OPTS`:

```bash
export ARGOCD_OPTS="--insecure --grpc-web"
```

### Sync Options Reference

Sync options can be set per-app or per-sync operation:

| Option | Description |
|--------|-------------|
| `CreateNamespace=true` | Auto-create destination namespace |
| `PrunePropagationPolicy=foreground` | Cascade delete policy |
| `PruneLast=true` | Prune resources after sync |
| `ApplyOutOfSyncOnly=true` | Only apply out-of-sync resources |
| `Replace=true` | Use kubectl replace instead of apply |
| `ServerSideApply=true` | Use server-side apply |
| `FailOnSharedResource=true` | Fail if resources managed by another app |
| `Validate=false` | Skip manifest validation |
| `RespectIgnoreDifferences=true` | Apply ignoreDifferences during sync |
| `SkipDryRunOnMissingResource=true` | Skip dry-run for missing CRDs |

```bash
# Set sync options at app level
argocd app set my-app \
  --sync-option CreateNamespace=true \
  --sync-option ServerSideApply=true

# Set sync options at sync time
argocd app sync my-app \
  --sync-option ApplyOutOfSyncOnly=true \
  --sync-option PruneLast=true
```

---

## Quick Reference Card

### Most Common Commands

```bash
# Login
argocd login argocd.example.com --username admin --password <pass> --insecure

# List apps
argocd app list

# Sync and wait
argocd app sync my-app && argocd app wait my-app --health --timeout 300

# Get app status
argocd app get my-app

# View diff
argocd app diff my-app

# View history
argocd app history my-app

# Rollback
argocd app rollback my-app <history-id>

# Delete (cascade)
argocd app delete my-app --cascade --yes

# Generate API token for CI
argocd account generate-token --account ci-bot --expires-in 8760h

# Sync with all safety options
argocd app sync my-app \
  --prune \
  --timeout 300 \
  --retry-limit 3 \
  --insecure
```

---

*Reference: https://argo-cd.readthedocs.io/en/stable/*
*ArgoCD stable documentation — covers CLI v2.x*

---

# Part 4: Security, RBAC, SSO & Secrets Management

# ArgoCD Security, RBAC, SSO & Secrets Management Reference

Comprehensive reference for securing ArgoCD deployments. Covers RBAC policy syntax, SSO/Dex connectors, secrets management, notifications, TLS, and multi-tenancy hardening.

Sources: Official ArgoCD docs (stable), Dex IdP docs.

---

## Table of Contents

1. [Security Hardening Overview](#1-security-hardening-overview)
2. [TLS Configuration](#2-tls-configuration)
3. [Authentication: Local Users](#3-authentication-local-users)
4. [Authentication: SSO with Dex](#4-authentication-sso-with-dex)
5. [Authentication: External OIDC (no Dex)](#5-authentication-external-oidc-no-dex)
6. [RBAC: Policy Syntax Reference](#6-rbac-policy-syntax-reference)
7. [RBAC: Built-in Roles](#7-rbac-built-in-roles)
8. [RBAC: Custom Roles & Policy Examples](#8-rbac-custom-roles--policy-examples)
9. [AppProject: Multi-Tenancy & Project RBAC](#9-appproject-multi-tenancy--project-rbac)
10. [Secrets Management](#10-secrets-management)
11. [Notifications](#11-notifications)
12. [Audit Logging & Observability](#12-audit-logging--observability)
13. [ApplicationSet Security](#13-applicationset-security)

---

## 1. Security Hardening Overview

### Key Vulnerabilities to Mitigate

| CVE / Issue | Risk | Mitigation |
|---|---|---|
| Default admin password derived from pod name | High | Change immediately or disable admin |
| API tokens for built-in users never expire | High | Use SSO tokens (24h expiry) or set explicit expiry |
| Brute force login (pre v1.5.3) | Medium | Rate limiting is now built-in; enforce HTTPS |
| Unauthorized git repo write access | Critical | Restrict repo write access; disable unused config tools |
| Directory manifests memory DoS | Medium | Set `reposerver.max.combined.directory.manifests.size` |

### Hardening Checklist

```yaml
# argocd-cm: Core security settings
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  # 1. Disable built-in admin after SSO is configured
  admin.enabled: "false"

  # 2. Enable anonymous access only if needed (defaults to false)
  users.anonymous.enabled: "false"

  # 3. Set base URL (required for SSO callbacks)
  url: https://argocd.example.com

  # 4. Limit memory for directory-type apps (prevents DoS)
  # Set in argocd-cmd-params-cm instead:
  # reposerver.max.combined.directory.manifests.size: "10M"
```

```yaml
# argocd-cmd-params-cm: Runtime parameters
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd
data:
  # Enforce minimum TLS version
  server.tls.minversion: "1.2"
  # Limit manifest memory
  reposerver.max.combined.directory.manifests.size: "10M"
  # Enable strict repo-server TLS validation
  server.repo.server.strict.tls: "true"
```

```yaml
# argocd-rbac-cm: Default deny, require explicit grants
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  # Set default policy to readonly (not admin)
  policy.default: role:readonly
  # Or set to empty string for full deny-by-default:
  # policy.default: ""
  scopes: '[groups, email]'
```

---

## 2. TLS Configuration

ArgoCD manages TLS for three endpoints: `argocd-server` (user-facing), `argocd-repo-server` (internal), and `argocd-dex-server` (OIDC).

### argocd-server TLS

Certificate selection priority:
1. `argocd-server-tls` secret (recommended, supports hot-reload)
2. `argocd-secret` (deprecated)
3. Auto-generated self-signed cert

```bash
# Create TLS secret from certificate files
kubectl create -n argocd secret tls argocd-server-tls \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem
```

TLS flags for `argocd-server`:
```
--tlsminversion 1.2       # Minimum TLS version (default: 1.2)
--tlsmaxversion 1.3       # Maximum TLS version
--tlsciphers <list>       # Custom cipher suite
--insecure                # Disable TLS entirely (dev only)
```

### argocd-repo-server TLS

```bash
# Certificate must include SANs:
# DNS:argocd-repo-server
# DNS:argocd-repo-server.argocd.svc
kubectl create -n argocd secret tls argocd-repo-server-tls \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem

# Pod restart required after cert update (no hot-reload)
kubectl rollout restart deployment/argocd-repo-server -n argocd
```

For self-signed certs, add CA to the secret:
```bash
kubectl -n argocd patch secret argocd-repo-server-tls \
  --type=json \
  -p='[{"op":"add","path":"/data/ca.crt","value":"'$(base64 -w0 /path/to/ca.crt)'"}]'
```

### argocd-dex-server TLS

```bash
kubectl create -n argocd secret tls argocd-dex-server-tls \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem

# Requires pod restart
kubectl rollout restart deployment/argocd-dex-server -n argocd
```

### Strict Inter-Component TLS Validation

By default, internal component-to-component connections use non-validating TLS. Enable strict validation:

```yaml
# Patch argocd-server deployment args
- --repo-server-strict-tls     # Validate repo-server cert
- --dex-server-strict-tls      # Validate dex-server cert

# Patch argocd-application-controller args
- --repo-server-strict-tls

# Patch argocd-applicationset-controller args
- --repo-server-strict-tls

# Patch argocd-notifications-controller args
- --argocd-repo-server-strict-tls
```

### Service Mesh / mTLS Integration

When using Istio or Linkerd sidecars for mTLS, disable ArgoCD's built-in TLS on internal components:

```yaml
# argocd-repo-server: disable TLS, bind to localhost only
- --disable-tls
- --listen=127.0.0.1

# Connecting components: use plaintext to sidecar
- --repo-server-plaintext
- --repo-server=<sidecar-address>
- --dex-server-plaintext
- --dex-server=<sidecar-address>
```

---

## 3. Authentication: Local Users

Local accounts are defined in `argocd-cm`. Use for automation tokens and small team members. Maximum username length: 32 characters.

### Defining Local Users

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  # User with both UI login and API key capabilities
  accounts.alice: login, apiKey

  # Automation account with only API key capability
  accounts.ci-bot: apiKey

  # Disable a user without deleting
  accounts.alice.enabled: "false"
```

### Managing Accounts via CLI

```bash
# List all accounts
argocd account list

# View specific account details
argocd account get --account alice

# Update a user's password (as admin or the user themselves)
argocd account update-password \
  --account alice \
  --current-password <admin-password> \
  --new-password <new-password>

# Generate an API token for automation
argocd account generate-token --account ci-bot

# Generate token with expiry (seconds)
argocd account generate-token --account ci-bot --expires-in 24h
```

### Rate Limiting Configuration

Configure via environment variables on argocd-server:
```
ARGOCD_SESSION_FAILURE_MAX_FAIL_COUNT=5      # Max failed attempts (default: 5)
ARGOCD_SESSION_FAILURE_WINDOW_SECONDS=300    # Window in seconds (default: 300)
ARGOCD_SESSION_MAX_CACHE_SIZE=1000           # Cache entries (default: 1000)
ARGOCD_MAX_CONCURRENT_LOGIN_REQUESTS_COUNT=50 # Concurrent logins (default: 50)
```

### Secret References in ConfigMaps

Values starting with `$` in ArgoCD ConfigMaps are resolved from Kubernetes Secrets:

```yaml
# In argocd-cm:
oidc.clientSecret: $oidc.azure.clientSecret
# → looks up key "oidc.azure.clientSecret" in "argocd-secret"

# For external secrets (must have label app.kubernetes.io/part-of: argocd):
oidc.clientSecret: $my-secret:client.secret
# → looks up key "client.secret" in secret named "my-secret"
```

---

## 4. Authentication: SSO with Dex

Dex is the bundled OIDC provider. Use when your identity provider doesn't natively support OIDC (e.g., SAML, LDAP), or when you need Dex features like GitHub org/team mapping.

### Dex Base Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.example.com
  dex.config: |
    # Dex logger settings (optional)
    logger:
      level: debug
      format: json
    connectors:
      # ... connector config below
```

### GitHub Dex Connector

```yaml
dex.config: |
  connectors:
  - type: github
    id: github
    name: GitHub
    config:
      clientID: $dex.github.clientID
      clientSecret: $dex.github.clientSecret
      redirectURI: https://argocd.example.com/api/dex/callback

      # Restrict to specific organizations and teams
      orgs:
      - name: my-org                    # All members of my-org
      - name: my-org-with-teams
        teams:
        - platform-team
        - sre-team
      # User MUST belong to at least ONE org/team to authenticate

      # Optional: format for team names in RBAC
      # Options: name, slug, both
      teamNameField: slug

      # Optional: load all orgs when neither org nor orgs is set
      loadAllGroups: false

      # Optional: use GitHub login as ID instead of numeric ID
      useLoginAsID: false
```

For GitHub Enterprise:
```yaml
    config:
      hostName: github.example.com      # Enterprise hostname
      rootCA: /etc/ssl/certs/ca.crt     # For self-signed certs
      clientID: $dex.github.clientID
      clientSecret: $dex.github.clientSecret
      redirectURI: https://argocd.example.com/api/dex/callback
      orgs:
      - name: my-enterprise-org
```

RBAC mapping for GitHub (groups appear as `org:team`):
```yaml
# argocd-rbac-cm
data:
  policy.csv: |
    g, my-org:platform-team, role:admin
    g, my-org:dev-team, role:readonly
    g, my-org-with-teams:sre-team, role:admin
  scopes: '[groups, email]'
```

### GitLab Dex Connector

```yaml
dex.config: |
  connectors:
  - type: gitlab
    id: gitlab
    name: GitLab
    config:
      baseURL: https://gitlab.com       # Or self-hosted URL
      clientID: $dex.gitlab.clientID
      clientSecret: $dex.gitlab.clientSecret
      redirectURI: https://argocd.example.com/api/dex/callback

      # Restrict to specific GitLab groups
      groups:
      - my-group
      - my-group/sub-group

      # Use GitLab handle instead of internal ID
      useLoginAsID: false

      # Include group permission levels in claims
      getGroupsPermission: false
```

Required GitLab OAuth scopes: `read_user`, `openid`.

### Google Dex Connector (OIDC, no groups)

```yaml
dex.config: |
  connectors:
  - type: oidc
    id: google
    name: Google
    config:
      issuer: https://accounts.google.com
      clientID: $dex.google.clientID
      clientSecret: $dex.google.clientSecret
      redirectURI: https://argocd.example.com/api/dex/callback
```

### Google Dex Connector (with Google Groups)

Requires a service account with Domain-Wide Delegation and Directory API access:

```yaml
dex.config: |
  connectors:
  - type: google
    id: google
    name: Google
    config:
      redirectURI: https://argocd.example.com/api/dex/callback
      clientID: $dex.google.clientID
      clientSecret: $dex.google.clientSecret

      # Service account JSON file (mount as volume)
      serviceAccountFilePath: /tmp/oidc/googleAuth.json

      # Admin user for impersonation (Directory API)
      adminEmail: admin@example.com
```

### LDAP Dex Connector

```yaml
dex.config: |
  connectors:
  - type: ldap
    id: ldap
    name: LDAP
    config:
      # TLS on port 636 (recommended over 389 plaintext)
      host: ldap.example.com:636
      rootCA: /etc/dex/ldap.ca

      # Service account for directory searches
      bindDN: uid=serviceaccount,cn=users,dc=example,dc=com
      bindPW: $dex.ldap.bindPW

      usernamePrompt: SSO Username

      userSearch:
        baseDN: cn=users,dc=example,dc=com
        filter: "(objectClass=person)"
        username: uid
        idAttr: uid
        emailAttr: mail
        nameAttr: name
        preferredUsernameAttr: uid

      groupSearch:
        baseDN: cn=groups,dc=example,dc=com
        filter: "(objectClass=group)"
        userMatchers:
        - userAttr: uid
          groupAttr: member
        nameAttr: name
```

### Microsoft/Azure AD via Dex (SAML)

```yaml
dex.config: |
  connectors:
  - type: saml
    id: saml
    name: Microsoft
    config:
      entityIssuer: https://argocd.example.com/api/dex/callback
      ssoURL: https://login.microsoftonline.com/{tenant-id}/saml2
      caData: <BASE64-ENCODED-SIGNING-CERT>
      usernameAttr: email
      emailAttr: email
      groupsAttr: Group
      redirectURI: https://argocd.example.com/api/dex/callback
```

---

## 5. Authentication: External OIDC (no Dex)

Use when you already have an OIDC-compliant provider: Okta, Azure AD, Auth0, Keycloak, etc.

### Generic OIDC Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.example.com
  oidc.config: |
    name: MyProvider
    issuer: https://idp.example.com
    clientID: argocd-client-id
    clientSecret: $oidc.myProvider.clientSecret

    # Scopes to request (default includes openid, profile, email, groups)
    requestedScopes:
    - openid
    - profile
    - email
    - groups

    # Request specific claims in ID token
    requestedIDTokenClaims:
      groups:
        essential: true

    # Separate client ID for CLI (PKCE flow)
    cliClientID: argocd-cli-client-id

    # Enable PKCE (recommended for SPA/CLI clients)
    enablePKCEAuthentication: true

    # Fetch groups from UserInfo endpoint when not in token
    enableUserInfoGroups: true
    userInfoPath: /userinfo
    userInfoCacheExpiration: "5m"

    # Custom logout endpoint
    logoutURL: https://idp.example.com/logout

    # Custom CA for provider verification
    rootCA: |
      -----BEGIN CERTIFICATE-----
      ...
      -----END CERTIFICATE-----

    # Validate token audience
    allowedAudiences:
    - argocd-client-id
```

### Okta OIDC (Direct, no Dex)

```yaml
oidc.config: |
  name: Okta
  issuer: https://your-org.okta.com/oauth2/aus9abcdefg7
  clientID: 0oa9abcdefgh123AB5d7
  clientSecret: $oidc.okta.clientSecret
  requestedScopes: ["openid", "profile", "email", "groups"]
  requestedIDTokenClaims:
    groups:
      essential: true
  # Optional: CLI client (Single-Page App integration in Okta)
  cliClientID: 0oa9cliClientID
```

```yaml
# argocd-rbac-cm
data:
  policy.csv: |
    g, argocd-admins, role:admin
    g, argocd-devs, role:readonly
  scopes: '[email, groups]'
```

### Microsoft Entra ID (Azure AD) OIDC (Direct, no Dex)

```yaml
oidc.config: |
  name: Azure
  issuer: https://login.microsoftonline.com/{directory_tenant_id}/v2.0
  clientID: {azure_ad_application_client_id}
  clientSecret: $oidc.azure.clientSecret
  requestedIDTokenClaims:
    groups:
      essential: true
  requestedScopes:
  - openid
  - profile
  - email
```

```yaml
# argocd-rbac-cm: Use Azure group object IDs
data:
  policy.csv: |
    g, "84ce98d1-e359-4f3b-85af-985b458de3c6", role:admin
  scopes: '[groups, email]'
```

---

## 6. RBAC: Policy Syntax Reference

ArgoCD uses Casbin for RBAC with two statement types.

### P Statements (Permission Rules)

```
p, <subject>, <resource>, <action>, <object>, <effect>
```

- **subject**: role name (e.g., `role:admin`), user (e.g., `user@example.com`), or group (e.g., `my-org:devs`)
- **resource**: see resource table below
- **action**: get, create, update, delete, sync, action, override, invoke
- **object**: resource-specific identifier (supports `*` wildcard)
- **effect**: `allow` or `deny` — deny always takes priority

### G Statements (Group/Role Assignments)

```
g, <user-or-group>, <role>
```

Maps SSO users/groups or local users to roles. Groups come from OIDC token claims.

### Resource Types and Valid Actions

| Resource | Valid Actions |
|---|---|
| `applications` | get, create, update, delete, sync, action, override |
| `applicationsets` | get, create, update, delete |
| `clusters` | get, create, update, delete |
| `projects` | get, create, update, delete |
| `repositories` | get, create, update, delete |
| `accounts` | get, update |
| `certificates` | get, create, delete |
| `gpgkeys` | get, create, delete |
| `logs` | get |
| `exec` | create |
| `extensions` | invoke |

### Object Format by Resource

**Applications:**
```
# Standard: <project>/<app-name>
p, role:dev, applications, get, my-project/*, allow

# With app-in-any-namespace: <project>/<namespace>/<app-name>
p, role:dev, applications, get, my-project/staging/*, allow
```

**Fine-grained application update/delete (sub-resources):**
```
# Format: <action>/<group>/<kind>/<namespace>/<name>
p, role:dev, applications, delete/*/Pod/*/*, prod/my-app, allow
p, role:dev, applications, update/*/Deployment/*/*, prod/my-app, allow

# Wildcard group (for core resources like Pod, ConfigMap):
p, role:dev, applications, update/*, staging/*, allow
```

**Custom Resource Actions:**
```
# Format: action/<group>/<kind>/<action-name>
p, role:ops, applications, action/extensions/DaemonSet/*, default/*, allow
p, role:ops, applications, action//Pod/maintenance-off, default/*, allow
```

**Extensions:**
```
# Must also have get on the application
p, role:dev, applications, get, default/*, allow
p, role:dev, extensions, invoke, httpbin, allow
```

### Deny Rules

Deny always overrides allow, regardless of order:
```
p, role:dev, applications, delete, prod/*, deny
p, role:dev, applications, delete, staging/*, allow
```

### Policy Matching Modes

```yaml
# argocd-rbac-cm
data:
  # glob (default): * matches any sequence of characters
  policy.matchMode: glob

  # regex: use regular expressions
  policy.matchMode: regex
```

---

## 7. RBAC: Built-in Roles

### role:readonly

Read-only access to all resources across all projects.

Equivalent to:
```
p, role:readonly, applications,    get, */*, allow
p, role:readonly, applicationsets, get, */*, allow
p, role:readonly, clusters,        get, *, allow
p, role:readonly, repositories,    get, *, allow
p, role:readonly, projects,        get, *, allow
p, role:readonly, logs,            get, */*, allow
```

### role:admin

Unrestricted access to all resources. Assigned to the `admin` local user by default.

### Default Policy

```yaml
# argocd-rbac-cm
data:
  # All authenticated users inherit this role
  policy.default: role:readonly

  # Strict: authenticated users have no permissions by default
  # policy.default: ""
```

**Warning**: Default policy applies to ALL authenticated users and cannot be blocked by deny rules.

---

## 8. RBAC: Custom Roles & Policy Examples

### Full argocd-rbac-cm Example

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  scopes: '[groups, email]'

  policy.csv: |
    # === Admin access ===
    g, my-org:platform-team, role:admin
    g, admin@example.com, role:admin

    # === Developer role: sync & read in dev/staging projects ===
    p, role:developer, applications, get,    dev/*, allow
    p, role:developer, applications, sync,   dev/*, allow
    p, role:developer, applications, get,    staging/*, allow
    p, role:developer, applications, sync,   staging/*, allow
    p, role:developer, applications, get,    prod/*, allow
    p, role:developer, logs,         get,    */*, allow
    g, my-org:developers, role:developer

    # === Ops role: can deploy to prod but not delete ===
    p, role:ops, applications, get,    */*, allow
    p, role:ops, applications, sync,   */*, allow
    p, role:ops, applications, update, */*, allow
    p, role:ops, applications, delete, prod/*, deny
    p, role:ops, applications, delete, */*, allow
    g, my-org:ops-team, role:ops

    # === Readonly SSO group ===
    g, my-org:viewers, role:readonly

    # === Local CI bot with direct policy ===
    p, ci-bot, applications, sync,   */*, allow
    p, ci-bot, applications, get,    */*, allow
```

### Additional Policy Files (Policy Overlays)

```yaml
# Additional keys matching pattern policy.<any-string>.csv are merged alphabetically
data:
  policy.tester-overlay.csv: |
    p, role:tester, applications, *, staging/*, allow
    g, my-org:qa-team, role:tester
```

### RBAC Validation and Testing

```bash
# Validate RBAC config from file
argocd admin settings rbac validate --policy-file /path/to/policy.csv

# Test if a subject can perform an action (against live cluster)
argocd admin settings rbac can role:developer applications sync dev/my-app

# Test against local config files
argocd admin settings rbac can \
  --policy-file /path/to/policy.csv \
  --default-role role:readonly \
  role:developer applications sync dev/my-app

# Test with server config
argocd admin settings rbac can \
  --server argocd.example.com \
  my-group applications get staging/my-app
```

---

## 9. AppProject: Multi-Tenancy & Project RBAC

AppProjects are the primary multi-tenancy primitive. They scope repositories, destination clusters/namespaces, and define project-local RBAC roles with JWT tokens.

### Complete AppProject Specification

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-alpha
  namespace: argocd
  # Prevent accidental deletion
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  description: "Team Alpha project - owns staging and production namespaces"

  # Allowed source repositories (wildcards supported)
  sourceRepos:
  - https://github.com/my-org/team-alpha-config
  - https://github.com/my-org/shared-charts
  - "!https://github.com/my-org/forbidden-repo"  # Negation: deny this repo

  # Allowed deployment destinations
  destinations:
  - server: https://kubernetes.default.svc    # In-cluster
    namespace: team-alpha-staging
  - server: https://prod-cluster.example.com
    namespace: team-alpha-production
  # Wildcards:
  - server: "*"
    namespace: team-alpha-*

  # Cluster-scoped resources allowed (empty = none allowed)
  clusterResourceWhitelist:
  - group: ""
    kind: Namespace
  - group: rbac.authorization.k8s.io
    kind: ClusterRole

  # Cluster-scoped resources explicitly denied
  clusterResourceBlacklist:
  - group: "*"
    kind: ClusterRoleBinding

  # Namespace-scoped resources denied (others allowed)
  namespaceResourceBlacklist:
  - group: ""
    kind: ResourceQuota
  - group: ""
    kind: LimitRange

  # Namespace-scoped resources explicitly allowed
  # (if set, ONLY these are allowed)
  # namespaceResourceWhitelist:
  # - group: apps
  #   kind: Deployment

  # Alert on resources in destination not managed by ArgoCD
  orphanedResources:
    warn: true

  # Restrict sync to specific time windows
  syncWindows:
  - kind: allow
    schedule: "10 1 * * *"   # cron: 1:10 AM daily
    duration: 1h
    applications:
    - "*"
  - kind: deny
    schedule: "0 22 * * 5"   # Friday 10pm
    duration: 16h
    namespaces:
    - team-alpha-production
    manualSync: true          # Allow manual override during deny window

  # Restrict apps to clusters owned by this project
  permitOnlyProjectScopedClusters: true

  # Project-level RBAC roles
  roles:
  - name: developer
    description: "Developer access within team-alpha project"
    policies:
    - p, proj:team-alpha:developer, applications, get,  team-alpha/*, allow
    - p, proj:team-alpha:developer, applications, sync, team-alpha/*, allow
    - p, proj:team-alpha:developer, logs,         get,  team-alpha/*, allow
    groups:
    - my-org:team-alpha-devs
    - developer@example.com

  - name: ci-deployer
    description: "CI/CD automation role"
    policies:
    - p, proj:team-alpha:ci-deployer, applications, get,    team-alpha/*, allow
    - p, proj:team-alpha:ci-deployer, applications, sync,   team-alpha/*, allow
    - p, proj:team-alpha:ci-deployer, applications, update, team-alpha/*, allow
    # JWT tokens for this role (generated via CLI)
    jwtTokens:
    - iat: 1696000000    # issued-at timestamp
```

### Generating JWT Tokens for Project Roles

```bash
# Generate a token for a project role (automation use)
argocd proj role create-token team-alpha ci-deployer

# With expiry (e.g., 30 days)
argocd proj role create-token team-alpha ci-deployer --expires-in 720h

# List tokens for a role
argocd proj role list-tokens team-alpha ci-deployer

# Delete a token
argocd proj role delete-token team-alpha ci-deployer <issued-at>

# Use token in automation
export ARGOCD_AUTH_TOKEN=<token>
argocd app sync team-alpha-app --auth-token $ARGOCD_AUTH_TOKEN
```

### Project Policy Naming Convention

Project role policies MUST use the prefix `proj:<project-name>:<role-name>`:
```
p, proj:team-alpha:developer, applications, sync, team-alpha/*, allow
```

Without this prefix, the policy is ignored during authorization.

### Multi-Tenancy Patterns

**Pattern 1: One project per team**
```yaml
# Each team gets their own AppProject
# Teams can self-manage resources within their project scope
# Platform team has role:admin globally
```

**Pattern 2: Environment-based projects**
```yaml
# dev-project: wide permissions, many teams
# staging-project: restricted, requires approval
# prod-project: ops-only sync, developer read-only
```

**Pattern 3: Self-service with project-scoped clusters**
```yaml
spec:
  permitOnlyProjectScopedClusters: true
  # Teams add their own clusters to the project
  # Cannot deploy to clusters owned by other projects
```

**Security Warning**: Any project that can deploy to the `argocd` namespace effectively has admin access. Always restrict `argocd` namespace access in `destinations`.

---

## 10. Secrets Management

ArgoCD recommends **destination-cluster approaches** where the target cluster manages secrets independently. ArgoCD's manifest generation step is not the right place to handle secrets.

### Recommended: Destination-Cluster Approaches

#### Bitnami Sealed Secrets

Encrypt secrets client-side; only the cluster can decrypt them. Safe to commit to git.

```bash
# Install Sealed Secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml

# Seal a secret
kubeseal --format=yaml < secret.yaml > sealed-secret.yaml

# Commit sealed-secret.yaml to git — ArgoCD syncs it
# The controller decrypts and creates the actual Secret in the cluster
```

```yaml
# Example: sealed-secret.yaml committed to git
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-secret
  namespace: my-namespace
spec:
  encryptedData:
    password: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq...
    username: AgCF5XiIWPxZDPIEr...
  template:
    metadata:
      name: my-secret
      namespace: my-namespace
    type: Opaque
```

#### External Secrets Operator (ESO)

Pull secrets from external vaults (AWS Secrets Manager, GCP Secret Manager, HashiCorp Vault, Azure Key Vault, etc.) into Kubernetes Secrets.

```yaml
# SecretStore: points to external secret backend
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: my-namespace
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "my-role"

---
# ExternalSecret: defines what to fetch
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-external-secret
  namespace: my-namespace
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: my-secret          # Creates this Kubernetes Secret
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef:
      key: my-app/credentials
      property: password
```

ArgoCD syncs the `SecretStore` and `ExternalSecret` CRDs. The ESO controller handles actual secret retrieval.

#### Vault Secrets Operator (VSO)

HashiCorp's official Kubernetes operator for Vault integration.

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: my-vault-secret
  namespace: my-namespace
spec:
  vaultAuthRef: vault-auth
  mount: secret
  type: kv-v2
  path: my-app/credentials
  destination:
    name: my-secret
    create: true
```

#### Kubernetes Secrets Store CSI Driver

Mount secrets directly into pods as volumes from external providers.

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-db-creds
  namespace: my-namespace
spec:
  provider: vault
  parameters:
    vaultAddress: "https://vault.example.com"
    roleName: "my-role"
    objects: |
      - objectName: "db-password"
        secretPath: "secret/data/my-app/db"
        secretKey: "password"
  secretObjects:
  - data:
    - key: password
      objectName: db-password
    secretName: db-secret
    type: Opaque
```

### Caution: ArgoCD Vault Plugin (AVP)

The `argocd-vault-plugin` injects secrets during ArgoCD's manifest generation. This approach is **strongly cautioned against** by ArgoCD maintainers due to:
- Secrets exposed in ArgoCD's render pipeline
- Increased operational complexity
- Security surface area expansion

If you must use it, configure as a Config Management Plugin (CMP) via sidecar:

```yaml
# plugin.yaml (mounted into argocd-repo-server sidecar)
apiVersion: argoproj.io/v1alpha1
kind: ConfigManagementPlugin
metadata:
  name: argocd-vault-plugin
spec:
  version: v1.0
  generate:
    command: [argocd-vault-plugin]
    args: ["generate", "."]
  discover:
    find:
      glob: "**/secrets.yaml"
```

```yaml
# Patch argocd-repo-server to add AVP sidecar
spec:
  template:
    spec:
      containers:
      - name: avp
        command: [/var/run/argocd/argocd-cmp-server]
        image: quay.io/argoproj-labs/argocd-vault-plugin:v1.x.x
        securityContext:
          runAsNonRoot: true
          runAsUser: 999
        env:
        - name: VAULT_ADDR
          value: "https://vault.example.com"
        volumeMounts:
        - mountPath: /var/run/argocd
          name: var-files
        - mountPath: /home/argocd/cmp-server/plugins
          name: plugins
        - mountPath: /home/argocd/cmp-server/config/plugin.yaml
          subPath: plugin.yaml
          name: avp-config
        - mountPath: /tmp
          name: cmp-tmp
```

### SOPS (Secrets OPerationS)

Encrypt secrets in git using age, PGP, AWS KMS, or GCP KMS. Requires a custom ArgoCD plugin to decrypt at render time.

```bash
# Encrypt a secret with SOPS
sops --encrypt --age <age-public-key> secret.yaml > secret.enc.yaml

# Commit secret.enc.yaml to git
# Decryption happens via ArgoCD CMP plugin in repo-server
```

---

## 11. Notifications

ArgoCD Notifications sends alerts for application lifecycle events. Configure in `argocd-notifications-cm` ConfigMap and `argocd-notifications-secret` Secret.

### Install Built-in Catalog

```bash
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml
```

### Built-in Trigger Catalog

| Trigger | Event |
|---|---|
| `on-created` | Application created |
| `on-deleted` | Application deleted |
| `on-deployed` | Healthy sync reached (once per commit) |
| `on-health-degraded` | Health status degraded |
| `on-sync-failed` | Sync operation failed |
| `on-sync-running` | Sync operation started |
| `on-sync-status-unknown` | Sync status unknown |
| `on-sync-succeeded` | Sync completed successfully |

### Trigger Syntax

```yaml
# argocd-notifications-cm
data:
  # Trigger: when condition, send template, once per revision
  trigger.on-sync-failed: |
    - when: app.status.operationState.phase in ['Error', 'Failed']
      send: [app-sync-failed]
      oncePer: app.status?.operationState?.syncResult?.revision

  # Multiple conditions in one trigger
  trigger.on-health-degraded: |
    - when: app.status.health.status == 'Degraded'
      send: [app-health-degraded-slack, app-health-degraded-email]
    - when: app.status.health.status == 'Missing'
      send: [app-health-missing]
      oncePer: app.metadata.name

  # Default triggers applied without annotation
  defaultTriggers: |
    - on-sync-failed
    - on-health-degraded
```

#### Trigger Expression Functions

```
# Time
time.Now()
time.Parse(val)

# Strings
strings.ToUpper(s)
strings.ToLower(s)
strings.ReplaceAll(s, old, new)

# Repository
repo.RepoURLToHTTPS(url)
repo.FullNameByRepoURL(url)          # Returns "owner/repo"
repo.QueryEscape(s)
repo.GetCommitMetadata(sha)          # .Message, .Author, .Date, .Tags
repo.GetAppDetails()                 # Helm/Kustomize/Directory info

# Sync
sync.GetInfoItem(app, "key")

# Optional chaining (safe navigation)
app.status?.operationState?.phase
```

### Template Syntax

```yaml
data:
  template.app-sync-succeeded: |
    message: |
      Application {{.app.metadata.name}} sync succeeded.
      Revision: {{.app.status.sync.revision}}

    # Slack-specific fields
    slack:
      attachments: |
        [{
          "color": "#18be52",
          "title": "{{.app.metadata.name}} - Sync Succeeded",
          "title_link": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
          "fields": [
            {
              "title": "Sync Status",
              "value": "{{.app.status.sync.status}}",
              "short": true
            },
            {
              "title": "Repository",
              "value": "{{.app.spec.source.repoURL}}",
              "short": true
            }
          ]
        }]

    # Email-specific fields
    email:
      subject: "ArgoCD: {{.app.metadata.name}} sync succeeded"
```

#### Template Variables

- `.app` — Application object
- `.appProject` — Associated AppProject
- `.context` — User-defined context key-values
- `.secrets.<key>` — Values from `argocd-notifications-secret`
- `.serviceType` — e.g., "slack", "email"
- `.recipient` — Recipient name

### Slack Notification Service

```bash
# 1. Create Slack app at https://api.slack.com/apps
# 2. Add OAuth scope: chat:write (and chat:write.customize for custom username/icon)
# 3. Install to workspace, copy Bot User OAuth Token
```

```yaml
# argocd-notifications-secret
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
stringData:
  slack-token: xoxb-your-slack-bot-token

---
# argocd-notifications-cm
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
    username: ArgoCD
    icon: ":argo:"

    # Group notifications by commit
    groupingKey: "{{.app.status.sync.revision}}"
    notifyBroadcast: false

    # Delivery policy: Post, PostAndUpdate, Update
    deliveryPolicy: Post
```

```yaml
# Application subscription annotation
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: "#deployments"
    notifications.argoproj.io/subscribe.on-health-degraded.slack: "#alerts,#on-call"
```

### Email Notification Service

```yaml
# argocd-notifications-secret
stringData:
  email-password: your-smtp-password

---
# argocd-notifications-cm
data:
  # Gmail configuration
  service.email.gmail: |
    username: $email-username
    password: $email-password
    host: smtp.gmail.com
    port: 465
    from: $email-from

  # Generic SMTP (no auth)
  service.email.internal: |
    host: smtp.company.internal
    port: 587
    from: argocd@company.com

  # Template with email subject
  template.app-sync-failed: |
    message: "Application {{.app.metadata.name}} sync failed"
    email:
      subject: "[ArgoCD] FAILED: {{.app.metadata.name}} sync"
```

```yaml
# Application subscription
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-failed.email.gmail: ops@example.com
```

### Webhook Notification Service

```yaml
data:
  # Service definition
  service.webhook.github-status: |
    url: https://api.github.com/repos/{{.app.spec.source.repoURL | call .repo.FullNameByRepoURL}}/statuses/{{.app.status.operationState.operation.sync.revision}}
    headers:
    - name: Authorization
      value: token $github-token
    - name: Content-Type
      value: application/json

  # Generic webhook
  service.webhook.jenkins: |
    url: https://jenkins.example.com/job/deploy/buildWithParameters
    headers:
    - name: Authorization
      value: Basic $jenkins-token
    basicAuth:
      username: $jenkins-user
      password: $jenkins-password

  # Webhook template
  template.github-commit-status: |
    webhook:
      github-status:
        method: POST
        body: |
          {
            "state": "{{if eq .app.status.operationState.phase "Succeeded"}}success{{else}}failure{{end}}",
            "description": "ArgoCD sync {{.app.status.operationState.phase}}",
            "context": "continuous-delivery/argocd"
          }
```

### Microsoft Teams Notification Service

> **Note**: Office 365 Connectors retire March 31, 2026. Migrate to Power Automate Workflows.

```yaml
# argocd-notifications-secret
stringData:
  channel-teams-url: https://webhook.office.com/webhook/your-webhook-id

---
# argocd-notifications-cm
data:
  service.teams: |
    recipientUrls:
      platform-alerts: $channel-teams-url

  template.app-sync-failed: |
    teams:
      themeColor: "#FF0000"
      summary: "Sync Failed: {{.app.metadata.name}}"
      facts: |
        [{
          "name": "Application",
          "value": "{{.app.metadata.name}}"
        },{
          "name": "Sync Status",
          "value": "{{.app.status.sync.status}}"
        }]
```

```yaml
# Application subscription
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-failed.teams: platform-alerts
```

### Namespace-Based Self-Service Notifications

Allow teams to configure notifications in their own namespaces:

```yaml
# argocd-cmd-params-cm
data:
  # Enable apps in additional namespaces
  application.namespaces: "team-alpha-*, team-beta-*"
  # Allow self-service notification configuration
  notifications.selfservice.enabled: "true"
```

---

## 12. Audit Logging & Observability

### Audit Trail Sources

1. **Git commit history**: All configuration changes tracked (who, what, when)
2. **Kubernetes Events**: Application sync events with responsible actors
3. **ArgoCD security logs**: Severity-tagged entries (1=Low to 5=Emergency)
4. **API server logs**: All API calls (exclude sensitive endpoints at proxy layer)

### Enabling Detailed Logging

```yaml
# argocd-cmd-params-cm
data:
  # Log level for all components
  server.log.level: info      # debug, info, warn, error
  repo.server.log.level: info
  controller.log.level: info
```

### Kubernetes Event Access

```bash
# View ArgoCD application events
kubectl get events -n argocd --field-selector reason=ResourceCreated
kubectl get events -n argocd --sort-by='.lastTimestamp'

# Watch sync events for specific app
kubectl describe application my-app -n argocd | grep -A5 Events
```

### Security Log Severity Levels

| Level | Description |
|---|---|
| 1 | Low |
| 2 | Low-Medium |
| 3 | Medium |
| 4 | High |
| 5 | Emergency |

### Repository Security

**Critical risk**: Write access to trusted git repositories enables malicious deployments. Mitigations:

```yaml
# In AppProject: restrict source repos
spec:
  sourceRepos:
  - https://github.com/my-org/trusted-config  # Explicit allowed repos only
  # Never use ["*"] in production

# Disable unused config management tools in argocd-cm:
data:
  # Disable Helm if not used (reduces attack surface)
  # kustomize.enabled: "false"
  # helm.enabled: "false"
```

---

## 13. ApplicationSet Security

ApplicationSets can generate Applications across multiple projects. They must be **admin-only** resources.

### Key Security Rules

1. **Only admins should create/update/delete ApplicationSets** — they can generate apps in any project
2. **Never allow user-controlled input in `project` template fields** — a malicious user with git push access could set the project to one with elevated permissions
3. **Control generator sources** — users with write access to git repos feeding ApplicationSet generators can create excessive applications or modify project assignments
4. **Hard-code the `project` field** in ApplicationSet templates:

```yaml
# SAFE: project hard-coded
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: team-alpha-apps
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/my-org/app-configs
      revision: HEAD
      directories:
      - path: apps/*
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: team-alpha    # HARD-CODED: not from generator output
      source:
        repoURL: https://github.com/my-org/app-configs
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: team-alpha-staging

---
# DANGEROUS: project from generator (allows project injection)
# project: '{{project}}'   # NEVER do this in multi-tenant setups
```

### ApplicationSet RBAC

```yaml
# argocd-rbac-cm: restrict applicationset management
data:
  policy.csv: |
    # Only platform team can manage applicationsets
    p, role:admin, applicationsets, *, *, allow
    p, role:platform, applicationsets, get, *, allow
    p, role:platform, applicationsets, create, *, allow
    p, role:platform, applicationsets, update, *, allow
    p, role:platform, applicationsets, delete, *, allow

    # Other roles: read-only
    p, role:developer, applicationsets, get, *, allow
```

---

## Quick Reference: Key ConfigMaps and Secrets

| Resource | Purpose |
|---|---|
| `argocd-cm` | Main config: URL, SSO, Dex, local users, feature flags |
| `argocd-rbac-cm` | RBAC policies, default role, scopes |
| `argocd-secret` | Admin password, JWT secret, SSO client secrets |
| `argocd-server-tls` | TLS cert for argocd-server (hot-reload) |
| `argocd-repo-server-tls` | TLS cert for argocd-repo-server (requires restart) |
| `argocd-dex-server-tls` | TLS cert for argocd-dex-server (requires restart) |
| `argocd-cmd-params-cm` | Runtime parameters for all ArgoCD components |
| `argocd-notifications-cm` | Notification triggers, templates, services |
| `argocd-notifications-secret` | Notification service credentials (Slack token, SMTP password) |

## Quick Reference: CLI Security Commands

```bash
# RBAC
argocd admin settings rbac validate --policy-file policy.csv
argocd admin settings rbac can role:developer applications sync dev/my-app

# Local users
argocd account list
argocd account update-password --account alice
argocd account generate-token --account ci-bot --expires-in 24h

# Project JWT tokens
argocd proj role create-token my-project my-role --expires-in 168h
argocd proj role list-tokens my-project my-role
argocd proj role delete-token my-project my-role <iat>

# TLS
kubectl create -n argocd secret tls argocd-server-tls --cert=cert.pem --key=key.pem
kubectl rollout restart deployment/argocd-repo-server -n argocd

# Disable admin (after SSO verified)
kubectl patch configmap argocd-cm -n argocd --patch '{"data":{"admin.enabled":"false"}}'
```

---

# Part 5: Troubleshooting, HA, Advanced Patterns

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
