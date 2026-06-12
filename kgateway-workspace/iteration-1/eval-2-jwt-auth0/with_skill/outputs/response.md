# Setting Up JWT Authentication with Auth0 on kgateway HTTPRoute

## Overview

To require JWT authentication for `/api/*` while allowing `/api/public` without auth, you need to:

1. Split your routing into two HTTPRoutes (protected and public), or use a single HTTPRoute with rule-level policy targeting
2. Create a `TrafficPolicy` with JWT validation pointing at Auth0's JWKS endpoint
3. Attach the policy to the protected route only

---

## Step 1: Create Your HTTPRoutes

Split the routing into a **public** route and a **protected** route. This is the cleanest approach because `TrafficPolicy` attaches at the HTTPRoute level.

```yaml
# Public route — no auth required
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-public
  namespace: default
spec:
  parentRefs:
  - name: http
    namespace: kgateway-system
  hostnames:
  - "api.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api/public
    backendRefs:
    - name: my-api-service
      port: 8080
---
# Protected route — JWT required
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-protected
  namespace: default
spec:
  parentRefs:
  - name: http
    namespace: kgateway-system
  hostnames:
  - "api.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: my-api-service
      port: 8080
```

> **Order matters:** The more specific `/api/public` path is in a separate HTTPRoute so it is matched first without JWT enforcement. The `/api` route covers everything else under `/api/*`.

---

## Step 2: Create the JWT TrafficPolicy for Auth0

Auth0 exposes its JWKS endpoint at `https://<your-tenant>.auth0.com/.well-known/jwks.json`. Replace `YOUR_TENANT` and `YOUR_API_AUDIENCE` with your actual Auth0 tenant domain and API identifier (audience).

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
metadata:
  name: auth0-jwt-policy
  namespace: default
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: api-protected          # targets only the protected route
  policy:
    jwt:
      providers:
      - name: auth0
        issuer: "https://YOUR_TENANT.auth0.com/"
        audiences:
        - "YOUR_API_AUDIENCE"    # the API identifier you set in Auth0
        jwks:
          remote:
            url: "https://YOUR_TENANT.auth0.com/.well-known/jwks.json"
            cacheDuration: 300s  # cache keys for 5 minutes
```

**Auth0-specific values to fill in:**
- `issuer`: Your Auth0 domain URL, e.g. `https://my-app.us.auth0.com/` (trailing slash required)
- `audiences`: The "Identifier" field of your Auth0 API (e.g. `https://api.example.com`)
- `jwks.remote.url`: `https://YOUR_TENANT.auth0.com/.well-known/jwks.json`

---

## Step 3: Apply Everything

```bash
kubectl apply -f httproutes.yaml
kubectl apply -f jwt-policy.yaml
```

Verify the policy was accepted:

```bash
kubectl describe trafficpolicy auth0-jwt-policy -n default
kubectl describe httproute api-protected -n default
```

---

## Optional: Forward JWT Claims to Your Backend

If your backend needs user identity info from the validated token, use `claimsToHeaders` to extract JWT claims and pass them as request headers:

```yaml
policy:
  jwt:
    providers:
    - name: auth0
      issuer: "https://YOUR_TENANT.auth0.com/"
      audiences:
      - "YOUR_API_AUDIENCE"
      jwks:
        remote:
          url: "https://YOUR_TENANT.auth0.com/.well-known/jwks.json"
          cacheDuration: 300s
      claimsToHeaders:
      - claim: sub
        header: X-User-Id
      - claim: email
        header: X-User-Email
```

---

## Optional: Require Specific Roles (RBAC)

To further restrict access to users with specific roles (using Auth0 custom claims):

```yaml
policy:
  jwt:
    providers:
    - name: auth0
      issuer: "https://YOUR_TENANT.auth0.com/"
      audiences:
      - "YOUR_API_AUDIENCE"
      jwks:
        remote:
          url: "https://YOUR_TENANT.auth0.com/.well-known/jwks.json"
    requirementRefs:
    - name: auth0
      claims:
      - name: "https://my-app.com/roles"   # Auth0 custom claim namespace
        values: ["admin", "editor"]         # user must have at least one of these
```

---

## Testing

```bash
# Should return 401 (no token)
curl -i https://api.example.com/api/users

# Should return 200 (valid Auth0 token)
TOKEN=$(curl -s -X POST https://YOUR_TENANT.auth0.com/oauth/token \
  -H "Content-Type: application/json" \
  -d '{"client_id":"CLIENT_ID","client_secret":"CLIENT_SECRET","audience":"YOUR_API_AUDIENCE","grant_type":"client_credentials"}' \
  | jq -r '.access_token')

curl -i -H "Authorization: Bearer $TOKEN" https://api.example.com/api/users

# Should return 200 WITHOUT a token (public route, no policy attached)
curl -i https://api.example.com/api/public
```

---

## Troubleshooting

**401 on all requests including /api/public:**
- Check that `api-public` HTTPRoute is separate from `api-protected` and has no TrafficPolicy attached to it.
- Run `kubectl get trafficpolicy -A` to confirm no stray policy targets the public route.

**401 with valid token:**
- Verify `issuer` exactly matches the `iss` claim in your JWT (decode at jwt.io). Auth0 issues with a trailing slash.
- Verify `audiences` matches the `aud` claim in your JWT.
- Check JWKS URL is reachable from inside the cluster: `kubectl exec -n kgateway-system deploy/<gateway-name> -- curl -s https://YOUR_TENANT.auth0.com/.well-known/jwks.json`

**Policy not taking effect:**
```bash
kubectl describe trafficpolicy auth0-jwt-policy -n default
# Look for status conditions — "Accepted: True"

kubectl port-forward deploy/kgateway -n kgateway-system 9095
# Visit http://localhost:9095/snapshots/xds to verify JWT filter appears in Envoy config
```

**Enable proxy debug logging temporarily:**
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
        logLevel: debug
```
Then check `kubectl logs -n kgateway-system deploy/<gateway-name>` for JWT validation details.
