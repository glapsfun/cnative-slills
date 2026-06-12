# JWT Authentication with Auth0 on kgateway HTTPRoute

## Overview

kgateway (the open-source Kubernetes-native API gateway based on Envoy, formerly known as Gloo Edge OSS) supports JWT authentication through its `VirtualHostOption` and `RouteOption` custom resources. To integrate Auth0 JWT validation with path-based rules (require auth on `/api/*`, allow `/api/public` unauthenticated), you need to configure a JWT provider and apply route-level policy overrides.

---

## Prerequisites

- kgateway installed in your cluster (Helm chart `kgateway` or `gloo`)
- An Auth0 tenant with an API configured
- Your Auth0 domain (e.g., `your-tenant.us.auth0.com`)
- The JWKS URI from Auth0: `https://your-tenant.us.auth0.com/.well-known/jwks.json`
- An existing `Gateway` and `HTTPRoute` resource

---

## Step 1: Create the JWT Provider via VirtualHostOption

kgateway uses the `VirtualHostOption` CRD to attach policies to a virtual host. JWT configuration lives under `spec.options.jwt`.

```yaml
apiVersion: gateway.solo.io/v1
kind: VirtualHostOption
metadata:
  name: jwt-auth0
  namespace: default
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: my-gateway
      namespace: default
  options:
    jwt:
      providers:
        auth0:
          issuer: "https://your-tenant.us.auth0.com/"
          audiences:
            - "https://your-api-identifier"
          jwks:
            remote:
              url: "https://your-tenant.us.auth0.com/.well-known/jwks.json"
              upstreamRef:
                name: auth0-jwks-upstream
                namespace: default
          claimsToHeaders:
            - claim: sub
              header: x-user-id
            - claim: email
              header: x-user-email
          keepToken: false
```

**Key fields:**
- `issuer`: Must exactly match the `iss` claim in Auth0 JWTs. Auth0 includes a trailing slash.
- `audiences`: The API identifier (audience) you configured in your Auth0 API settings.
- `jwks.remote.url`: Auth0's public JWKS endpoint for token signature verification.
- `keepToken`: Set to `false` to strip the Authorization header before forwarding to upstream services (optional but common for security).

---

## Step 2: Create an Upstream for the JWKS Endpoint

kgateway needs an `Upstream` to reach the Auth0 JWKS endpoint for fetching public keys:

```yaml
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: auth0-jwks-upstream
  namespace: default
spec:
  static:
    hosts:
      - addr: "your-tenant.us.auth0.com"
        port: 443
  sslConfig:
    sni: "your-tenant.us.auth0.com"
```

---

## Step 3: Configure HTTPRoute with Path-Based JWT Rules

To require JWT on all `/api/*` paths but allow `/api/public` without authentication, you need two route configurations with a `RouteOption` to disable JWT on the public path.

### HTTPRoute with ordered rules

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-api-route
  namespace: default
spec:
  parentRefs:
    - name: my-gateway
      namespace: default
  rules:
    # Rule 1: Public endpoint — no auth required (matched first)
    - matches:
        - path:
            type: PathPrefix
            value: /api/public
      filters:
        - type: ExtensionRef
          extensionRef:
            group: gateway.solo.io
            kind: RouteOption
            name: disable-jwt
      backendRefs:
        - name: my-api-service
          port: 8080

    # Rule 2: All other /api/* paths — JWT required
    - matches:
        - path:
            type: PathPrefix
            value: /api
      filters:
        - type: ExtensionRef
          extensionRef:
            group: gateway.solo.io
            kind: RouteOption
            name: require-jwt
      backendRefs:
        - name: my-api-service
          port: 8080
```

### RouteOption to disable JWT for /api/public

```yaml
apiVersion: gateway.solo.io/v1
kind: RouteOption
metadata:
  name: disable-jwt
  namespace: default
spec:
  options:
    jwt:
      disable: true
```

### RouteOption to explicitly require JWT for /api/*

```yaml
apiVersion: gateway.solo.io/v1
kind: RouteOption
metadata:
  name: require-jwt
  namespace: default
spec:
  options:
    jwt:
      providers:
        auth0:
          issuer: "https://your-tenant.us.auth0.com/"
          audiences:
            - "https://your-api-identifier"
          jwks:
            remote:
              url: "https://your-tenant.us.auth0.com/.well-known/jwks.json"
              upstreamRef:
                name: auth0-jwks-upstream
                namespace: default
```

---

## Step 4: Apply All Resources

```bash
kubectl apply -f auth0-jwks-upstream.yaml
kubectl apply -f jwt-virtualhostoption.yaml
kubectl apply -f disable-jwt-routeoption.yaml
kubectl apply -f require-jwt-routeoption.yaml
kubectl apply -f my-api-httproute.yaml
```

---

## Step 5: Verify the Configuration

### Test that /api/public is accessible without a token

```bash
curl -v http://<gateway-ip>/api/public
# Expected: 200 OK
```

### Test that /api/protected requires a token

```bash
curl -v http://<gateway-ip>/api/protected
# Expected: 401 Unauthorized

# With a valid Auth0 token:
TOKEN=$(curl -s --request POST \
  --url "https://your-tenant.us.auth0.com/oauth/token" \
  --header "content-type: application/json" \
  --data '{
    "client_id": "<YOUR_CLIENT_ID>",
    "client_secret": "<YOUR_CLIENT_SECRET>",
    "audience": "https://your-api-identifier",
    "grant_type": "client_credentials"
  }' | jq -r '.access_token')

curl -v -H "Authorization: Bearer $TOKEN" http://<gateway-ip>/api/protected
# Expected: 200 OK
```

---

## How Route Matching Priority Works

HTTPRoute rules are evaluated in order. Because `/api/public` is listed **before** `/api` (prefix match), requests to `/api/public` match the first rule and get the `disable-jwt` RouteOption applied. All other `/api/*` requests fall through to the second rule requiring JWT validation.

**Important:** The order of rules in the `HTTPRoute` spec matters. Always place more specific paths before less specific ones.

---

## Troubleshooting

### JWT validation fails with 401

1. **Check the issuer:** Auth0 JWTs include a trailing slash in `iss`. Ensure your `issuer` field matches exactly: `https://your-tenant.us.auth0.com/`
2. **Check the audience:** The `aud` claim in the JWT must match one of the values in `audiences`.
3. **JWKS connectivity:** Verify kgateway can reach the JWKS endpoint. Check the `Upstream` resource and any network policies.

```bash
kubectl logs -n gloo-system deploy/gateway-proxy | grep jwt
```

### Check VirtualHostOption status

```bash
kubectl get virtualhostoption jwt-auth0 -o yaml
# Look at .status.conditions for any errors
```

### Inspect the Envoy config

```bash
kubectl exec -n gloo-system deploy/gateway-proxy -- \
  wget -qO- localhost:19000/config_dump | \
  python3 -m json.tool | grep -A 20 "jwt_authn"
```

---

## Alternative: Using a Single VirtualHostOption with Route-Level Overrides

Instead of defining JWT config in both `VirtualHostOption` and `RouteOption`, you can define it once at the virtual host level and only use `RouteOption` to disable it for public routes:

1. Define the full JWT config in `VirtualHostOption` (as in Step 1).
2. Apply only the `disable-jwt` RouteOption to the `/api/public` route.
3. All other routes inherit JWT enforcement from the virtual host policy.

This is the recommended pattern as it reduces duplication.

---

## Summary

| Resource | Purpose |
|---|---|
| `Upstream` | Defines how kgateway reaches Auth0 JWKS endpoint |
| `VirtualHostOption` | Sets default JWT policy for all routes on the Gateway |
| `RouteOption` (disable-jwt) | Disables JWT check for `/api/public` |
| `RouteOption` (require-jwt) | Optionally reinforces JWT check on `/api/*` |
| `HTTPRoute` | Defines path routing and attaches RouteOptions via ExtensionRef |

The key insight is that **route order matters** in HTTPRoute, and kgateway's `RouteOption` with `jwt.disable: true` is the mechanism to carve out unauthenticated exceptions from a broadly-enforced JWT policy.
