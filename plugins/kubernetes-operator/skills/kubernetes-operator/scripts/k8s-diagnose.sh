#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: k8s-diagnose.sh [-n NAMESPACE | -A] [--no-logs] [POD]

Read-only triage that walks the SKILL.md debugging playbooks top-down for
unhealthy pods: classifies the failure (Pending, CrashLoopBackOff,
ImagePullBackOff, CreateContainerConfigError, OOMKilled, stuck Terminating,
NotReady), prints the recommended next step, then shows the pod's recent events
and the previous container logs for crash-looping containers.

With no POD, scans the namespace for problem pods. With a POD name, always
reports on that pod even if healthy. Makes no changes to the cluster.

Options:
  -n NAMESPACE   namespace to inspect (default: current context namespace)
  -A             scan all namespaces
  --no-logs      skip 'describe' events and 'logs --previous' (summary only)

Requires kubectl (with a reachable cluster) and python3.

Examples:
  k8s-diagnose.sh -n prod
  k8s-diagnose.sh -n prod payments-api-6d9f7c4b8-x2k9p
  k8s-diagnose.sh -A --no-logs
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
all_ns=0
no_logs=0
pod=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) namespace="${2:-}"; shift 2 ;;
    -A|--all-namespaces) all_ns=1; shift ;;
    --no-logs) no_logs=1; shift ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) pod="$1"; shift ;;
  esac
done

scope=(--request-timeout="${KUBECTL_REQUEST_TIMEOUT}")
if [[ "$all_ns" -eq 1 ]]; then
  scope+=(--all-namespaces)
elif [[ -n "$namespace" ]]; then
  scope+=(-n "$namespace")
fi

get_args=(get pods "${scope[@]}" -o json)
if [[ -n "$pod" && "$all_ns" -eq 0 ]]; then
  get_args=(get pod "$pod" "${scope[@]}" -o json)
fi

if ! pods_json="$(kubectl "${get_args[@]}" 2>&1)"; then
  echo "kubectl failed: $pods_json" >&2
  exit 1
fi

prog="$(mktemp "${TMPDIR:-/tmp}/k8s-diagnose.XXXXXX.py")"
worklist="$(mktemp "${TMPDIR:-/tmp}/k8s-diagnose-work.XXXXXX")"
trap 'rm -f "$prog" "$worklist"' EXIT

cat >"$prog" <<'PY'
import json
import sys

worklist_path = sys.argv[1]
want_pod = sys.argv[2] if len(sys.argv) > 2 else ""

data = json.load(sys.stdin)
# kubectl returns kind "PodList" or a generic "List" depending on version; a
# single `get pod NAME` returns one Pod object. Detect by the "items" key.
items = data["items"] if isinstance(data.get("items"), list) else [data]

HINTS = {
    "Pending": "Not scheduled. `kubectl describe pod` events show the failed filter: insufficient CPU/mem (check requests + `kubectl top nodes`), unsatisfiable nodeSelector/affinity, untolerated taints, or an unbound PVC (`kubectl get pvc`).",
    "CrashLoopBackOff": "Container starts then dies. Read `logs --previous` (below); check exit code in Last State (137=OOM/SIGKILL, 1/2=app error, 126/127=bad command). Rule out a liveness probe killing a slow-but-healthy app.",
    "ImagePullBackOff": "Registry/image problem. The describe event has the verbatim error: typo'd image/tag, missing imagePullSecrets for a private registry, or wrong architecture.",
    "ErrImagePull": "Registry/image problem. The describe event has the verbatim error: typo'd image/tag, missing imagePullSecrets for a private registry, or wrong architecture.",
    "CreateContainerConfigError": "A referenced ConfigMap/Secret key is missing or malformed. `kubectl describe pod` names the missing key.",
    "CreateContainerError": "Container could not be created (bad command, mount, or runtime error). See describe events.",
    "OOMKilled": "Memory exceeded the limit and the container was killed. Raise the memory limit or reduce usage; compare `kubectl top pod --containers` to limits.",
    "Terminating": "Stuck deleting — a finalizer isn't being cleared. Check `kubectl get pod -o jsonpath='{.metadata.finalizers}'` and the controller responsible. Force-removing finalizers can orphan external resources.",
    "Unschedulable": "Scheduler rejected the pod (see Pending hint).",
}

problems = []  # (ns, name, summary_lines, prevlog_container)


def container_states(status):
    out = []
    crash_container = None
    oom_seen = False
    for cs in (status.get("containerStatuses") or []):
        cname = cs.get("name", "?")
        ready = cs.get("ready", False)
        restarts = cs.get("restartCount", 0)
        state = cs.get("state") or {}
        last = cs.get("lastState") or {}
        reason = None
        detail = ""
        if "waiting" in state:
            reason = state["waiting"].get("reason")
            detail = state["waiting"].get("message", "") or ""
        elif "terminated" in state:
            t = state["terminated"]
            reason = t.get("reason")
            detail = f"exit {t.get('exitCode')}"
        lt = (last.get("terminated") or {})
        if lt:
            detail = (detail + f"; last exit {lt.get('exitCode')} ({lt.get('reason')})").strip("; ")
            if lt.get("reason") == "OOMKilled":
                reason = reason or "OOMKilled"
                oom_seen = True
        line = f"    container {cname}: ready={ready} restarts={restarts}"
        if reason:
            line += f" reason={reason}"
        if detail:
            line += f" [{detail}]"
        out.append((line, reason, cname, ready))
        if reason in ("CrashLoopBackOff",) or (lt and lt.get("exitCode", 0) != 0):
            crash_container = cname
    return out, crash_container, oom_seen


def classify(pod):
    meta = pod.get("metadata") or {}
    status = pod.get("status") or {}
    phase = status.get("phase", "?")
    name = meta.get("name", "?")
    ns = meta.get("namespace", "?")

    healthy = False
    if phase == "Succeeded":
        healthy = True
    if phase == "Running":
        conds = {c.get("type"): c.get("status") for c in (status.get("conditions") or [])}
        if conds.get("Ready") == "True":
            healthy = True

    if meta.get("deletionTimestamp"):
        healthy = False

    if want_pod and name != want_pod:
        return None
    if healthy and not want_pod:
        return None

    node = (pod.get("spec") or {}).get("nodeName") or "-"
    lines = [f"POD {ns}/{name}  phase={phase}  node={node}"]
    triggers = []

    if meta.get("deletionTimestamp"):
        triggers.append("Terminating")
        fins = meta.get("finalizers") or []
        lines.append(f"    deletionTimestamp set; finalizers={fins}")

    cstates, crash_container, oom_seen = container_states(status)
    lines.extend(l[0] for l in cstates)
    container_reasons = {reason for _, reason, _, _ in cstates if reason in HINTS}
    triggers.extend(container_reasons)
    if oom_seen:
        triggers.append("OOMKilled")

    # Generic Pending hint only when no more specific container reason explains it.
    if phase == "Pending" and not container_reasons:
        triggers.append("Pending")

    # Unschedulable shows up as a PodScheduled=False condition.
    for c in (status.get("conditions") or []):
        if c.get("type") == "PodScheduled" and c.get("status") == "False":
            triggers.append("Unschedulable")
            if c.get("message"):
                lines.append(f"    scheduler: {c.get('message')}")

    if healthy:
        lines.append("    (currently healthy — reported because you named it explicitly)")

    seen = set()
    for t in triggers:
        if t in seen:
            continue
        seen.add(t)
        lines.append(f"    -> {t}: {HINTS[t]}")

    return ns, name, lines, crash_container


for pod in items:
    res = classify(pod)
    if res is None:
        continue
    ns, name, lines, crash_container = res
    problems.append((ns, name, crash_container))
    print("\n".join(lines))
    print()

with open(worklist_path, "w", encoding="utf-8") as f:
    for ns, name, crash in problems:
        f.write(f"{ns}\t{name}\t{crash or ''}\n")

if not problems:
    print("No unhealthy pods found in scope.")
PY

printf '%s' "$pods_json" | python3 "$prog" "$worklist" "$pod"

if [[ "$no_logs" -eq 1 ]]; then
  exit 0
fi

# Second pass: show events and previous logs for each problem pod.
while IFS=$'\t' read -r ns name crash; do
  [[ -z "$name" ]] && continue
  printf '\n========== %s/%s ==========\n' "$ns" "$name"
  printf -- '--- recent events ---\n'
  kubectl describe pod "$name" -n "$ns" --request-timeout="${KUBECTL_REQUEST_TIMEOUT}" 2>/dev/null \
    | awk '/^Events:/{flag=1} flag' | tail -n 20 || echo "(events unavailable)"
  if [[ -n "$crash" ]]; then
    printf -- '--- previous logs: %s (last 20 lines) ---\n' "$crash"
    kubectl logs "$name" -c "$crash" -n "$ns" --previous --tail=20 \
      --request-timeout="${KUBECTL_REQUEST_TIMEOUT}" 2>&1 || echo "(no previous logs)"
  fi
done <"$worklist"
