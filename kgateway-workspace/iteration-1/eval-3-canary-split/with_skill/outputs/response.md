# Canary Deploy Traffic Splitting in kgateway

## Overview

kgateway supports traffic splitting natively via the standard Kubernetes Gateway API `HTTPRoute` resource. You configure weighted `backendRefs` in a single route rule, and kgateway (via Envoy) handles the probabilistic split on each request.

## Configuration

Create (or update) an `HTTPRoute` that references both your v1 and v2 Services with `weight` values:

```yaml
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
        value: /
    backendRefs:
    - name: my-app-v1      # stable / current version
      port: 8080
      weight: 90
    - name: my-app-v2      # canary / new version
      port: 8080
      weight: 10
```

### Prerequisites

Both Services must exist in the same namespace (or in another namespace with a `ReferenceGrant`):

```yaml
# v1 service (already running)
apiVersion: v1
kind: Service
metadata:
  name: my-app-v1
  namespace: default
spec:
  selector:
    app: my-app
    version: v1
  ports:
  - port: 8080
---
# v2 service (canary)
apiVersion: v1
kind: Service
metadata:
  name: my-app-v2
  namespace: default
spec:
  selector:
    app: my-app
    version: v2
  ports:
  - port: 8080
```

## How the Weights Work

- Weights are **relative**, not percentages — they do not need to sum to 100.
- `weight: 90` + `weight: 10` means 90% of requests go to v1 and 10% go to v2.
- To shift more traffic to v2 over time, edit the `weight` values (e.g., 80/20, then 50/50, then 0/100).
- To send all traffic to a single backend, set its weight to `1` and the other to `0`.

## Applying the Configuration

```bash
kubectl apply -f httproute-canary.yaml
```

Check that the route is accepted and programmed:

```bash
kubectl describe httproute my-app -n default
```

Look for:
```
status:
  parents:
  - conditions:
    - type: Accepted
      status: "True"
    - type: ResolvedRefs
      status: "True"
```

If `ResolvedRefs` is `False`, the Services referenced in `backendRefs` cannot be found — verify names, namespaces, and ports.

## Promoting or Rolling Back

**Increase canary traffic** (shift to 80/20):
```yaml
backendRefs:
- name: my-app-v1
  port: 8080
  weight: 80
- name: my-app-v2
  port: 8080
  weight: 20
```

**Promote v2 to 100%** (complete rollout):
```yaml
backendRefs:
- name: my-app-v2
  port: 8080
  weight: 1
```

**Rollback to v1 instantly**:
```yaml
backendRefs:
- name: my-app-v1
  port: 8080
  weight: 1
```

## Cross-Namespace Services

If v1 and v2 live in different namespaces, add a `ReferenceGrant` in each target namespace:

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-route-from-default
  namespace: v2-namespace
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: default
  to:
  - group: ""
    kind: Service
```

## Optional: Automated Canary with Argo Rollouts

For automated progressive delivery (metric-based promotion, automatic rollback), kgateway integrates with Argo Rollouts. The Rollouts controller can update the `weight` values automatically as it evaluates success metrics. See the kgateway operations reference or https://kgateway.dev/docs/envoy/latest/ for the Argo Rollouts integration guide.

## Version Note

Traffic splitting via weighted `backendRefs` is supported in all current kgateway versions (v2.1.x, v2.2.x, v2.3.x). No kgateway-specific CRDs are required — this uses the standard Gateway API HTTPRoute spec.
