# kgateway Security Reference

## TLS/HTTPS Setup

### Basic HTTPS

```bash
# 1. Create TLS secret
kubectl create secret tls my-cert \
  --cert=tls.crt --key=tls.key \
  -n kgateway-system

# 2. Configure Gateway listener (see gateway-setup.md)
# 3. Create HTTPRoute with HTTPS redirect from HTTP
```

HTTPS redirect pattern — HTTP listener redirects, HTTPS listener serves:

```yaml
# HTTP Gateway listener + redirect route
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: https-redirect
  namespace: default
spec:
  parentRefs:
  - name: http            # HTTP listener
    namespace: kgateway-system
    sectionName: http
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        statusCode: 301
---
# HTTPS route serving content
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app-https
  namespace: default
spec:
  parentRefs:
  - name: https           # HTTPS listener
    namespace: kgateway-system
    sectionName: https
  rules:
  - backendRefs:
    - name: my-service
      port: 8080
```

### Backend TLS (originate TLS to upstream)

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: BackendConfigPolicy
metadata:
  name: backend-tls
  namespace: default
spec:
  targetRefs:
  - group: ""
    kind: Service
    name: my-tls-service
  policy:
    tls:
      mode: SIMPLE          # SIMPLE = one-way TLS, MUTUAL = mTLS to backend
      caCertificates:
        secretRef:
          name: backend-ca-cert
```

## JWT Authentication

### Basic JWT Validation

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
metadata:
  name: jwt-auth
  namespace: default
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: protected-route
  policy:
    jwt:
      providers:
      - name: my-idp
        issuer: "https://auth.example.com"
        audiences:
        - "my-api-audience"
        jwks:
          remote:
            url: "https://auth.example.com/.well-known/jwks.json"
            cacheDuration: 300s
```

### JWT Claim-Based RBAC

Extract claims from validated JWTs to make routing or access decisions:

```yaml
policy:
  jwt:
    providers:
    - name: my-idp
      issuer: "https://auth.example.com"
      jwks:
        remote:
          url: "https://auth.example.com/.well-known/jwks.json"
      claimsToHeaders:
      - claim: sub
        header: X-User-Id
      - claim: roles
        header: X-User-Roles
    requirementRefs:
    - name: my-idp
      claims:
      - name: roles
        values: ["admin", "editor"]    # require at least one of these values
```

## External Authentication

### API Key Authentication

```bash
# 1. Create secret with API keys
kubectl create secret generic api-keys \
  --from-literal=key1=client-a-secret \
  --from-literal=key2=client-b-secret \
  -n kgateway-system
```

```yaml
# 2. Create GatewayExtension
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayExtension
metadata:
  name: api-key-auth
  namespace: kgateway-system
spec:
  type: Auth
  auth:
    apiKey:
      secretRef:
        name: api-keys
        namespace: kgateway-system
      labelSelector:
        env: production
      header: X-Api-Key          # header name to extract key from
---
# 3. Attach via TrafficPolicy
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
metadata:
  name: require-api-key
  namespace: default
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: my-route
  policy:
    extAuth:
      extensionRef:
        name: api-key-auth
        namespace: kgateway-system
```

### Basic Authentication

```yaml
spec:
  type: Auth
  auth:
    basicAuth:
      secretRef:
        name: htpasswd-secret
        namespace: kgateway-system
```

Create the htpasswd secret:
```bash
htpasswd -bn user1 password1 > htpasswd
kubectl create secret generic htpasswd-secret \
  --from-file=htpasswd=htpasswd \
  -n kgateway-system
```

### Custom External Auth Service

```yaml
spec:
  type: Auth
  auth:
    grpcService:
      backendRef:
        name: my-authz-service
        port: 9001
      timeout: 5s
      statusOnError: 403
      failureModeAllow: false    # deny on auth service error
```

## Rate Limiting

### Local Rate Limiting (per-proxy-instance)

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
metadata:
  name: local-rate-limit
  namespace: default
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: my-route
  policy:
    rateLimit:
      local:
        tokenBucket:
          maxTokens: 1000
          tokensPerFill: 100
          fillInterval: 60s
        percentEnabled: 100      # v2.3.0+: % of requests subject to limiting
        percentEnforced: 100     # v2.3.0+: % of limited requests that get 429
```

### Global Rate Limiting (requires external rate-limit server)

```yaml
# 1. Create GatewayExtension pointing at rate-limit server
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayExtension
metadata:
  name: global-ratelimit
  namespace: kgateway-system
spec:
  type: RateLimit
  rateLimit:
    grpcService:
      backendRef:
        name: rate-limit-server
        port: 8081
---
# 2. TrafficPolicy with descriptors
policy:
  rateLimit:
    global:
      extensionRef:
        name: global-ratelimit
        namespace: kgateway-system
      descriptors:
      - entries:
        - remoteAddress: {}
      - entries:
        - requestHeader:
            headerName: X-User-Id
            descriptorKey: user_id
```

## CORS

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
metadata:
  name: cors-policy
  namespace: default
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: my-route
  policy:
    cors:
      allowOrigins:
      - "https://app.example.com"
      - "https://*.trusted.com"    # spec-compliant wildcard (v2.3.0+ only)
      allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
      allowHeaders: ["Content-Type", "Authorization", "X-Custom-Header"]
      exposeHeaders: ["X-Response-Id"]
      allowCredentials: true
      maxAge: 86400
```

**CORS wildcard note (v2.3.0):** Patterns like `https://app.*` are rejected. Use `https://*.domain.com` format only.

## CSRF Protection

```yaml
policy:
  csrf:
    filterEnabled:
      defaultValue:
        numerator: 100
        denominator: HUNDRED
    additionalOrigins:
    - exact: "https://my-app.example.com"
```

## IP-Based Access Control (v2.3.0+)

```yaml
policy:
  ipAllowList:
    allow:
    - 10.0.0.0/8
    - 192.168.1.0/24
    - 203.0.113.5       # specific IP
```

Deny-list mode:
```yaml
policy:
  ipDenyList:
    deny:
    - 198.51.100.0/24
```

## Access Logging

Configure at the Gateway or listener level with `ListenerPolicy`:

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
    # JSON to stdout
    - fileSink:
        path: /dev/stdout
        jsonFormat:
          start_time: "%START_TIME%"
          method: "%REQ(:METHOD)%"
          path: "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%"
          protocol: "%PROTOCOL%"
          response_code: "%RESPONSE_CODE%"
          response_flags: "%RESPONSE_FLAGS%"
          bytes_sent: "%BYTES_SENT%"
          duration: "%DURATION%"
          upstream_cluster: "%UPSTREAM_CLUSTER%"
          x_forwarded_for: "%REQ(X-FORWARDED-FOR)%"
          user_agent: "%REQ(USER-AGENT)%"

    # gRPC sink (e.g., to an OTel collector)
    - grpcService:
        backendRef:
          name: otel-collector
          port: 4317
        additionalRequestHeadersToLog:
        - x-request-id
        - x-b3-traceid
```

## Istio mTLS Integration

When running with Istio sidecar mesh, enforce mTLS between kgateway and upstream services:

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: BackendConfigPolicy
metadata:
  name: istio-mtls
  namespace: default
spec:
  targetRefs:
  - group: ""
    kind: Service
    name: my-mesh-service
  policy:
    tls:
      mode: ISTIO_MUTUAL    # Use Istio's SPIFFE cert for mTLS
```

For Istio ambient mesh setup, see the Istio integration section in `references/operations.md`.
