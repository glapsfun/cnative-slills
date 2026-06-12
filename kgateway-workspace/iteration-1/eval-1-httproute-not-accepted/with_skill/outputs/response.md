# HTTPRoute 'Accepted: False' — Root Cause and Fix

The most likely cause is a **cross-namespace attachment restriction**. Your HTTPRoute is in `app-ns`, but your Gateway is in `kgateway-system`. By default, kgateway Gateways only accept routes from the **same namespace** as the Gateway. Since your HTTPRoute lives in a different namespace, the Gateway's listener rejects it, producing `Accepted: False`.

## Step 1 — Confirm the diagnosis

```bash
kubectl describe httproute my-app -n app-ns
```

Look for a condition like:

```
status:
  parents:
  - conditions:
    - type: Accepted
      status: "False"
      reason: NotAllowedByParent
      message: "..."
```

`NotAllowedByParent` (or `NoMatchingParent`) confirms the namespace restriction is the problem.

Also verify the Gateway itself is healthy:

```bash
kubectl describe gateway http -n kgateway-system
# status.conditions[type=Programmed].status should be True
```

## Fix — Allow routes from other namespaces

Add `allowedRoutes` to the Gateway listener so it accepts routes from `app-ns` (or from all namespaces):

```yaml
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
    allowedRoutes:
      namespaces:
        from: All        # or use Selector to restrict to specific namespaces
```

If you only want to allow routes from `app-ns` specifically:

```yaml
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            kubernetes.io/metadata.name: app-ns
```

After applying the Gateway change, re-check:

```bash
kubectl describe httproute my-app -n app-ns
```

`Accepted: True` should appear within a few seconds once the control plane processes the update.

## Secondary issue to check — ResolvedRefs

Once `Accepted` turns True, also check for a `ResolvedRefs` condition. If `my-service` in `app-ns` is referenced by a backend from the route (same namespace), that should resolve fine without any extra steps. But if you later reference a Service **in a different namespace**, you will also need a `ReferenceGrant`:

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-app-ns
  namespace: app-ns          # namespace where the Service lives
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: app-ns
  to:
  - group: ""
    kind: Service
```

## Other things to rule out

| Check | Command |
|-------|---------|
| Gateway name/namespace in parentRefs matches exactly | `kubectl get gateway -A` |
| sectionName (if set) matches a listener name | `kubectl describe gateway http -n kgateway-system` |
| Control plane is running | `kubectl get pods -n kgateway-system` |
| Control plane logs show no translation errors | `kubectl logs deploy/kgateway -n kgateway-system \| tail -50` |

Your `parentRefs` references `name: http` in `namespace: kgateway-system`, which looks correct assuming the Gateway is named `http`. The missing piece is the `allowedRoutes` configuration on the listener.

## Summary

The `Accepted: False` status on your HTTPRoute is almost certainly because the Gateway listener has no `allowedRoutes` configuration, so it defaults to only accepting routes from its own namespace (`kgateway-system`). Your route is in `app-ns`. Adding `allowedRoutes.namespaces.from: All` (or a namespace selector) to the Gateway listener will fix it.
