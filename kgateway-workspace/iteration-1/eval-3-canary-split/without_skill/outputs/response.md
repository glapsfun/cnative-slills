# Canary Deployment with kgateway: 90/10 Traffic Split

## Overview

kgateway (the Kubernetes-native API gateway based on Envoy, formerly Gloo Edge OSS) supports weighted traffic splitting through its routing configuration. To send 10% of traffic to v2 and 90% to v1, you use weighted destinations in your routing rules.

## Prerequisites

- kgateway installed in your cluster
- Two Kubernetes Services: one for v1 and one for v2 of your application
- A VirtualService (or HTTPRoute if using Gateway API mode) configured

---

## Option 1: Using kgateway VirtualService (Gloo Edge / kgateway CRD mode)

### Step 1: Ensure both versions have separate Services

```yaml
# v1 Service
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
      targetPort: 8080
---
# v2 Service
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
      targetPort: 8080
```

### Step 2: Create Upstreams for each version

kgateway uses `Upstream` resources to represent backend destinations:

```yaml
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: my-app-v1
  namespace: gloo-system
spec:
  kube:
    serviceName: my-app-v1
    serviceNamespace: default
    servicePort: 8080
---
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: my-app-v2
  namespace: gloo-system
spec:
  kube:
    serviceName: my-app-v2
    serviceNamespace: default
    servicePort: 8080
```

> **Note:** kgateway can auto-discover Upstreams. Check if they already exist with:
> ```bash
> kubectl get upstreams -n gloo-system
> ```

### Step 3: Configure VirtualService with weighted routing

```yaml
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: my-app-canary
  namespace: gloo-system
spec:
  virtualHost:
    domains:
      - my-app.example.com
    routes:
      - matchers:
          - prefix: /
        routeAction:
          multi:
            destinations:
              - weight: 90
                destination:
                  upstream:
                    name: my-app-v1
                    namespace: gloo-system
              - weight: 10
                destination:
                  upstream:
                    name: my-app-v2
                    namespace: gloo-system
```

The `weight` values are relative — they don't need to sum to 100, but using 90 and 10 makes the percentages clear and intuitive.

---

## Option 2: Using Kubernetes Gateway API (HTTPRoute)

If kgateway is running in Gateway API mode (the newer, standard approach), use `HTTPRoute`:

### Step 1: Ensure Gateway exists

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
  namespace: default
spec:
  gatewayClassName: kgateway
  listeners:
    - name: http
      protocol: HTTP
      port: 80
```

### Step 2: Create HTTPRoute with weighted backendRefs

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app-canary
  namespace: default
spec:
  parentRefs:
    - name: my-gateway
  hostnames:
    - my-app.example.com
  rules:
    - backendRefs:
        - name: my-app-v1
          port: 8080
          weight: 90
        - name: my-app-v2
          port: 8080
          weight: 10
```

This is the cleanest approach and aligns with the Kubernetes Gateway API standard. The `weight` field in each `backendRef` controls the traffic distribution.

---

## Verifying the Traffic Split

### Check the route is accepted

```bash
# For VirtualService mode
kubectl get virtualservice my-app-canary -n gloo-system -o yaml

# For HTTPRoute mode
kubectl describe httproute my-app-canary -n default
```

Look for `Accepted: True` and `ResolvedRefs: True` in the status conditions.

### Watch traffic distribution in real time

```bash
# Check Envoy proxy config (kgateway uses Envoy under the hood)
kubectl exec -n gloo-system deploy/gateway-proxy -- \
  curl -s localhost:19000/config_dump | jq '.configs[] | select(.["@type"] | contains("RouteConfiguration"))'
```

### Send test traffic

```bash
for i in $(seq 1 100); do
  curl -s -o /dev/null -w "%{http_code}\n" http://my-app.example.com/
done
```

You can differentiate v1 vs v2 responses by adding version headers in your application responses.

---

## Gradually Increasing v2 Traffic

For a safe canary rollout, progressively shift traffic:

| Phase | v1 weight | v2 weight |
|-------|-----------|-----------|
| Initial canary | 90 | 10 |
| Expand canary | 70 | 30 |
| Majority canary | 50 | 50 |
| Near-complete | 20 | 80 |
| Full rollout | 0 | 100 |

Update the weights in the VirtualService or HTTPRoute and apply with `kubectl apply -f`.

---

## Adding Header-Based Routing (Optional)

For testing, you can route specific requests (e.g., internal testers) always to v2 by adding a header-based rule before the weighted rule:

```yaml
# HTTPRoute example with header-based canary
rules:
  # Testers always go to v2
  - matches:
      - headers:
          - name: x-canary
            value: "true"
    backendRefs:
      - name: my-app-v2
        port: 8080
        weight: 1
  # Everyone else: 90/10 split
  - backendRefs:
      - name: my-app-v1
        port: 8080
        weight: 90
      - name: my-app-v2
        port: 8080
        weight: 10
```

---

## Key Points

- **Weights are relative integers**, not percentages — `90` and `10` produce a 90%/10% split.
- **VirtualService** is the kgateway-native CRD; **HTTPRoute** is the Kubernetes Gateway API standard — prefer HTTPRoute for new deployments.
- kgateway delegates weighted routing to **Envoy**, which handles the actual load balancing stochastically per request.
- If a destination becomes unavailable, Envoy will not automatically redistribute its weight — health checks and outlier detection should be configured for production use.
- Changes to weights take effect immediately after `kubectl apply` with no downtime.
