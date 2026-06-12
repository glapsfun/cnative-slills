# kgateway Operations Reference

## Observability

### OpenTelemetry Tracing (v2.3.0+)

Deploy an OTel collector and configure tracing at listener or per-route level:

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: ListenerPolicy
metadata:
  name: tracing
  namespace: kgateway-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: http
  policy:
    tracing:
      provider:
        openTelemetry:
          grpcService:
            backendRef:
              name: otel-collector
              port: 4317
      resourceDetectors:
        environment: {}      # auto-populates resource attributes from env vars
      samplingFraction: 0.1  # sample 10% of requests
```

Per-route tracing override:
```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
spec:
  policy:
    tracing:
      samplingFraction: 1.0    # 100% for this route
      customTags:
      - tag: user-id
        requestHeader:
          name: X-User-Id
```

### Metrics

Envoy gateway proxy exposes Prometheus metrics at `:19000/stats/prometheus`.

```bash
# Port-forward and scrape metrics
kubectl port-forward deploy/http -n kgateway-system 19000
curl http://localhost:19000/stats/prometheus | grep envoy_http
```

Key metrics:
- `envoy_http_downstream_rq_total` — total requests
- `envoy_http_downstream_rq_5xx` — 5xx responses
- `envoy_cluster_upstream_rq_total` — requests to each backend
- `envoy_cluster_upstream_rq_time` — upstream response time histogram
- `envoy_listener_downstream_cx_active` — active connections

Scrape the control plane metrics (port 9091):
```bash
kubectl port-forward deploy/kgateway -n kgateway-system 9091
curl http://localhost:9091/metrics
```

### Access Logging

See `references/security.md` for access log configuration examples.

## Integrations

### Argo Rollouts (Canary Analysis)

kgateway integrates with Argo Rollouts to drive traffic splits during canary deployments. Install the kgateway Argo Rollouts plugin, then reference the HTTPRoute in your Rollout spec:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
spec:
  strategy:
    canary:
      canaryService: my-app-canary
      stableService: my-app-stable
      trafficRouting:
        plugins:
          kgateway:
            httpRoute: my-app-route
            namespace: default
      steps:
      - setWeight: 20
      - pause: {duration: 5m}
      - setWeight: 50
      - pause: {duration: 5m}
```

### cert-manager

Automate TLS certificate provisioning with cert-manager. cert-manager can watch `Gateway` resources and create/renew certificates automatically:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: https
  namespace: kgateway-system
  annotations:
    cert-manager.io/issuer: letsencrypt-prod
spec:
  listeners:
  - name: https
    protocol: HTTPS
    port: 8443
    tls:
      mode: Terminate
      certificateRefs:
      - name: https-cert    # cert-manager creates this Secret
```

### ExternalDNS

Automatically create DNS records for Gateway LoadBalancer IPs:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: http
  namespace: kgateway-system
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "*.example.com"
```

### AWS Elastic Load Balancers

**Network Load Balancer (NLB):**
```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayParameters
metadata:
  name: nlb-params
  namespace: kgateway-system
spec:
  kube:
    service:
      type: LoadBalancer
      extraAnnotations:
        service.beta.kubernetes.io/aws-load-balancer-type: nlb
        service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
```

**Application Load Balancer (ALB):**
Use the AWS Load Balancer Controller — set the Gateway service type to `NodePort` and configure an Ingress pointing at it, or use the ALB's target group binding.

### Istio Integration

**Ambient mesh ingress** (ztunnel handles L4, waypoint handles L7):

```bash
# Label namespace for ambient mesh
kubectl label namespace default istio.io/dataplane-mode=ambient

# kgateway serves as the ingress; traffic passes through ztunnel
# No special kgateway config needed — works out of the box
```

**Sidecar mesh ingress** — enable Istio injection in the gateway namespace and configure mTLS to upstreams:

```bash
# Inject sidecar into kgateway-system (optional — kgateway can use ISTIO_MUTUAL directly)
kubectl label namespace kgateway-system istio-injection=enabled
```

Enable ServiceEntry watching (required for Istio virtual services):
```bash
helm upgrade kgateway ... \
  --set controller.env.KGW_ENABLE_ISTIO_INTEGRATION=true
```

## Upgrade Operations

See `references/installation.md` for the full upgrade procedure.

Quick upgrade checklist:
1. Review release notes at https://github.com/kgateway-dev/kgateway/releases
2. Check for breaking changes in this file's version matrix
3. Upgrade Gateway API CRDs first
4. Upgrade kgateway-crds Helm chart
5. Upgrade kgateway control plane Helm chart (always pass `--reuse-values` or `-f values.yaml`)
6. Verify pods and route status

## Multi-Namespace Gateway Management

kgateway watches all namespaces by default. To restrict to specific namespaces:

```yaml
controller:
  env:
    WATCH_NAMESPACES: "team-a,team-b,kgateway-system"
```

## High Availability

```yaml
controller:
  replicaCount: 2
  podDisruptionBudget:
    enabled: true
    minAvailable: 1
```

Gateway proxy scaling:
```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayParameters
spec:
  kube:
    deployment:
      replicas: 3
    podTemplate:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app: kgateway
```
