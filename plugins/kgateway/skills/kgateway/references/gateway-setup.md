# kgateway Gateway Setup Reference

## GatewayClass

kgateway installs a `GatewayClass` named `kgateway` automatically. Reference it in every Gateway:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: http
  namespace: kgateway-system
spec:
  gatewayClassName: kgateway   # always this value
  listeners:
  - name: http
    protocol: HTTP
    port: 8080
```

## Listener Types

### HTTP Listener

```yaml
listeners:
- name: http
  protocol: HTTP
  port: 8080
```

### HTTPS Listener (TLS termination)

```yaml
listeners:
- name: https
  protocol: HTTPS
  port: 8443
  tls:
    mode: Terminate
    certificateRefs:
    - name: my-tls-secret      # Kubernetes Secret type: kubernetes.io/tls
      namespace: kgateway-system
```

Create the TLS secret:
```bash
kubectl create secret tls my-tls-secret \
  --cert=tls.crt --key=tls.key \
  -n kgateway-system
```

### mTLS Listener (require client certificates)

```yaml
listeners:
- name: mtls
  protocol: HTTPS
  port: 8443
  tls:
    mode: Terminate
    certificateRefs:
    - name: server-tls
    clientValidation:
      caCertificateRefs:
      - name: client-ca
        kind: Secret
```

### SNI-Based Routing

Route different TLS traffic by SNI hostname on the same port:

```yaml
listeners:
- name: app-a
  protocol: HTTPS
  port: 8443
  hostname: app-a.example.com
  tls:
    mode: Terminate
    certificateRefs:
    - name: app-a-tls
- name: app-b
  protocol: HTTPS
  port: 8443
  hostname: app-b.example.com
  tls:
    mode: Terminate
    certificateRefs:
    - name: app-b-tls
```

### TLS Passthrough

Pass TLS traffic to the backend without terminating at the gateway:

```yaml
listeners:
- name: passthrough
  protocol: TLS
  port: 8443
  tls:
    mode: Passthrough
```

Route with `TLSRoute`:
```yaml
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TLSRoute
metadata:
  name: my-tls-app
spec:
  parentRefs:
  - name: my-gateway
    sectionName: passthrough
  rules:
  - backendRefs:
    - name: my-tls-service
      port: 8443
```

### TCP Listener

```yaml
listeners:
- name: tcp
  protocol: TCP
  port: 5432
```

### HTTP/1.0 and HTTP/0.9 Support

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: ListenerPolicy
metadata:
  name: legacy-http
  namespace: kgateway-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: http
  policy:
    http1Settings:
      enableTrailers: true
      overrideStreamErrorOnInvalidHttpMessage: true
      http10RequestRejection: false
```

## GatewayParameters — Customizing the Proxy Pod

`GatewayParameters` controls the Envoy proxy Deployment generated for each Gateway.

```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayParameters
metadata:
  name: custom-proxy
  namespace: kgateway-system
spec:
  kube:
    # Resource requests/limits for the Envoy container
    envoyContainer:
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 512Mi
      bootstrap:
        logLevel: info   # trace, debug, info, warn, error, critical, off

    # Replica count
    deployment:
      replicas: 2

    # Annotations on the generated pods
    podTemplate:
      extraAnnotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "19000"

    # Service type overrides
    service:
      type: LoadBalancer
```

Reference the GatewayParameters from the Gateway via annotation:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: http
  namespace: kgateway-system
  annotations:
    gateway.kgateway.dev/gateway-parameters-name: custom-proxy
spec:
  gatewayClassName: kgateway
  listeners:
  - name: http
    protocol: HTTP
    port: 8080
```

## Static IP for a Gateway (v2.3.0+)

```yaml
spec:
  addresses:
  - type: IPAddress
    value: "10.100.0.50"
```

## Self-Managed Gateways

To manage the Envoy pod yourself (bring your own deployment), disable kgateway's automatic provisioning:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: self-managed
  namespace: kgateway-system
  annotations:
    gateway.kgateway.dev/managed: "false"
spec:
  gatewayClassName: kgateway
  ...
```

## Cross-Namespace Routes (ReferenceGrant)

When an `HTTPRoute` in namespace `team-a` references a Service in namespace `backends`:

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-team-a
  namespace: backends         # namespace of the Service being referenced
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: team-a         # namespace that contains the HTTPRoute
  to:
  - group: ""
    kind: Service
```

## Checking Gateway Status

```bash
kubectl describe gateway http -n kgateway-system
# Look for:
# status.conditions[].type: Programmed (True = gateway proxy is running and ready)
# status.conditions[].type: Accepted  (True = gateway config is valid)
# status.listeners[].conditions[].type: ResolvedRefs (True = all cert refs resolved)
```
