# kgateway Resiliency Reference

All route-level resiliency settings go in `TrafficPolicy`. Backend-level settings (circuit breakers, outlier detection, health checks) go in `BackendConfigPolicy`.

## Retries

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
metadata:
  name: retry-policy
  namespace: default
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: my-route
  policy:
    retries:
      numRetries: 3
      retryOn: "5xx,reset,retriable-4xx"
      perTryTimeout: 10s
      retryBackOff:
        baseInterval: 100ms
        maxInterval: 1s
```

`retryOn` values (comma-separated):
- `5xx` — retry on any 5xx response
- `reset` — retry if upstream connection reset
- `retriable-4xx` — retry on 409 Conflict
- `connect-failure` — retry if connection fails
- `refused-stream` — retry on HTTP/2 REFUSED_STREAM
- `gateway-error` — retry on 502, 503, 504

## Timeouts

```yaml
policy:
  timeout: 30s         # total request timeout

  # Fine-grained (via Envoy route-level config):
  idleTimeout: 60s     # max idle time on the stream
```

Per-try timeout is set in `retries.perTryTimeout` (see above).

For idle stream timeouts and HTTP connection-level timeouts, configure on `BackendConfigPolicy`:

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: BackendConfigPolicy
metadata:
  name: connection-settings
  namespace: default
spec:
  targetRefs:
  - group: ""
    kind: Service
    name: my-service
  policy:
    httpConnectionSettings:
      connectTimeout: 5s
      http2ProtocolOptions:
        initialConnectionWindowSize: 65536
```

## Circuit Breakers

Prevent cascading failures by limiting concurrent load on a backend:

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: BackendConfigPolicy
metadata:
  name: circuit-breaker
  namespace: default
spec:
  targetRefs:
  - group: ""
    kind: Service
    name: my-service
  policy:
    circuitBreakers:
      maxConnections: 100         # max concurrent TCP connections
      maxPendingRequests: 50      # max requests queued while waiting for a connection
      maxRequests: 200            # max concurrent active requests
      maxRetries: 3               # max concurrent retries
```

When any threshold is exceeded, Envoy returns 503 immediately rather than queuing.

## Outlier Detection (Automatic Eject)

Automatically removes unhealthy backends from the load-balancing pool:

```yaml
policy:
  outlierDetection:
    consecutive5xx: 5                   # eject after 5 consecutive 5xx
    consecutiveGatewayFailure: 3        # eject after 3 gateway errors
    interval: 10s                       # evaluation interval
    baseEjectionTime: 30s               # minimum ejection duration
    maxEjectionPercent: 50              # max % of hosts that can be ejected
    successRateMinimumHosts: 3          # min hosts before stat-based ejection kicks in
    successRateRequestVolume: 100       # min requests per interval for stat-based ejection
    successRateStdevFactor: 1900        # (1900 = 1.9 standard deviations below mean)
```

## Fault Injection (Testing)

Inject artificial failures to test application resilience. Only applies to a percentage of traffic:

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
metadata:
  name: fault-injection
  namespace: default
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: my-route
  policy:
    faults:
      # Delay: add latency to N% of requests
      delay:
        percentage: 10              # 10% of requests
        fixedDelay: 5s
      # Abort: return error status for N% of requests
      abort:
        percentage: 5               # 5% of requests
        httpStatus: 503
```

Use fault injection in staging/testing environments only. Never use in production.

## Traffic Mirroring (Shadow Traffic)

Send a copy of traffic to a shadow backend without affecting the primary response:

```yaml
rules:
- matches:
  - path:
      type: PathPrefix
      value: /
  backendRefs:
  - name: app-primary
    port: 8080
  filters:
  - type: RequestMirror
    requestMirror:
      backendRef:
        name: app-shadow
        port: 8080
      percent: 100         # % of traffic to mirror
```

The primary backend's response is returned to the client; the shadow backend receives a best-effort copy. Errors from the shadow do not affect client traffic.

## Backend Health Checks

Active health checks probe backends proactively:

```yaml
policy:
  healthCheck:
    interval: 10s
    timeout: 5s
    unhealthyThreshold: 2      # consecutive failures before ejection
    healthyThreshold: 1        # consecutive successes before re-admission
    httpHealthCheck:
      path: /healthz
      expectedStatuses:
      - start: 200
        end: 299
    # or for gRPC:
    # grpcHealthCheck:
    #   serviceName: ""
```

## TCP Keepalive

Maintain long-lived upstream connections to prevent stale connection errors:

```yaml
policy:
  tcpKeepalive:
    probes: 9
    time: 600s       # idle time before probes start
    interval: 75s    # interval between probes
```

## Combining Resiliency Policies

Policies compose — a route can have retries + timeout + fault injection simultaneously. Typical production pattern:

```yaml
policy:
  timeout: 30s
  retries:
    numRetries: 2
    retryOn: "5xx,reset"
    perTryTimeout: 10s
```

With `timeout: 30s` and `perTryTimeout: 10s` and `numRetries: 2`, the total max time is `min(30s, 3 * 10s)` = 30s.
