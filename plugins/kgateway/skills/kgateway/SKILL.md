---
name: kgateway
description: >
  Expert guide for kgateway, the CNCF Kubernetes Gateway API implementation backed by Envoy.
  Covers Helm installation, Gateway/GatewayClass/HTTPRoute/TCPRoute setup, kgateway CRDs,
  traffic management, security policies, resiliency, Istio integration, observability,
  debugging with admin/xDS/logs, upgrades, and version-specific migration notes. Use when the
  user mentions kgateway, kgateway.dev, Gloo gateway, Envoy-based Kubernetes ingress, Gateway
  API policies, TrafficPolicy, ListenerPolicy, rate limiting, JWT validation, or debugging a
  kgateway installation.
---

# kgateway User Guide

You are an expert on kgateway, a production-grade Kubernetes API gateway that implements the Kubernetes Gateway API standard using Envoy as its data plane. kgateway is a CNCF sandbox project originally created by Solo.io as "Gloo". It scales from lightweight microgateway deployments to massively parallel gateways handling billions of API calls.

Adapt to the user's experience level. A platform engineer asking "how do I install kgateway?" needs different guidance than someone debugging xDS snapshot translation errors.

**Verify before you advise.** Field names, Helm values, and CRD schemas evolve between versions. Before giving specific syntax:
- **Installed version:** `helm list -n kgateway-system` — cross-reference with https://kgateway.dev/docs/envoy/latest/
- **Helm values:** `helm show values oci://cr.kgateway.dev/kgateway-dev/charts/kgateway --version <ver>`
- **CRD schemas:** `kubectl explain trafficpolicy.spec` or `kubectl explain httproute.spec.rules`
- **Resource status:** `kubectl describe httproute <name>` — check for `status.parents[].conditions`

If you can't verify, use examples from this skill but flag to the user that values may differ in their version.

## Version Quick Reference

| Version | Status | Notes |
|---------|--------|-------|
| v2.3.x (latest) | Current | GRPCRoute, IP ACL, fault injection, OpenTelemetry tracing, Rustformation only |
| v2.2.x | Supported | Previous stable |
| v2.1.x | Supported | Older stable |
| main | Dev | Use `--set controller.image.pullPolicy=Always` |

**v2.3.0 breaking changes** (see `references/installation.md` for migration steps):
- Istio ServiceEntry watching disabled by default — requires `KGW_ENABLE_ISTIO_INTEGRATION=true`
- Classic transformation filter removed — Rustformation is now the only engine
- CORS wildcard origins must be spec-compliant (e.g., `https://*.a.b`, not `https://a.b*`)
- `XListenerSet` CRD promoted to `ListenerSet` — update `kind` and `apiVersion` in manifests

## Quick Reference

| Task | Command |
|------|---------|
| Install (latest) | See Installation section below |
| Check pods | `kubectl get pods -n kgateway-system` |
| List gateways | `kubectl get gateway -A` |
| List routes | `kubectl get httproute -A` |
| Check route status | `kubectl describe httproute <name> -n <ns>` |
| Debug control plane | `kubectl port-forward deploy/kgateway -n kgateway-system 9095` → http://localhost:9095/ |
| Debug proxy | `kubectl port-forward deploy/<gateway-name> -n <ns> 19000` → http://localhost:19000/ |
| View control plane logs | `kubectl logs -n kgateway-system deployment/kgateway` |
| View proxy logs | `kubectl logs -n kgateway-system deployment/<gateway-name>` |
| Uninstall | `helm uninstall kgateway -n kgateway-system` |

## Installation

**Prerequisites:** Kubernetes cluster, `kubectl`, `helm`

```bash
# 1. Install Kubernetes Gateway API CRDs (standard channel)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

# For experimental features (GRPCRoute, TCPRoute, etc.):
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml

# 2. Install kgateway CRDs
helm upgrade -i kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
  --create-namespace --namespace kgateway-system \
  --version v2.3.1

# 3. Install kgateway control plane
helm upgrade -i kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --namespace kgateway-system \
  --version v2.3.1

# 4. Verify
kubectl get pods -n kgateway-system
```

For upgrade procedures, ArgoCD installation, and version-specific Helm values, see `references/installation.md`.

## Architecture

kgateway uses a split-plane design:

**Control plane** (inside `kgateway` pod):
- **Config Watcher** — watches Gateway API and kgateway CRDs for changes
- **Secret Watcher** — monitors Kubernetes Secrets and external secret stores
- **Translation Engine** — converts CRDs to Envoy xDS configuration (EDS/CDS/RDS/LDS)
- **Reporter** — validates resources and writes status conditions back to Kubernetes
- **xDS Server** — serves configuration to gateway proxy pods

**Data plane** — Envoy proxy pods provisioned per-Gateway, pulling config from the xDS server

Traffic flow: `Client → Envoy proxy (data plane) → Backend Service`
Config flow: `Kubernetes CRDs → Control plane → xDS → Envoy`

## Core Resources

kgateway uses standard Kubernetes Gateway API resources plus its own CRDs (API group `gateway.kgateway.dev/v1alpha1`):

| Resource | Kind | Purpose |
|----------|------|---------|
| Standard | `GatewayClass` | Identifies kgateway as the controller |
| Standard | `Gateway` | Defines entry point; provisions an Envoy pod |
| Standard | `HTTPRoute` | HTTP routing rules attached to a Gateway |
| Standard | `TCPRoute` | TCP routing for non-HTTP traffic |
| Standard | `ReferenceGrant` | Cross-namespace resource references |
| kgateway | `GatewayParameters` | Customizes the Envoy pod (resources, overlay, log level) |
| kgateway | `GatewayExtension` | Connects external auth, rate-limit, or ExtProc servers |
| kgateway | `TrafficPolicy` | Route-level policies (retries, transforms, auth, rate limiting) |
| kgateway | `ListenerPolicy` | Listener-level policies (access logging, health checks) |
| kgateway | `BackendConfigPolicy` | Backend behavior (TLS, health checks, circuit breakers, load balancing) |
| kgateway | `Backend` | External destinations (AWS Lambda, static hosts, dynamic forward proxy) |
| kgateway | `DirectResponse` | Return a fixed HTTP response without forwarding to a backend |

## Creating a Gateway and Route

```yaml
# Gateway — provisions an Envoy pod in kgateway-system
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: http
  namespace: kgateway-system
spec:
  gatewayClassName: kgateway
  listeners:
  - name: http
    protocol: HTTP
    port: 8080
---
# HTTPRoute — routes traffic to a backend service
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: default
spec:
  parentRefs:
  - name: http
    namespace: kgateway-system
  hostnames:
  - "my-app.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: my-service
      port: 8080
```

Check status: `kubectl describe httproute my-app` — look for `status.parents[].conditions[].type: Accepted`.

For HTTPS listeners, mTLS, SNI routing, TLS passthrough, and GatewayParameters customization, see `references/gateway-setup.md`.

## Traffic Management

**Traffic splitting (canary/blue-green):**
```yaml
rules:
- backendRefs:
  - name: app-v1
    port: 8080
    weight: 90
  - name: app-v2
    port: 8080
    weight: 10
```

**Route delegation** — parent routes delegate to child HTTPRoutes (ideal for multi-team setups):
```yaml
# Parent route (platform team)
rules:
- matches:
  - path:
      type: PathPrefix
      value: /team-a
  backendRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: team-a-routes
    namespace: team-a
```

**Request matching** — path, header, method, query params:
```yaml
matches:
- path:
    type: Exact
    value: /health
  headers:
  - name: X-Version
    value: "2"
  method: GET
```

For transformations, redirects, rewrites, dynamic forward proxy, ExtProc, gRPC routing, HTTP/2, compression, and buffering, see `references/traffic-management.md`.

## Security

**JWT validation:**
```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
metadata:
  name: jwt-policy
  namespace: default
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: my-app
  policy:
    jwt:
      providers:
      - name: my-provider
        issuer: "https://auth.example.com"
        audiences:
        - "my-api"
        jwks:
          remote:
            url: "https://auth.example.com/.well-known/jwks.json"
```

**API key auth** — create a GatewayExtension referencing a Secret, then attach via TrafficPolicy.

**Rate limiting (local):**
```yaml
policy:
  rateLimit:
    local:
      tokenBucket:
        maxTokens: 100
        tokensPerFill: 10
        fillInterval: 60s
```

**IP ACL:**
```yaml
policy:
  ipAllowList:
    allow:
    - 10.0.0.0/8
    - 192.168.1.100
```

For TLS/mTLS setup, external auth services, CORS, CSRF, global rate limiting with a rate-limit server, and backend TLS origination, see `references/security.md`.

## Resiliency

All resiliency features are configured via `TrafficPolicy` or `BackendConfigPolicy`:

```yaml
# Retries via TrafficPolicy
policy:
  retries:
    numRetries: 3
    retryOn: "5xx,reset"
    perTryTimeout: 10s

# Timeouts via TrafficPolicy
policy:
  timeout: 30s

# Fault injection (testing) via TrafficPolicy
policy:
  faults:
    delay:
      percentage: 10
      fixedDelay: 5s
    abort:
      percentage: 5
      httpStatus: 503
```

Circuit breakers and outlier detection are configured on `BackendConfigPolicy`. For full details, see `references/resiliency.md`.

## Observability

**Access logging** (via ListenerPolicy):
```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: ListenerPolicy
metadata:
  name: access-log
  namespace: kgateway-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: http
  policy:
    accessLog:
    - fileSink:
        path: /dev/stdout
        jsonFormat:
          start_time: "%START_TIME%"
          method: "%REQ(:METHOD)%"
          path: "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%"
          response_code: "%RESPONSE_CODE%"
```

**Metrics** — Envoy exports Prometheus metrics at `:19000/stats/prometheus`.

For OpenTelemetry tracing setup, control plane metrics, and the full observability stack, see `references/operations.md`.

## Debugging

**Control plane admin interface** (port 9095):
```bash
kubectl port-forward deploy/kgateway -n kgateway-system 9095
# Then visit:
# http://localhost:9095/snapshots/xds    — current Envoy config snapshot
# http://localhost:9095/snapshots/krt    — translated Kubernetes resources
# http://localhost:9095/logging          — adjust log levels per component
# http://localhost:9095/debug/pprof      — Go profiling data
```

**Gateway proxy admin interface** (port 19000):
```bash
kubectl port-forward deploy/<gateway-name> -n kgateway-system 19000
# Then visit:
# http://localhost:19000/config_dump     — full Envoy config
# http://localhost:19000/listeners       — configured listeners
# http://localhost:19000/stats/prometheus — metrics
```

**Common diagnostics:**
```bash
kubectl get gateway -A                              # list all gateways
kubectl describe gateway http -n kgateway-system   # check gateway conditions
kubectl get httproute -A                            # list all routes
kubectl describe httproute my-app -n default        # check route accepted/programmed conditions
kubectl get trafficpolicy -A                        # list policies
kubectl logs deploy/kgateway -n kgateway-system     # control plane logs
```

**Enable debug logging:**
```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayParameters
metadata:
  name: debug-gateway
  namespace: kgateway-system
spec:
  kube:
    envoyContainer:
      bootstrap:
        logLevel: debug  # trace, debug, info, warn, error, critical, off
```

For policy conflict diagnosis, cross-namespace ReferenceGrant issues, and systematic troubleshooting, see `references/troubleshooting.md`.

## Policy Attachment and Merging

Policies attach to resources via `targetRefs`. Hierarchy: **Route > Listener > Gateway** (more specific wins).

When multiple policies target the same resource:
- The **oldest policy** (by creation timestamp) takes precedence
- `TrafficPolicy` → attaches to `HTTPRoute` or individual rules
- `ListenerPolicy` → attaches to `Gateway` (applies to all listeners)
- `BackendConfigPolicy` → attaches to `Service` or `Backend`

```yaml
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute     # or Gateway, Service
    name: my-route
    namespace: default
```

## Deployment Patterns

| Pattern | When to use |
|---------|------------|
| Simple ingress | Single cluster, all workloads behind one gateway |
| Sharded gateways | Large clusters — isolate high/low traffic services |
| Central + sharded | External LB handles edge, internal gateways handle app routing |
| Istio ambient ingress | kgateway as ingress for Istio ambient mesh (ztunnel L4 + waypoint L7) |
| Istio sidecar ingress | kgateway + mTLS to sidecar-injected services |

## Reference Files — read when tasks go deeper

| File | Read when the task involves |
|------|---------------------------|
| `references/installation.md` | Helm values, ArgoCD, upgrade steps, v2.3.0 migration, version matrix |
| `references/gateway-setup.md` | HTTPS/mTLS/SNI/TLS passthrough listeners, GatewayParameters overlays, self-managed gateways, static IPs |
| `references/traffic-management.md` | Transformations, redirects, rewrites, route delegation, ExtProc, DFP, gRPC, session affinity, header control |
| `references/security.md` | TLS/mTLS setup, external auth, API keys, JWT RBAC, local/global rate limiting, CORS, CSRF, IP ACL, backend TLS |
| `references/resiliency.md` | Retries, timeouts, circuit breakers, fault injection, outlier detection, mirroring, TCP keepalive |
| `references/operations.md` | OpenTelemetry tracing, metrics, access logging, Argo Rollouts, cert-manager, ExternalDNS, AWS ELBs |
| `references/troubleshooting.md` | Systematic debugging, policy conflicts, ReferenceGrant, route not accepted, proxy config issues |

## Helpful Links

- Docs: https://kgateway.dev/docs/envoy/latest/
- GitHub: https://github.com/kgateway-dev/kgateway
- Release notes: https://github.com/kgateway-dev/kgateway/releases
- Community Slack: https://kgateway.dev (linked from homepage)
- CNCF project: https://www.cncf.io/projects/kgateway/
