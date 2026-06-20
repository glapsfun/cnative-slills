#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: k8s-manifest-lint.sh [--strict] [FILE ...]

Offline static review of Kubernetes manifests against the SKILL.md "Writing
manifests" checklist. Reads the given YAML files (multi-document supported), or
stdin when no file is given. No cluster access required.

Flags each workload (Deployment, StatefulSet, DaemonSet, ReplicaSet, Job,
CronJob, Pod) for:
  - deprecated/removed apiVersion
  - :latest or untagged images
  - missing resource requests / memory limit
  - missing readiness probe
  - weak pod/container securityContext (root, privilege escalation, caps,
    privileged, host namespaces)
  - default ServiceAccount / token automount
  - plaintext secrets in env

Exit status: 0 when clean (warnings allowed), 2 when any ERROR is found.
With --strict, warnings also cause exit 2. Requires python3 with PyYAML.

Examples:
  k8s-manifest-lint.sh deploy.yaml
  helm template ./chart | k8s-manifest-lint.sh
  kubectl get deploy api -n prod -o yaml | k8s-manifest-lint.sh --strict
EOF
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for manifest linting" >&2
  exit 1
fi

strict=0
files=()
for arg in "$@"; do
  case "$arg" in
    --strict) strict=1 ;;
    *) files+=("$arg") ;;
  esac
done

# Write the linter to a temp file so the script's stdin stays free for piped manifests.
prog="$(mktemp "${TMPDIR:-/tmp}/k8s-manifest-lint.XXXXXX.py")"
trap 'rm -f "$prog"' EXIT

cat >"$prog" <<'PY'
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML is required (pip install pyyaml)\n")
    sys.exit(1)

strict = sys.argv[1] == "1"
paths = sys.argv[2:]

# (apiVersion, kind) -> replacement note. kind None means any kind in that group.
DEPRECATED = {
    ("extensions/v1beta1", None): "removed in 1.16; use apps/v1, networking.k8s.io/v1, or policy/v1",
    ("apps/v1beta1", None): "removed in 1.16; use apps/v1",
    ("apps/v1beta2", None): "removed in 1.16; use apps/v1",
    ("networking.k8s.io/v1beta1", "Ingress"): "removed in 1.22; use networking.k8s.io/v1",
    ("policy/v1beta1", "PodDisruptionBudget"): "removed in 1.25; use policy/v1",
    ("policy/v1beta1", "PodSecurityPolicy"): "removed in 1.25; PSP is gone, use Pod Security Admission",
    ("batch/v1beta1", "CronJob"): "removed in 1.25; use batch/v1",
    ("rbac.authorization.k8s.io/v1beta1", None): "removed in 1.22; use rbac.authorization.k8s.io/v1",
    ("autoscaling/v2beta1", None): "removed in 1.25; use autoscaling/v2",
    ("autoscaling/v2beta2", None): "removed in 1.26; use autoscaling/v2",
}

WORKLOAD_KINDS = {
    "Deployment", "StatefulSet", "DaemonSet", "ReplicaSet",
    "Job", "CronJob", "Pod", "ReplicationController",
}

SECRETISH = ("PASSWORD", "PASSWD", "SECRET", "TOKEN", "APIKEY", "API_KEY",
             "PRIVATE_KEY", "ACCESS_KEY")

findings = []  # (level, where, message)


def add(level, where, msg):
    findings.append((level, where, msg))


def pod_spec_of(doc):
    """Return (pod_spec, where_suffix) for a workload doc, or (None, None)."""
    kind = doc.get("kind")
    spec = doc.get("spec") or {}
    if kind == "Pod":
        return spec, ""
    if kind == "CronJob":
        tmpl = (((spec.get("jobTemplate") or {}).get("spec") or {})
                .get("template") or {})
        return tmpl.get("spec"), " (jobTemplate)"
    tmpl = (spec.get("template") or {})
    return tmpl.get("spec"), ""


def check_container(c, where, host_level, pod_nonroot):
    name = c.get("name", "?")
    img = c.get("image", "")
    if not img:
        add("ERROR", where, f"container '{name}': no image set")
    elif ":" not in img.rsplit("/", 1)[-1]:
        add("WARN", where, f"container '{name}': image '{img}' has no tag (implies :latest)")
    elif img.rsplit(":", 1)[-1] == "latest":
        add("WARN", where, f"container '{name}': image pinned to :latest — rollbacks are nondeterministic")

    res = c.get("resources") or {}
    requests = res.get("requests") or {}
    limits = res.get("limits") or {}
    if "cpu" not in requests and "memory" not in requests:
        add("WARN", where, f"container '{name}': no resource requests (scheduling + QoS rely on them)")
    if "memory" not in limits:
        add("WARN", where, f"container '{name}': no memory limit (no OOM protection)")

    # Probes only meaningful for long-running containers, skip for Job-ish handled by caller.
    if host_level != "job" and not c.get("readinessProbe"):
        add("WARN", where, f"container '{name}': no readinessProbe (traffic not gated on readiness)")

    sc = c.get("securityContext") or {}
    if not pod_nonroot and sc.get("runAsNonRoot") is not True:
        add("WARN", where, f"container '{name}': runAsNonRoot not true at pod or container level (required for 'restricted' Pod Security)")
    if sc.get("privileged") is True:
        add("ERROR", where, f"container '{name}': privileged: true")
    if sc.get("allowPrivilegeEscalation") is not False:
        add("WARN", where, f"container '{name}': allowPrivilegeEscalation not set to false")
    if sc.get("runAsUser") == 0:
        add("ERROR", where, f"container '{name}': runAsUser: 0 (root)")
    caps = (sc.get("capabilities") or {})
    drop = [str(x).upper() for x in (caps.get("drop") or [])]
    if "ALL" not in drop:
        add("WARN", where, f"container '{name}': capabilities.drop does not include ALL")
    addc = [str(x).upper() for x in (caps.get("add") or [])]
    for danger in ("SYS_ADMIN", "NET_ADMIN", "ALL"):
        if danger in addc:
            add("ERROR", where, f"container '{name}': adds dangerous capability {danger}")

    for e in (c.get("env") or []):
        ename = str(e.get("name", "")).upper()
        if "value" in e and e.get("value") and any(s in ename for s in SECRETISH):
            add("ERROR", where, f"container '{name}': env '{e.get('name')}' has a plaintext value — use a Secret + valueFrom.secretKeyRef")


def check_doc(doc, idx):
    if not isinstance(doc, dict):
        return
    api = doc.get("apiVersion", "")
    kind = doc.get("kind", "")
    where = f"{kind or '?'} {((doc.get('metadata') or {}).get('name')) or f'#{idx}'}"

    for (dep_api, dep_kind), note in DEPRECATED.items():
        if api == dep_api and (dep_kind is None or dep_kind == kind):
            add("ERROR", where, f"apiVersion {api} is deprecated/removed — {note}")

    if kind not in WORKLOAD_KINDS:
        return

    pod_spec, suffix = pod_spec_of(doc)
    if not isinstance(pod_spec, dict):
        add("WARN", where, "could not locate pod template spec")
        return
    where = where + suffix

    host_level = "job" if kind in ("Job", "CronJob") else "service"

    psc = pod_spec.get("securityContext") or {}
    pod_nonroot = psc.get("runAsNonRoot") is True
    for host_ns in ("hostNetwork", "hostPID", "hostIPC"):
        if pod_spec.get(host_ns) is True:
            add("ERROR", where, f"{host_ns}: true breaks pod isolation")

    sa = pod_spec.get("serviceAccountName") or pod_spec.get("serviceAccount")
    if not sa or sa == "default":
        add("WARN", where, "uses the namespace 'default' ServiceAccount — give the app a dedicated SA")
    if pod_spec.get("automountServiceAccountToken") is None:
        add("WARN", where, "automountServiceAccountToken not set (default true mounts an API token; set false if unused)")

    containers = pod_spec.get("containers") or []
    if not containers:
        add("ERROR", where, "no containers defined")
    for c in containers:
        check_container(c, where, host_level, pod_nonroot)
    for c in (pod_spec.get("initContainers") or []):
        check_container(c, where + "/init", host_level, pod_nonroot)


def main():
    docs = []
    try:
        if paths:
            for p in paths:
                with open(p, "r", encoding="utf-8") as f:
                    for d in yaml.safe_load_all(f):
                        docs.append((p, d))
        else:
            for d in yaml.safe_load_all(sys.stdin):
                docs.append(("<stdin>", d))
    except yaml.YAMLError as exc:
        sys.stderr.write(f"YAML parse error: {exc}\n")
        sys.exit(1)
    except OSError as exc:
        sys.stderr.write(f"{exc}\n")
        sys.exit(1)

    idx = 0
    workloads = 0
    for src, doc in docs:
        if doc is None:
            continue
        idx += 1
        if isinstance(doc, dict) and doc.get("kind") in WORKLOAD_KINDS:
            workloads += 1
        check_doc(doc, idx)

    if not findings:
        print(f"OK — {idx} document(s), {workloads} workload(s), no issues found.")
        sys.exit(0)

    errors = sum(1 for lvl, _, _ in findings if lvl == "ERROR")
    warns = sum(1 for lvl, _, _ in findings if lvl == "WARN")
    order = {"ERROR": 0, "WARN": 1}
    for lvl, where, msg in sorted(findings, key=lambda f: (order[f[0]], f[1])):
        print(f"{lvl:5} [{where}] {msg}")
    print(f"\n{errors} error(s), {warns} warning(s) across {idx} document(s).")

    if errors > 0 or (strict and warns > 0):
        sys.exit(2)
    sys.exit(0)


main()
PY

# "${files[@]+...}" guards against an empty array under `set -u` on bash 3.2 (macOS).
python3 "$prog" "$strict" ${files[@]+"${files[@]}"}
