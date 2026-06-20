#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: k8s-rbac-check.sh [-n NAMESPACE] [SERVICEACCOUNT]

Read-only RBAC audit.

With a SERVICEACCOUNT, reports that account's effective permissions
(kubectl auth can-i --list, impersonating the SA), checks a set of high-risk
verbs, and lists the Role/ClusterRole bindings that grant to it — the fast path
for "Forbidden" errors and for spotting over-permissioned workloads.

With no SERVICEACCOUNT, scans the cluster for risky bindings: subjects bound to
cluster-admin and RoleBindings/ClusterRoleBindings whose roleRef name suggests
broad access.

Impersonation (auth can-i --as) requires the caller to hold the 'impersonate'
verb; if denied, the binding-based report still works. Makes no changes.

Options:
  -n NAMESPACE   namespace of the ServiceAccount (default: current context ns)

Requires kubectl (reachable cluster) and python3.

Examples:
  k8s-rbac-check.sh -n prod reporting
  k8s-rbac-check.sh                 # cluster-wide risky-binding scan
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
sa=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) namespace="${2:-}"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) sa="$1"; shift ;;
  esac
done

if [[ -z "$namespace" ]]; then
  namespace="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
  namespace="${namespace:-default}"
fi

kc() { kubectl --request-timeout="${KUBECTL_REQUEST_TIMEOUT}" "$@"; }

prog="$(mktemp "${TMPDIR:-/tmp}/k8s-rbac.XXXXXX.py")"
trap 'rm -f "$prog"' EXIT

# Python helper: given subject filter on stdin JSON of (cluster)rolebindings,
# print bindings matching the subject, or risky bindings if no subject given.
cat >"$prog" <<'PY'
import json
import sys

mode = sys.argv[1]            # "subject" or "risky"
want_ns = sys.argv[2] if len(sys.argv) > 2 else ""
want_sa = sys.argv[3] if len(sys.argv) > 3 else ""

RISKY_ROLE_HINTS = ("cluster-admin", "admin", "edit")

data = json.load(sys.stdin)
items = data["items"] if isinstance(data.get("items"), list) else [data]

rows = []
for b in items:
    kind = b.get("kind", "")
    meta = b.get("metadata") or {}
    name = meta.get("name", "?")
    ns = meta.get("namespace", "")
    ref = b.get("roleRef") or {}
    ref_str = f"{ref.get('kind','?')}/{ref.get('name','?')}"
    subjects = b.get("subjects") or []

    if mode == "subject":
        for s in subjects:
            if (s.get("kind") == "ServiceAccount"
                    and s.get("name") == want_sa
                    and (s.get("namespace", ns) == want_ns)):
                where = f"{kind} {ns + '/' if ns else ''}{name}"
                rows.append(f"  {where}  ->  {ref_str}")
    else:  # risky
        ref_name = ref.get("name", "").lower()
        if any(h == ref_name for h in RISKY_ROLE_HINTS):
            subj_str = ", ".join(
                f"{s.get('kind')}:{(s.get('namespace','') + '/') if s.get('namespace') else ''}{s.get('name')}"
                for s in subjects
            ) or "(no subjects)"
            where = f"{kind} {ns + '/' if ns else ''}{name}"
            rows.append(f"  {where}  ->  {ref_str}\n      subjects: {subj_str}")

for r in rows:
    print(r)
if not rows:
    print("  (none)")
PY

if [[ -n "$sa" ]]; then
  full="system:serviceaccount:${namespace}:${sa}"
  echo "## ServiceAccount ${namespace}/${sa}"

  if ! kc get serviceaccount "$sa" -n "$namespace" >/dev/null 2>&1; then
    echo "WARNING: ServiceAccount '${sa}' not found in namespace '${namespace}'."
  fi

  echo
  echo "### Effective permissions in namespace '${namespace}' (auth can-i --list)"
  if ! kc auth can-i --list --as="$full" -n "$namespace" 2>/dev/null; then
    echo "(could not impersonate — caller lacks 'impersonate' verb; skipping)"
  fi

  echo
  echo "### High-risk verb checks"
  checks=(
    "'*':'*' (full admin)|*|*"
    "create pods|create|pods"
    "get secrets|get|secrets"
    "create secrets|create|secrets"
    "delete namespaces|delete|namespaces"
    "impersonate users|impersonate|users"
    "escalate roles (rbac)|escalate|roles.rbac.authorization.k8s.io"
    "bind roles (rbac)|bind|roles.rbac.authorization.k8s.io"
  )
  for entry in "${checks[@]}"; do
    label="${entry%%|*}"; rest="${entry#*|}"
    verb="${rest%%|*}"; res="${rest#*|}"
    ans="$(kc auth can-i "$verb" "$res" --as="$full" -n "$namespace" 2>/dev/null || echo "?")"
    printf '  %-28s %s\n' "$label:" "$ans"
  done

  echo
  echo "### Namespaced RoleBindings granting to this SA (ns ${namespace})"
  kc get rolebindings -n "$namespace" -o json 2>/dev/null \
    | python3 "$prog" subject "$namespace" "$sa" || echo "  (unavailable)"

  echo
  echo "### ClusterRoleBindings granting to this SA"
  kc get clusterrolebindings -o json 2>/dev/null \
    | python3 "$prog" subject "$namespace" "$sa" || echo "  (unavailable)"
else
  echo "## Cluster-wide risky binding scan (roleRef in: cluster-admin, admin, edit)"
  echo
  echo "### ClusterRoleBindings"
  kc get clusterrolebindings -o json 2>/dev/null \
    | python3 "$prog" risky || echo "  (unavailable)"
  echo
  echo "### RoleBindings (all namespaces)"
  kc get rolebindings --all-namespaces -o json 2>/dev/null \
    | python3 "$prog" risky || echo "  (unavailable)"
  echo
  echo "Tip: re-run with a ServiceAccount name to audit one workload's effective access."
fi
