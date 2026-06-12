# kgateway Installation & Upgrade Reference

## Version Matrix

| kgateway | Kubernetes Gateway API | Kubernetes | Notes |
|----------|----------------------|------------|-------|
| v2.3.x   | v1.5.1               | 1.26+      | Latest; GRPCRoute, IP ACL, fault injection, OTel tracing |
| v2.2.x   | v1.2.x               | 1.25+      | Previous stable |
| v2.1.x   | v1.1.x               | 1.24+      | Older stable |

Check supported Kubernetes versions at: https://kgateway.dev/docs/envoy/latest/reference/version-support/

## Helm Charts

| Chart | OCI Path |
|-------|---------|
| CRDs | `oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds` |
| Control plane | `oci://cr.kgateway.dev/kgateway-dev/charts/kgateway` |

Inspect available values: `helm show values oci://cr.kgateway.dev/kgateway-dev/charts/kgateway --version v2.3.1`

## Fresh Installation

```bash
# 1. Gateway API CRDs — standard channel (HTTPRoute, GatewayClass, Gateway, ReferenceGrant)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

# Use experimental channel for GRPCRoute, TCPRoute, TLSRoute:
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml

# 2. kgateway CRDs
helm upgrade -i kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
  --create-namespace --namespace kgateway-system \
  --version v2.3.1

# 3. kgateway control plane
helm upgrade -i kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --namespace kgateway-system \
  --version v2.3.1

# 4. Verify
kubectl get pods -n kgateway-system
# Expected: one kgateway pod Running
```

## Development/Main Builds

```bash
helm upgrade -i kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --namespace kgateway-system \
  --version v2.4.0-main \
  --set controller.image.pullPolicy=Always
```

## ArgoCD Installation

Use Helm-based Application resources targeting the OCI charts. Set `helm.version` and pass `values` inline. The CRDs chart must be applied before the control plane chart (use sync-wave annotations).

## Upgrade Procedure

```bash
export NEW_VERSION=2.3.1

# 1. Review release notes for breaking changes
# https://github.com/kgateway-dev/kgateway/releases/tag/v${NEW_VERSION}

# 2. Upgrade Gateway API CRDs if required by the new version
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

# 3. Upgrade kgateway CRDs
helm upgrade -i kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
  --namespace kgateway-system \
  --version v${NEW_VERSION}

# 4. Compare Helm values (diff your saved values.yaml against new defaults)
helm show values oci://cr.kgateway.dev/kgateway-dev/charts/kgateway --version v${NEW_VERSION}

# 5. Upgrade control plane (always pass previous values to avoid overwriting)
helm upgrade -i kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --namespace kgateway-system \
  --version v${NEW_VERSION} \
  -f values.yaml

# 6. Verify
kubectl get pods -n kgateway-system
kubectl rollout status deployment/kgateway -n kgateway-system
```

## v2.3.0 Migration Guide

### 1. Istio ServiceEntry watching

Previously enabled by default. Now requires explicit opt-in:

```bash
helm upgrade kgateway ... \
  --set controller.env.KGW_ENABLE_ISTIO_INTEGRATION=true
```

Or in values.yaml:
```yaml
controller:
  env:
    KGW_ENABLE_ISTIO_INTEGRATION: "true"
```

### 2. Classic transformation removed

The C++ "classic" transformation filter is gone. Only Rustformation is supported. If your `TrafficPolicy` resources used classic-only features (check your policies for `transformation.transformationTemplate` with C++ Inja), migrate them to Rustformation syntax. Classic policies silently misbehave after upgrade.

Test before upgrading: `kubectl get trafficpolicy -A -o yaml | grep -i transformation`

### 3. CORS wildcard origins

Non-spec patterns like `https://a.b*` are rejected. Use spec-compliant syntax:
- Before: `https://app.b*`
- After: `https://*.app.b` or a specific hostname

### 4. XListenerSet → ListenerSet

```yaml
# Before
apiVersion: gateway.networking.x-k8s.io/v1alpha1
kind: XListenerSet

# After
apiVersion: gateway.networking.k8s.io/v1
kind: ListenerSet
```

Migrate before upgrading: `kubectl get xlistenerset -A`

## Uninstall

```bash
helm uninstall kgateway -n kgateway-system
helm uninstall kgateway-crds -n kgateway-system
kubectl delete namespace kgateway-system
# Remove Gateway API CRDs if no longer needed:
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
```

## Key Helm Values

```yaml
controller:
  image:
    pullPolicy: IfNotPresent   # Always for dev builds
  replicaCount: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
  env:
    KGW_ENABLE_ISTIO_INTEGRATION: "false"  # set "true" for Istio ServiceEntry support
    LOG_LEVEL: info                         # debug, info, warn, error

# Gateway proxy defaults
gateway:
  proxyDeployment:
    replicas: 1
```
