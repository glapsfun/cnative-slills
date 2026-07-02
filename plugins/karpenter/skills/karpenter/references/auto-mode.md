# EKS Auto Mode (built-in Karpenter)

Auto Mode is AWS-managed Karpenter plus managed networking/LB/storage/GPU plumbing. The
Karpenter controller runs inside the AWS-managed control plane — **no controller pods, no
controller logs, no Karpenter Prometheus metrics**. Nodes are EC2 "managed instances" on
AWS-owned Bottlerocket AMIs: immutable, SELinux enforcing, no SSH/SSM, IMDSv2 with hop
limit 1 (fixed), AMI chosen by AWS with ~weekly releases that drift-replace nodes.
Pricing: a per-instance management fee (~12% of on-demand price for common types; AWS does
not publish the percentage) on top of EC2 — charged at the on-demand-based rate regardless
of purchase option, so proportionally heavier on spot and not reduced by RIs/Savings Plans.

NodePools remain `karpenter.sh/v1` (same disruption/limits/weight semantics — see
[nodepools.md](nodepools.md) and [disruption.md](disruption.md)), but:

- `nodeClassRef` must be `{group: eks.amazonaws.com, kind: NodeClass}`.
- Instance labels use the **`eks.amazonaws.com/` namespace** — `karpenter.k8s.aws/*` labels
  match nothing on Auto Mode.
- `kubernetes.io/os` is unsupported (Linux only).
- `expireAfter`: default 336h, **hard cap 504h (21 days)** — nodes are force-recycled; plan
  PDBs accordingly. `terminationGracePeriod` defaults to 24h (materialized on NodeClaims).
- Pod density: `min(standard max-pods calculation, 110)` per node, not tunable (pod-subnet
  separation reduces it further — the primary ENI is reserved for the node IP).

## Built-in NodePools (`system`, `general-purpose`)

Enable/disable only — never editable. Both: on-demand, C/M/R families, generation ≥5, the
built-in `default` NodeClass. `system` carries a `CriticalAddonsOnly` taint (amd64+arm64);
`general-purpose` is amd64-only. Disable built-ins when you need spot, Graviton for general
workloads, custom storage/networking, or per-team isolation — then create custom pools.
Never name a custom NodeClass `default` (collides with the auto-provisioned one — which
exists only while at least one built-in pool is enabled; disable both built-ins and there is
no `default` NodeClass to reference). Removing a built-in pool from the cluster's
`computeConfig` deletes the NodePool and drains/terminates its nodes; re-adding recreates it.
Custom NodeClasses with their own `role` need an EKS access entry of type `EC2` with the
`AmazonEKSAutoNodePolicy` cluster access policy (auto-created only for built-ins).

Migrating from self-hosted Karpenter (AWS's recommended order, requires Karpenter ≥ v1.1):
enable Auto Mode **without** `general-purpose` (it is unselective and will grab pending
pods) → create a tainted custom Auto Mode NodePool → add the toleration +
`nodeSelector: {eks.amazonaws.com/compute-type: auto}` to workloads → migrate gradually →
delete the old Karpenter NodePools → uninstall Karpenter. The `nodepools.karpenter.sh` /
`nodeclaims.karpenter.sh` CRDs are **shared** between the two systems — do not modify or
delete them mid-migration.

## Auto Mode NodeClass (`eks.amazonaws.com/v1`, kind `NodeClass`)

```yaml
apiVersion: eks.amazonaws.com/v1
kind: NodeClass
metadata:
  name: workload
spec:
  role: eks-auto-node-my-cluster        # or instanceProfile (mutually exclusive)
  subnetSelectorTerms:
    - tags: {Tier: private}             # or id: subnet-...
  securityGroupSelectorTerms:
    - tags: {"aws:eks:cluster-name": my-cluster}   # or id / name
  ephemeralStorage:                     # replaces blockDeviceMappings
    size: 100Gi                         # default 80Gi
    iops: 3000                          # default 3000 (3000-16000)
    throughput: 125                     # default 125 (125-1000)
    # kmsKeyID: arn:aws:kms:...         # custom encryption key
  snatPolicy: Random                    # Random | Disabled (Disabled = your NAT handles egress)
  networkPolicy: DefaultAllow           # DefaultAllow | DefaultDeny
  networkPolicyEventLogs: Disabled      # Enabled for NP decision logs
  tags:
    Environment: production
```

Optional blocks: `podSubnetSelectorTerms` + `podSecurityGroupSelectorTerms` (separate pod
networking — both together; Security Groups for Pods is NOT supported on Auto Mode),
`capacityReservationSelectorTerms` (ODCRs/Capacity Blocks), `advancedNetworking`
(`associatePublicIPAddress`, `httpsProxy`/`noProxy`, `ipv4PrefixSize`, `enableV4Egress`),
`advancedSecurity.fips`, `certificateBundles`, `placementGroupSelector`.

**Not available vs self-hosted EC2NodeClass** (catch these in reviews — they signal
copy-paste from self-hosted docs): `amiFamily`/`amiSelectorTerms`, `userData`,
`blockDeviceMappings`, `metadataOptions`, `kubelet` config, `instanceStorePolicy`,
`detailedMonitoring`. The only sanctioned node-customization path is DaemonSets.

NVMe behavior: if `ephemeralStorage.size` < instance local NVMe, the NVMe is formatted
(RAID0 if multiple) for ephemeral use; if ≥, NVMe is exposed directly.

## Supported requirement labels

`topology.kubernetes.io/zone`, `node.kubernetes.io/instance-type`, `kubernetes.io/arch`,
`karpenter.sh/capacity-type` (spot|on-demand|reserved), and:
`eks.amazonaws.com/instance-category`, `-family`, `-generation`, `-size`, `-cpu`,
`-cpu-manufacturer`, `-memory` (MiB), `-ebs-bandwidth`, `-network-bandwidth`,
`-gpu-name` (t4/l40s/a100/...), `-gpu-manufacturer`, `-gpu-count`, `-gpu-memory` (MiB),
`-local-nvme` (GiB), `-instance-hypervisor`, `-encryption-in-transit-supported`, and
`capacity-reservation-interruptible` (newer; present only on `reserved` nodes).
Auto Mode nodes also carry `eks.amazonaws.com/compute-type: auto` — the selector for
requiring (or excluding, via `NotIn`) Auto Mode nodes in mixed clusters.

Instance universe: broad C/M/R/T/I/X/Z (now through the c8/m8/r8 generations, plus hpc8a)
and accelerated (p3→p6-b300, g4→g7e, inf1/2, trn1/2) — but only types with >1 vCPU and
size above `small`.

## GPU / accelerated pools

NVIDIA and Neuron drivers + device plugins are **bundled in the AMI** (invisible — do not
install the NVIDIA device plugin or GPU Operator's plugin for these nodes; in mixed
clusters, configure self-managed plugins to exclude Auto Mode nodes).

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata: {name: gpu}
spec:
  disruption:
    consolidationPolicy: WhenEmpty   # scale-to-zero; tune consolidateAfter to spikiness
    consolidateAfter: 5m             # short = fast cost cutoff; ~1h for spiky retrain jobs
  template:
    spec:
      nodeClassRef: {group: eks.amazonaws.com, kind: NodeClass, name: default}
      requirements:
        - {key: eks.amazonaws.com/instance-family, operator: In, values: [g6e, g6]}
        - {key: karpenter.sh/capacity-type, operator: In, values: [on-demand]}
        - {key: kubernetes.io/arch, operator: In, values: [amd64]}
      taints:
        - {key: nvidia.com/gpu, effect: NoSchedule}
  limits:
    cpu: "512"
```

Workloads then need all three: a toleration for the taint, targeting (nodeSelector on a pool
label or the taint-implied isolation), and `resources.limits["nvidia.com/gpu"]` so the GPU
is actually allocated. Target specific GPUs with `instance-gpu-name`/`-gpu-memory` rather
than memorizing family names.

## Static capacity

`spec.replicas` on a NodePool is GA-equivalent on Auto Mode (same one-way-door semantics as
upstream — see [nodepools.md](nodepools.md)).

## Troubleshooting without controller logs

- **Karpenter's decisions**: enable control-plane logging, then query kube-apiserver audit
  logs in CloudWatch Logs Insights for event reasons: `DisruptionBlocked`,
  `Unconsolidatable`, `FailedScheduling`, `NoCompatibleInstanceTypes`,
  `InsufficientCapacityError`, `DisruptionTerminating`, `FailedDraining`, etc.
- **Provisioning failures**: `kubectl get nodeclaim` / `kubectl describe nodeclaim`.
  `Error getting launch template configs` usually = custom NodeClass tags without the extra
  IAM permissions; `Error creating fleet` = RunInstances auth (check CloudTrail for
  AccessDenied/UnauthorizedOperation).
- **Node-level**: node monitoring agent events/conditions are built in; `NodeDiagnostic` CR
  bundles node logs to S3 (and can capture tcpdump network traces); `kubectl debug node/<n>
  --profile=sysadmin` + `nsenter -t 1 -m journalctl -u kubelet` for live kubelet logs;
  `aws ec2 get-console-output` for boot issues.
- Pods not landing on Auto nodes in mixed clusters: nodeSelector probably uses
  `karpenter.k8s.aws/*` labels — switch to `eks.amazonaws.com/*` / `compute-type: auto`.
- Since April 2026, managed instances are hidden from EC2 list APIs/console by default
  (toggle "Managed resource visibility" in EC2 account attributes); they remain visible via
  EKS console and `kubectl get nodes`, and remain billable.
- SELinux MCS labels isolate pods: sharing an RWO volume across pods needs identical
  `securityContext.seLinuxOptions.level` values with **three** categories (e.g.
  `s0:c123,c456,c789` — auto-assigned pods get two, so three avoids collisions).
- Pods needing IMDS access require `hostNetwork: true` (hop limit is fixed at 1); prefer
  Pod Identity/IRSA.

## When Auto Mode is the wrong tool

Custom AMIs/golden images, userData/bootstrap or kernel-level host changes, kubelet tuning
(>110 pods, reserved resources), Windows, nodes living >21 days, IMDS for pods, controller
observability/tuning, or fee-sensitive very large fleets → self-hosted Karpenter. Both can
coexist during migration: partition workloads per pool and use `eks.amazonaws.com/compute-type`
selectors; AWS recommends not running both long-term.
