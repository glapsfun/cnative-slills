# HTTPRoute 'Accepted: False' in kgateway v2.3.1

## Overview

When an HTTPRoute shows `Accepted: False`, it means the Gateway controller has rejected the route. In kgateway (the Gloo Gateway / Solo.io implementation of the Kubernetes Gateway API), this most commonly indicates that the HTTPRoute is not permitted to attach to the referenced Gateway. Here are the most likely causes and fixes for your configuration.

---

## Most Likely Cause: Missing ReferenceGrant

Your HTTPRoute is in namespace `app-ns` but references a Gateway in namespace `kgateway-system`. This is a **cross-namespace reference**, which the Gateway API specification explicitly blocks by default.

Without a `ReferenceGrant` in the Gateway's namespace (`kgateway-system`) that allows `app-ns` to reference it, the HTTPRoute will be rejected with `Accepted: False` and a reason like `NotAllowedByParent`.

### Fix: Create a ReferenceGrant

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-app-ns-routes
  namespace: kgateway-system   # must be in the Gateway's namespace
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: app-ns           # the namespace where your HTTPRoute lives
  to:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: http                  # optionally restrict to a specific Gateway
```

Apply this to your cluster:

```bash
kubectl apply -f referencegrant.yaml
```

After applying, the HTTPRoute should reconcile and `Accepted` should change to `True`.

---

## Secondary Checks

### 1. Verify the Gateway name and namespace match exactly

Your HTTPRoute references:
```yaml
parentRefs:
- name: http
  namespace: kgateway-system
```

Confirm the Gateway actually exists with that exact name and namespace:

```bash
kubectl get gateway -n kgateway-system http
```

If the Gateway is named differently (e.g., `my-gateway`, `http-gateway`), update the `parentRefs` accordingly.

### 2. Check the Gateway's allowedRoutes configuration

The Gateway listener may restrict which namespaces or route kinds it accepts. Inspect the Gateway spec:

```bash
kubectl get gateway -n kgateway-system http -o yaml
```

Look for the `listeners[].allowedRoutes` field. A common pattern that restricts routes:

```yaml
listeners:
- name: http
  port: 80
  protocol: HTTP
  allowedRoutes:
    namespaces:
      from: Same   # only allows routes from the SAME namespace as the Gateway
```

If `from: Same` is set, routes from `app-ns` will be rejected. Change it to `All` or `Selector` to allow cross-namespace routes:

```yaml
allowedRoutes:
  namespaces:
    from: All
```

Or use a label selector to allow specific namespaces:

```yaml
allowedRoutes:
  namespaces:
    from: Selector
    selector:
      matchLabels:
        kubernetes.io/metadata.name: app-ns
```

### 3. Check listener protocol compatibility

If the listener uses `HTTPS` but your HTTPRoute targets the `http` listener name, make sure they match. Also verify the listener `name` field — `parentRefs` can reference a specific listener by name:

```yaml
parentRefs:
- name: http
  namespace: kgateway-system
  sectionName: http   # optional: must match a listener's name field exactly
```

If `sectionName` is omitted, the route tries to attach to all compatible listeners.

### 4. Inspect the HTTPRoute status for the exact reason

Get the detailed status message — it will tell you precisely why it was rejected:

```bash
kubectl get httproute my-app -n app-ns -o yaml
```

Look at the `status.parents` block:

```yaml
status:
  parents:
  - conditions:
    - lastTransitionTime: ...
      message: "namespace not permitted by ReferenceGrant"
      reason: NotAllowedByParent
      status: "False"
      type: Accepted
    parentRef:
      group: gateway.networking.k8s.io
      kind: Gateway
      name: http
      namespace: kgateway-system
```

The `message` and `reason` fields pinpoint the exact issue.

### 5. Check kgateway controller logs

```bash
kubectl logs -n kgateway-system -l app=gloo -c gloo --tail=100
# or depending on your deployment:
kubectl logs -n kgateway-system deployment/gloo -c gloo --tail=100
```

Look for errors related to `my-app` HTTPRoute or namespace permission errors.

### 6. Verify the backend service exists

While a missing backend service typically results in `ResolvedRefs: False` rather than `Accepted: False`, confirm the service exists in `app-ns`:

```bash
kubectl get service my-service -n app-ns
```

---

## Summary: Most Likely Fix

For kgateway v2.3.1, the most common cause of `Accepted: False` on a cross-namespace HTTPRoute is a missing `ReferenceGrant`. Create the `ReferenceGrant` resource in `kgateway-system` namespace (shown above), and also verify the Gateway's `allowedRoutes.namespaces.from` is not set to `Same`.

**Diagnostic command to run first:**

```bash
kubectl get httproute my-app -n app-ns -o jsonpath='{.status.parents[*].conditions}' | jq .
```

This will give you the exact rejection reason and guide which fix to apply.
