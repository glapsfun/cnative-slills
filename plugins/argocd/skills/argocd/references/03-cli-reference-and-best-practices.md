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
