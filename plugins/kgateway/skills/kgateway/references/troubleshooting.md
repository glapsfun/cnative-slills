# kgateway Troubleshooting Reference

## Systematic Diagnosis

When something isn't routing correctly, work down this checklist:

```
1. Is the control plane healthy?
   kubectl get pods -n kgateway-system
   kubectl logs deploy/kgateway -n kgateway-system | tail -50

2. Is the Gateway accepted and programmed?
   kubectl describe gateway <name> -n kgateway-system
   → status.conditions[type=Programmed].status: True

3. Is the HTTPRoute accepted?
   kubectl describe httproute <name> -n <namespace>
   → status.parents[].conditions[type=Accepted].status: True
   → status.parents[].conditions[type=ResolvedRefs].status: True

4. Is the proxy pod running?
   kubectl get pods -n kgateway-system -l app=<gateway-name>

5. Does the Envoy config look correct?
   kubectl port-forward deploy/<gateway-name> -n kgateway-system 19000
   curl http://localhost:19000/config_dump | jq '.configs[] | .["@type"]'
```

## Control Plane Debugging

```bash
# Port-forward to the control plane admin interface
kubectl port-forward deploy/kgateway -n kgateway-system 9095

# View the xDS snapshot (Envoy-specific translated config)
curl http://localhost:9095/snapshots/xds | jq .

# View the KRT snapshot (translated Kubernetes resources before xDS conversion)
curl http://localhost:9095/snapshots/krt | jq .

# Check and adjust log levels
curl http://localhost:9095/logging
curl -X POST http://localhost:9095/logging?level=debug

# pprof profiling
curl http://localhost:9095/debug/pprof/goroutine?debug=1
```

## Gateway Proxy Debugging

```bash
# Port-forward to the proxy admin interface
kubectl port-forward deploy/http -n kgateway-system 19000

# View full Envoy config
curl http://localhost:19000/config_dump

# View active listeners
curl http://localhost:19000/listeners

# View active clusters (backends)
curl http://localhost:19000/clusters

# View active routes
curl http://localhost:19000/routes

# View runtime values
curl http://localhost:19000/runtime

# Reset statistics
curl -X POST http://localhost:19000/reset_counters
```

## Common Issues

### Route Not Accepted

**Symptom:** `kubectl describe httproute` shows `Accepted: False`

**Causes and fixes:**
- `parentRefs` points to wrong Gateway name or namespace → verify with `kubectl get gateway -A`
- `sectionName` doesn't match any listener name in the Gateway → check listener names
- Namespace mismatch — route is in a different namespace than the Gateway and no `allowedRoutes` is set:
  ```yaml
  # In Gateway spec, allow routes from all namespaces:
  listeners:
  - name: http
    allowedRoutes:
      namespaces:
        from: All   # or Selector with labelSelector
  ```

### ResolvedRefs: False

**Symptom:** Route is accepted but `ResolvedRefs: False`

**Causes:**
- Backend Service doesn't exist or is in a different namespace
- Cross-namespace reference missing `ReferenceGrant` → create one (see `references/gateway-setup.md`)
- TLS cert Secret referenced in Gateway doesn't exist

```bash
kubectl get referencegrant -A
kubectl get secret <cert-name> -n kgateway-system
```

### Policy Not Applied

**Symptom:** TrafficPolicy exists but its behavior isn't observed

**Causes:**
- `targetRefs` incorrect — group/kind/name mismatch:
  ```bash
  kubectl describe trafficpolicy <name> -n <ns>
  # Look for status.conditions showing attachment errors
  ```
- Multiple policies targeting the same resource → oldest policy wins:
  ```bash
  kubectl get trafficpolicy -A --sort-by=.metadata.creationTimestamp
  ```
- Cross-namespace policy attachment requires explicit permission — check if your kgateway version supports this

### Cross-Namespace Reference Denied

**Symptom:** `ReferenceNotPermitted` in route conditions

**Fix:** Create a `ReferenceGrant` in the target namespace:
```bash
kubectl get referencegrant -n <target-namespace>
```
See `references/gateway-setup.md` for ReferenceGrant YAML.

### Gateway Pod Not Starting

```bash
kubectl describe pod -n kgateway-system -l app=<gateway-name>
# Look for: ImagePullBackOff, OOMKilled, resource limits exceeded

# Check GatewayParameters if custom resources are set
kubectl get gatewayparameters -A
```

### Envoy Config Not Updating

The control plane may have rejected a resource due to validation errors:

```bash
# Control plane logs show rejection reasons
kubectl logs deploy/kgateway -n kgateway-system | grep -i "rejected\|error\|warn"

# Check resource status for validation errors
kubectl describe httproute <name>
kubectl describe trafficpolicy <name>
```

If the xDS snapshot isn't updating, check the KRT snapshot at `http://localhost:9095/snapshots/krt` to see if translation is producing output.

### Authentication Not Working

**JWT not being validated:**
```bash
# Test with an invalid token — should get 401
curl -H "Authorization: Bearer invalid" http://gateway/protected

# Test with no token — should get 401  
curl http://gateway/protected

# Check JWKS URL is reachable from the control plane pod
kubectl exec -n kgateway-system deploy/kgateway -- \
  curl https://auth.example.com/.well-known/jwks.json
```

**API key auth not working:**
```bash
# Verify the secret exists and has the right keys
kubectl get secret api-keys -n kgateway-system -o yaml

# Check GatewayExtension status
kubectl describe gatewayextension api-key-auth -n kgateway-system
```

### Rate Limiting Not Triggering

```bash
# Check if TrafficPolicy is attached
kubectl describe trafficpolicy <name>

# For global rate limiting, verify the rate-limit service is reachable
kubectl exec -n kgateway-system deploy/http -- \
  curl http://rate-limit-server:8081/healthcheck
```

### Debug Logging

Enable verbose Envoy logging for a specific component:

```bash
# Increase log level on the running proxy (temporary, resets on restart)
kubectl port-forward deploy/http -n kgateway-system 19000
curl -X POST "http://localhost:19000/logging?level=debug"

# Persistent via GatewayParameters
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayParameters
spec:
  kube:
    envoyContainer:
      bootstrap:
        logLevel: debug
        componentLogLevels:
          router: trace
          filter: debug
```

Available log components: `admin`, `client`, `config`, `connection`, `filter`, `http`, `pool`, `router`, `runtime`, `upstream`

### Transformation Issues (v2.3.0+)

Classic transformation was removed in v2.3.0. If routes break after upgrading:

```bash
# Find all TrafficPolicies with transformations
kubectl get trafficpolicy -A -o json | \
  jq '.items[] | select(.spec.policy.transformation != null) | .metadata'
```

Migrate from classic to Rustformation syntax — the Inja templating engine is the same, but some classic-specific behaviors differ.

### Checking Resource Health Summary

```bash
# One-shot health check across all gateway resources
kubectl get gateway,httproute,trafficpolicy,listenerolicy,backendconfigpolicy -A

# Check for any resources with non-True conditions
kubectl get httproute -A -o json | \
  jq '.items[] | select(.status.parents[].conditions[] | select(.type=="Accepted" and .status!="True")) | .metadata'
```
