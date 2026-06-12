# Upgrading from kgateway v2.2 to v2.3

v2.3 brings several new features but also has four breaking changes that require action before or during the upgrade. Here is everything you need to know.

## What's New in v2.3

- **GRPCRoute support** — native gRPC routing via the Gateway API experimental channel
- **IP ACL** — allow/deny lists for IP-based access control via `TrafficPolicy`
- **Fault injection** — delay and abort injection for resilience testing via `TrafficPolicy`
- **OpenTelemetry tracing** — distributed tracing support in the observability stack
- **Rustformation only** — the transformation engine is now unified on Rust (classic C++ filter removed)

## Kubernetes Gateway API CRD Upgrade

v2.3 requires **Gateway API v1.5.1**, up from v1.2.x in v2.2. Upgrade the CRDs as the first step:

```bash
# Standard channel (HTTPRoute, GatewayClass, Gateway, ReferenceGrant)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

# Experimental channel (required for GRPCRoute, TCPRoute, TLSRoute)
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml
```

## Breaking Changes — Action Required

### 1. Classic transformation filter removed

The C++ "classic" transformation filter (`transformation.transformationTemplate` using Inja syntax) is gone. Rustformation is now the only engine.

**Before upgrading, audit your TrafficPolicy resources:**

```bash
kubectl get trafficpolicy -A -o yaml | grep -i transformation
```

Any policies using classic Inja templates will silently misbehave after the upgrade — there is no error, they just stop working. Migrate those policies to Rustformation syntax before upgrading.

### 2. Istio ServiceEntry watching is now opt-in

Previously enabled by default; now disabled. If you use kgateway with Istio ServiceEntries, you must explicitly re-enable it or Istio service discovery will stop working after the upgrade.

Add to your `values.yaml`:

```yaml
controller:
  env:
    KGW_ENABLE_ISTIO_INTEGRATION: "true"
```

Or pass it during the Helm upgrade:

```bash
helm upgrade kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --namespace kgateway-system \
  --version v2.3.1 \
  --set controller.env.KGW_ENABLE_ISTIO_INTEGRATION=true \
  -f values.yaml
```

### 3. CORS wildcard origins must be spec-compliant

Non-standard wildcard patterns like `https://app.example*` are now rejected. Only RFC-compliant patterns are accepted.

Audit your CORS configurations:

```bash
kubectl get trafficpolicy -A -o yaml | grep -i cors
```

Fix any non-compliant patterns:

| Before (rejected) | After (accepted) |
|-------------------|-----------------|
| `https://app.b*` | `https://*.app.b` |
| `https://a.b*` | `https://*.a.b` or a specific hostname |

### 4. XListenerSet promoted to ListenerSet

`XListenerSet` (experimental kind) is now promoted to the stable `ListenerSet`. The `kind` and `apiVersion` must be updated in all manifests.

Check if you have any XListenerSet resources:

```bash
kubectl get xlistenerset -A
```

If any exist, update them before upgrading:

```yaml
# Before
apiVersion: gateway.networking.x-k8s.io/v1alpha1
kind: XListenerSet

# After
apiVersion: gateway.networking.k8s.io/v1
kind: ListenerSet
```

## Upgrade Procedure

```bash
export NEW_VERSION=2.3.1

# 1. Review official release notes for any additional changes
# https://github.com/kgateway-dev/kgateway/releases/tag/v2.3.1

# 2. Pre-upgrade checks (run before touching anything)
kubectl get trafficpolicy -A -o yaml | grep -i transformation  # classic transforms?
kubectl get trafficpolicy -A -o yaml | grep -i cors            # non-compliant CORS?
kubectl get xlistenerset -A                                     # old XListenerSet resources?

# 3. Upgrade Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

# 4. Upgrade kgateway CRDs
helm upgrade -i kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
  --namespace kgateway-system \
  --version v${NEW_VERSION}

# 5. Diff Helm values to find any new or removed defaults
helm show values oci://cr.kgateway.dev/kgateway-dev/charts/kgateway --version v${NEW_VERSION}

# 6. Upgrade control plane (always pass -f values.yaml to preserve your settings)
helm upgrade -i kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --namespace kgateway-system \
  --version v${NEW_VERSION} \
  -f values.yaml

# 7. Verify
kubectl get pods -n kgateway-system
kubectl rollout status deployment/kgateway -n kgateway-system
```

## Post-Upgrade Verification

```bash
# Control plane is healthy
kubectl get pods -n kgateway-system

# Gateways are programmed
kubectl get gateway -A

# Routes are accepted
kubectl get httproute -A
kubectl describe httproute <name> -n <ns>  # check status.parents[].conditions

# Check control plane logs for warnings
kubectl logs deploy/kgateway -n kgateway-system | grep -i error
```

## Summary of Required Pre-Upgrade Actions

| Check | Command | Action if found |
|-------|---------|----------------|
| Classic transformations | `kubectl get trafficpolicy -A -o yaml \| grep -i transformation` | Migrate to Rustformation syntax |
| Istio integration | Check if you use ServiceEntries | Add `KGW_ENABLE_ISTIO_INTEGRATION=true` to values |
| Non-compliant CORS | `kubectl get trafficpolicy -A -o yaml \| grep -i cors` | Fix wildcard patterns to `https://*.domain.com` |
| XListenerSet resources | `kubectl get xlistenerset -A` | Update kind/apiVersion to ListenerSet |

None of these changes are skippable — missing them leads to silent failures (classic transforms, CORS) or broken Istio discovery. The safest approach is to run all four checks and resolve findings before running `helm upgrade`.
