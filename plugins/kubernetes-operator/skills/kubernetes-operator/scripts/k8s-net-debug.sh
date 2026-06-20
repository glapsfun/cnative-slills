#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: k8s-net-debug.sh -n NAMESPACE SERVICE

Read-only triage for the SKILL.md "Service not reachable" playbook. For the
named Service it reports, in order:
  1. Service spec: type, clusterIP, selector, and the port -> targetPort chain.
  2. EndpointSlices: how many endpoints are Ready (empty = selector matches no
     Ready pods, the most common cause).
  3. Pods matching the selector and whether each is Ready, so selector/label and
     readiness mismatches are obvious.
  4. NetworkPolicies in the namespace that select the backend pods (these make
     traffic deny-by-default for the directions they list).
  5. The cluster DNS FQDN to test.

Makes no changes. Requires kubectl (reachable cluster) and python3.

Example:
  k8s-net-debug.sh -n prod backend-svc
EOF
  exit 0
fi

for tool in kubectl python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required" >&2
    exit 1
  fi
done

KUBECTL_REQUEST_TIMEOUT="${KUBECTL_REQUEST_TIMEOUT:-10s}"
namespace=""
service=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) namespace="${2:-}"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) service="$1"; shift ;;
  esac
done

if [[ -z "$service" ]]; then
  echo "error: SERVICE name is required (see --help)" >&2
  exit 1
fi
if [[ -z "$namespace" ]]; then
  namespace="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
  namespace="${namespace:-default}"
fi

kc() { kubectl --request-timeout="${KUBECTL_REQUEST_TIMEOUT}" "$@"; }

svc_json="$(kc get service "$service" -n "$namespace" -o json 2>&1)" || {
  echo "Service '${service}' not found in namespace '${namespace}':" >&2
  echo "$svc_json" >&2
  exit 1
}

slices_json="$(kc get endpointslices -n "$namespace" -l "kubernetes.io/service-name=${service}" -o json 2>/dev/null || echo '{}')"
pods_json="$(kc get pods -n "$namespace" -o json 2>/dev/null || echo '{}')"
netpol_json="$(kc get networkpolicies -n "$namespace" -o json 2>/dev/null || echo '{}')"

svc_f="$(mktemp "${TMPDIR:-/tmp}/net-svc.XXXXXX")"
sl_f="$(mktemp "${TMPDIR:-/tmp}/net-sl.XXXXXX")"
pod_f="$(mktemp "${TMPDIR:-/tmp}/net-pod.XXXXXX")"
np_f="$(mktemp "${TMPDIR:-/tmp}/net-np.XXXXXX")"
prog="$(mktemp "${TMPDIR:-/tmp}/net-debug.XXXXXX.py")"
trap 'rm -f "$svc_f" "$sl_f" "$pod_f" "$np_f" "$prog"' EXIT

printf '%s' "$svc_json" >"$svc_f"
printf '%s' "$slices_json" >"$sl_f"
printf '%s' "$pods_json" >"$pod_f"
printf '%s' "$netpol_json" >"$np_f"

cat >"$prog" <<'PY'
import json
import sys

svc_f, sl_f, pod_f, np_f, ns = sys.argv[1:6]


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}


def items(obj):
    return obj["items"] if isinstance(obj.get("items"), list) else ([obj] if obj else [])


svc = load(svc_f)
slices = items(load(sl_f))
pods = items(load(pod_f))
netpols = items(load(np_f))

spec = svc.get("spec") or {}
selector = spec.get("selector") or {}
svc_name = (svc.get("metadata") or {}).get("name", "?")

print(f"## Service {ns}/{svc_name}")
print(f"  type:      {spec.get('type', 'ClusterIP')}")
print(f"  clusterIP: {spec.get('clusterIP', '-')}")
print(f"  selector:  {selector or '(none — endpoints managed manually or headless)'}")
print("  ports:")
for p in (spec.get("ports") or []):
    name = p.get("name", "")
    print(f"    - {name + ' ' if name else ''}{p.get('protocol','TCP')} port={p.get('port')} "
          f"-> targetPort={p.get('targetPort')}"
          + (f" nodePort={p.get('nodePort')}" if p.get('nodePort') else ""))

# Endpoints
ready = notready = 0
for sl in slices:
    for ep in (sl.get("endpoints") or []):
        cond = ep.get("conditions") or {}
        if cond.get("ready"):
            ready += 1
        else:
            notready += 1
print(f"\n## EndpointSlices: {ready} ready, {notready} not-ready endpoint(s)")
if ready == 0:
    print("  !! No Ready endpoints — clients get connection refused / no route.")
    print("     The Service selector matches no Ready pods. Compare selector to pod")
    print("     labels below, and check pod readiness (Ready=False pods are excluded).")

# Pods matching selector
print(f"\n## Pods matching selector {selector or '{}'}")
if not selector:
    print("  (no selector — skipping label match)")
else:
    matched = 0
    for pod in pods:
        labels = (pod.get("metadata") or {}).get("labels") or {}
        if all(labels.get(k) == v for k, v in selector.items()):
            matched += 1
            status = pod.get("status") or {}
            conds = {c.get("type"): c.get("status") for c in (status.get("conditions") or [])}
            pname = (pod.get("metadata") or {}).get("name", "?")
            print(f"  - {pname}: phase={status.get('phase','?')} Ready={conds.get('Ready','?')}")
    if matched == 0:
        print("  !! No pods match this selector. Either no workload is deployed, or the")
        print("     pod labels differ from spec.selector. Check `kubectl get pods --show-labels`.")

# NetworkPolicies affecting backend pods
print(f"\n## NetworkPolicies in {ns} selecting these pods")
backend_pods = []
if selector:
    for pod in pods:
        labels = (pod.get("metadata") or {}).get("labels") or {}
        if all(labels.get(k) == v for k, v in selector.items()):
            backend_pods.append(labels)


def np_selects(np_selector, pod_labels_list):
    match = np_selector.get("matchLabels") or {}
    if not match and not (np_selector.get("matchExpressions")):
        return True  # empty podSelector selects all pods in ns
    for labels in pod_labels_list:
        if match and all(labels.get(k) == v for k, v in match.items()):
            return True
    return False


affecting = []
for np in netpols:
    nspec = np.get("spec") or {}
    psel = nspec.get("podSelector") or {}
    if np_selects(psel, backend_pods):
        ptypes = nspec.get("policyTypes") or []
        affecting.append((np.get("metadata", {}).get("name", "?"), ptypes))
if affecting:
    for name, ptypes in affecting:
        print(f"  - {name}: policyTypes={ptypes or '[Ingress]'} "
              "(traffic is deny-by-default for these directions unless explicitly allowed)")
else:
    print("  (none — no NetworkPolicy restricts these pods)")

# DNS hint
print("\n## DNS / connectivity test")
print(f"  FQDN: {svc_name}.{ns}.svc.cluster.local")
ports = spec.get("ports") or []
port = ports[0].get("port") if ports else "<port>"
print(f"  From a debug pod:")
print(f"    kubectl run -it --rm dbg --image=busybox:1.36 --restart=Never -n {ns} -- \\")
print(f"      sh -c 'nslookup {svc_name}.{ns} && wget -qO- {svc_name}.{ns}:{port}'")
PY

python3 "$prog" "$svc_f" "$sl_f" "$pod_f" "$np_f" "$namespace"
