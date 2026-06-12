# Upgrading from kgateway v2.2 to v2.3

## Overview

kgateway (formerly Gloo Gateway / Gloo Edge, the open-source Kubernetes-native API gateway built on Envoy Proxy by Solo.io) follows a Kubernetes Gateway API-centric model from v2.x onward. Moving from v2.2 to v2.3 involves several areas you should carefully review.

---

## Key Changes and What to Watch Out For

### 1. Helm Chart and CRD Updates

- **Always upgrade CRDs first** before upgrading the Helm chart. In v2.x releases, CRDs are managed separately and must be applied before the controller is updated.
- Check the release notes for any new or modified CRDs (CustomResourceDefinitions). Failing to update CRDs before deploying the new controller version can result in reconciliation failures or missing fields being silently dropped.
- Run `kubectl diff` against the new CRD manifests before applying them to spot breaking field changes.

### 2. Kubernetes Gateway API Version Compatibility

- kgateway v2.3 targets a specific version of the upstream Kubernetes Gateway API (e.g., v1 or v1beta1). Confirm the Gateway API CRDs installed in your cluster match what v2.3 expects.
- Gateway API resources (GatewayClass, Gateway, HTTPRoute, etc.) may have graduated from beta to stable between patch cycles, requiring object re-creation or migration if you have resources pinned to an older API version.

### 3. GatewayClass and Controller Name

- Verify the `spec.controllerName` in your GatewayClass still matches the value used by the new controller. This value can change between minor versions.
- If the controller name changes, existing Gateways will become "orphaned" until the GatewayClass is updated.

### 4. Policy Attachment Changes (ExtensionRef / TargetRef)

kgateway uses policy attachment resources (e.g., RouteOption, VirtualHostOption, HTTPListenerPolicy) to extend Gateway API. Between v2.2 and v2.3:

- Check whether any policy CRDs have had field renames, new required fields, or deprecated fields removed.
- Review `RouteOption` and `VirtualHostOption` resources — Solo.io has been iterating on how policies attach to routes (via `targetRef` vs inline `extensionRef`), and a minor version bump can change the preferred or required attachment method.
- Policies referencing resources by `targetRef` should be verified against the new schema.

### 5. Envoy Proxy Version Bump

kgateway bundles a specific Envoy Proxy version. A minor kgateway release typically bumps the underlying Envoy version, which can affect:

- **Filter chain behavior** — Envoy filter API changes may affect custom Lua filters, WASM extensions, or ext-proc filters you have configured.
- **xDS and admin API changes** — if you scrape Envoy metrics or use the admin API directly, check for endpoint or label changes.
- **TLS defaults** — Envoy occasionally tightens default TLS cipher suites or minimum protocol versions.

### 6. Waypoint / Ambient Mesh Integration (if applicable)

If you are using kgateway in conjunction with Istio Ambient / waypoint proxy mode, v2.3 may change how the gateway integrates with the mesh data plane. Check Solo.io's release notes for any Ambient-related changes.

### 7. AI Gateway Features (if using LLM routing)

kgateway v2.x introduced AI gateway capabilities (LLM provider routing, token-based rate limiting, prompt guards). Between v2.2 and v2.3:

- New AI-specific CRDs or fields may have been added.
- Rate limit schema for token-based limits may have changed.
- Provider credential secret format may have evolved.

If you are not using AI gateway features, this section does not apply.

### 8. Rate Limiting and ExtAuth

- The rate limit server integration and ext-auth server integration have been areas of active development. Review the changelog for any changes to how `RateLimitConfig` or `AuthConfig` resources reference backends.
- Token/JWT claim extraction configuration can change between minor versions.

### 9. Observability and Metrics

- Prometheus metric label names and cardinality can change with an Envoy version bump.
- If you have dashboards or alerts tied to specific metric names (e.g., `envoy_http_downstream_rq_total`), audit them after upgrading.

### 10. Deprecation Removals

Minor versions sometimes remove fields that were deprecated in the prior minor version. Before upgrading:

- Run `kubectl get --all-namespaces` for each relevant CRD kind and inspect for any deprecation warnings in resource `status` conditions.
- Check your Helm values file against the new `values.yaml` schema — removed Helm values silently become no-ops.

---

## Recommended Upgrade Process

1. **Read the official v2.3 release notes and migration guide** at https://kgateway.dev or the Solo.io docs portal before doing anything else.
2. Back up all existing CRs: `kubectl get <kind> -A -o yaml > backup.yaml` for each kgateway CRD kind.
3. Apply updated CRDs: `kubectl apply -f https://<release-url>/crds.yaml`
4. Upgrade the Helm release: `helm upgrade kgateway kgateway/kgateway --version 2.3.x -f values.yaml`
5. Watch controller logs for reconciliation errors immediately after upgrade.
6. Validate route behavior with smoke tests before promoting to production.
7. If running multiple replicas, consider a canary rollout using a separate GatewayClass.

---

## Honest Limitations of This Response

This response is based on general knowledge of kgateway's v2.x architecture and typical patterns in Kubernetes gateway projects. I do not have the specific v2.3 release notes in my training data with high confidence. The actual breaking changes between v2.2.x and v2.3.x may differ from what is described above.

**You should always consult:**
- The official kgateway changelog: https://github.com/kgateway-dev/kgateway/releases
- The migration guide in the kgateway docs: https://kgateway.dev/docs
- Solo.io support channels if you are on an enterprise license

Using the `kubernetes-operator` skill or a web-search-enabled agent to pull the live release notes will give you a more accurate and complete answer than this training-data-only response.
