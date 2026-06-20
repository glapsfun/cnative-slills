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
