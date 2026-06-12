# kgateway Traffic Management Reference

## Request Matching

HTTPRoute rules match on path, headers, method, and query parameters. All conditions in a single `match` entry use AND logic; multiple `matches` entries use OR logic.

```yaml
rules:
- matches:
  - path:
      type: Exact          # Exact, PathPrefix, RegularExpression
      value: /api/v1/users
    headers:
    - name: X-Api-Version
      value: "2"
      type: Exact          # Exact, RegularExpression
    method: GET
    queryParams:
    - name: format
      value: json
  backendRefs:
  - name: users-service
    port: 8080
```

## Backend Destinations

### Kubernetes Service

```yaml
backendRefs:
- name: my-service
  namespace: default     # required for cross-namespace (needs ReferenceGrant)
  port: 8080
```

### External Backend (AWS Lambda)

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: Backend
metadata:
  name: my-lambda
  namespace: default
spec:
  awsLambda:
    functionName: my-function
    region: us-east-1
    credentials:
      secretRef:
        name: aws-credentials
---
backendRefs:
- group: gateway.kgateway.dev
  kind: Backend
  name: my-lambda
  port: 443
```

### Static Upstream Host

```yaml
spec:
  static:
    hosts:
    - addr: api.external.com
      port: 443
```

### Dynamic Forward Proxy

Route to hostnames resolved at request time (useful for egress gateways):

```yaml
spec:
  dynamicForwardProxy: {}
```

Combined with a TrafficPolicy `dynamicForwardProxy` setting on the route to resolve the `:authority` header.

## Traffic Splitting (Canary / Blue-Green)

```yaml
rules:
- matches:
  - path:
      type: PathPrefix
      value: /
  backendRefs:
  - name: app-stable
    port: 8080
    weight: 90
  - name: app-canary
    port: 8080
    weight: 10
```

Weights are relative — they don't need to sum to 100. To send all traffic to one backend, set its weight to 1 and others to 0.

## Route Delegation

Delegates routing responsibility from a parent HTTPRoute to child HTTPRoutes. The parent owns the path prefix; children define sub-routes under it.

```yaml
# Parent route (platform team, namespace: infra)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: root
  namespace: infra
spec:
  parentRefs:
  - name: http
    namespace: kgateway-system
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /team-a
    backendRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: team-a-routes
      namespace: team-a
---
# Child route (team A, namespace: team-a)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: team-a-routes
  namespace: team-a
spec:
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /team-a/api
    backendRefs:
    - name: team-a-service
      port: 8080
```

**Label-based delegation** — parent selects children by label:

```yaml
backendRefs:
- group: gateway.networking.k8s.io
  kind: HTTPRoute
  labelSelector:
    matchLabels:
      delegation: team-a
```

## Redirects

**HTTPS redirect** (redirect all HTTP to HTTPS):

```yaml
rules:
- matches:
  - path:
      type: PathPrefix
      value: /
  filters:
  - type: RequestRedirect
    requestRedirect:
      scheme: https
      statusCode: 301
```

**Path redirect:**

```yaml
filters:
- type: RequestRedirect
  requestRedirect:
    path:
      type: ReplaceFullPath
      replaceFullPath: /new-path
    statusCode: 302
```

**Host redirect:**

```yaml
filters:
- type: RequestRedirect
  requestRedirect:
    hostname: new.example.com
```

## Rewrites

**Path prefix rewrite** (strip the route prefix before forwarding):

```yaml
filters:
- type: URLRewrite
  urlRewrite:
    path:
      type: ReplacePrefixMatch
      replacePrefixMatch: /
```

**Host rewrite:**

```yaml
filters:
- type: URLRewrite
  urlRewrite:
    hostname: internal-service.cluster.local
```

## Header Manipulation

```yaml
filters:
- type: RequestHeaderModifier
  requestHeaderModifier:
    add:
    - name: X-Gateway-Version
      value: "kgateway-2.3"
    remove:
    - X-Internal-Debug
    set:
    - name: Host
      value: backend.internal
- type: ResponseHeaderModifier
  responseHeaderModifier:
    add:
    - name: X-Cache-Control
      value: no-store
```

## Transformations (Rustformation)

kgateway v2.3+ uses Rustformation exclusively (the classic C++ engine was removed). Use `TrafficPolicy`:

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
metadata:
  name: transform
  namespace: default
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: my-route
  policy:
    transformation:
      request:
        # Inja template — set a header from a query param
        headers:
          X-User-Id:
            text: "{{ query_string('user_id') }}"
        body:
          parseAs: json
      response:
        headers:
          X-Response-Time:
            text: "{{ response_header('x-process-ms') }}ms"
```

Available template variables: request headers, query params, body fields (when `parseAs: json`), dynamic metadata.

## DirectResponse

Return a fixed response without forwarding to any backend:

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: DirectResponse
metadata:
  name: maintenance
  namespace: default
spec:
  status: 503
  body: '{"error": "Service temporarily unavailable"}'
---
# Reference in HTTPRoute
backendRefs:
- group: gateway.kgateway.dev
  kind: DirectResponse
  name: maintenance
```

## External Processing (ExtProc)

Route requests through an external gRPC server that can modify headers/body before forwarding:

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayExtension
metadata:
  name: my-extproc
  namespace: kgateway-system
spec:
  type: ExtProc
  extProc:
    grpcService:
      backendRef:
        name: extproc-service
        port: 9191
---
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
metadata:
  name: use-extproc
  namespace: default
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: my-route
  policy:
    extProc:
      extensionRef:
        name: my-extproc
        namespace: kgateway-system
      processingMode:
        requestHeaderMode: SEND
        responseHeaderMode: SEND
```

## gRPC Routing (v2.3.0+)

Use `GRPCRoute` for protocol-aware routing with header matching on `:method` and `:path`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: grpc-route
  namespace: default
spec:
  parentRefs:
  - name: http
    namespace: kgateway-system
  rules:
  - matches:
    - method:
        service: helloworld.Greeter
        method: SayHello
  backendRefs:
  - name: grpc-service
    port: 9090
```

## Session Affinity

Consistent hashing to pin a client to a specific backend pod:

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: BackendConfigPolicy
metadata:
  name: sticky
  namespace: default
spec:
  targetRefs:
  - group: ""
    kind: Service
    name: my-service
  policy:
    loadBalancer:
      consistentHash:
        httpHeaderName: X-User-Id   # or useSourceIp: true, or httpCookie
```

## Compression

Enable gzip compression via TrafficPolicy:

```yaml
policy:
  compression:
    gzip:
      minContentLength: 1024
      contentType:
      - application/json
      - text/html
```

## Request Buffering

Buffer the full request body before forwarding (needed for transformations that read the body):

```yaml
policy:
  buffering:
    maxRequestBytes: 65536
    maxResponseBytes: 65536
```

## Proxy Protocol (Preserve Client IP)

Enable PROXY protocol on the Gateway listener to propagate the real client IP:

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: ListenerPolicy
metadata:
  name: proxy-protocol
  namespace: kgateway-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: http
  policy:
    proxyProtocol:
      rule: SANITIZE   # or USE_REMOTE_ADDRESS
```
