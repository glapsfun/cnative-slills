# Operations: install, IAM, spot infra, upgrades, observability, cost patterns

Self-hosted unless marked otherwise; Auto Mode outsources most of this page to AWS.

## Installation & controller placement

- Install via Helm from `oci://public.ecr.aws/karpenter/karpenter` into `kube-system`
  (current default namespace; gets API priority & flow-control protection). Chart defaults:
  2 replicas, leader election, zonal topology spread `DoNotSchedule`.
- **The controller must run on capacity Karpenter does not manage**: an EKS Fargate profile
  for its namespace, or a small dedicated managed node group (≥2 nodes for the 2 replicas).
  Reason: it cannot reschedule itself off a node it is draining.
- Two IAM roles: **node role** (instance profile: EKSWorkerNode/ECR/SSM/CNI policies,
  authorized via EKS access entry or aws-auth) and **controller role** via Pod Identity
  (MNG path) or IRSA (Fargate path — the Pod Identity agent is a DaemonSet and can't run on
  Fargate). New minor versions sometimes require new IAM permissions — check upgrade notes.
- Private/isolated VPCs: need STS + SSM (+ SQS for interruptions) VPC endpoints; there is
  no Pricing API endpoint — set `ISOLATED_VPC=true` (Helm `settings.isolatedVPC`; the old
  `AWS_ISOLATED_VPC` name is pre-v1) so pricing falls back to data baked into the binary,
  refreshed only on upgrade. No IAM endpoint → use `instanceProfile` instead of `role` on
  the NodeClass.
- Spot in a fresh account: create the service-linked role once —
  `aws iam create-service-linked-role --aws-service-name spot.amazonaws.com`
  ("name has been taken" = already exists, fine).

## Spot interruption infrastructure

- Enable native handling: Helm `--set settings.interruptionQueue=<queue>`. Karpenter
  consumes a **user-provisioned** SQS queue fed by EventBridge rules (spot interruption
  warnings, rebalance recommendations, scheduled-change health events, instance
  state-changes, status-check failures — the getting-started CloudFormation creates all of
  it). On a 2-minute spot warning Karpenter taints, drains, terminates, and starts the
  replacement immediately.
- Rebalance recommendations emit a Kubernetes event only — no proactive replacement (no
  safe default action).
- **Do not run AWS Node Termination Handler alongside Karpenter** — duplicate handling;
  NTH's rebalance-draining + Karpenter relaunching the same type = churn loop.
- Karpenter also polls `ec2:DescribeInstanceStatus` for health (needs the IAM permission;
  no SQS required for that path).

## Upgrades

Order of operations, learned the hard way by many fleets:

1. **Pin AMIs first** (`alias: al2023@vYYYYMMDD`). With `@latest`, a controller upgrade
   that changes AMI resolution or the drift hash can roll the entire fleet immediately.
2. **Tighten budgets** before the upgrade (`nodes: "0"` or a small absolute number) —
   several releases change the NodeClaim hash and mark everything Drifted on startup.
3. **Upgrade the `karpenter-crd` chart, then the `karpenter` chart, same version.** Helm
   never updates CRDs on chart upgrade; stale CRDs → strict-decoding errors. Keep both
   charts version-locked; step through minor versions, reading each release's upgrade notes
   (API moves, new IAM permissions — e.g. v1.12 added `arc-zonal-shift:GetManagedResource`
   and `ec2:DescribeInstanceStatus`, and its drift-hash change marks every existing node
   Drifted on upgrade).
4. Release budgets and let drift roll nodes at your pace.
5. EKS control-plane upgrades: with alias-without-pin selectors, Karpenter auto-discovers
   the new K8s-version AMI and drift-rolls nodes. In prod, pin → upgrade control plane →
   bump pin deliberately. Validate in non-prod with `@latest` to soak new AMIs.

Karpenter has a per-release supported K8s range (compatibility matrix on karpenter.sh) but
is not strictly coupled to K8s minor versions.

## Observability

Alert-worthy (Prometheus, self-hosted — Auto Mode has none of these; use audit-log events):

| Signal | Why |
|---|---|
| `karpenter_nodepools_usage` / `karpenter_nodepools_limit` near 1 (~80%) | Limit exhaustion is otherwise a log-only event; pods Pend silently |
| controller log `exceeds limit` pattern (CloudWatch metric filter) | Same failure, belt-and-suspenders |
| `karpenter_cluster_state_synced == 0` | Desynced state = bad decisions |
| `karpenter_cloudprovider_errors_total` rate | IAM regressions, ICE storms, throttling |
| `karpenter_pods_startup_duration_seconds` p95 | The end-to-end "pending → running" SLI |
| `karpenter_interruption_received_messages_total`, queue duration | Spot interruption volume / handling lag |
| `karpenter_voluntary_disruption_*_failures/timeouts` | Consolidation failing at scale |
| Node lifetime distribution (`karpenter_nodes_current_lifetime_seconds`) | A mass below ~15 min = churn problem (raise consolidateAfter, check unstable affinities) |

Events: `Unconsolidatable` and `DisruptionBlocked` explain stuck consolidation (they name
the blocking PDB); `FailedScheduling` with "no instance type met the scheduling
requirements" = constraints mismatch. `DisruptionBlocked` fires repeatedly for 1-replica
apps with PDBs — don't page on it raw. Tools: `eks-node-viewer` (live binpacking),
getting-started Grafana dashboards. Always set billing alarms / Cost Anomaly Detection —
autoscalers outrun budgets faster than humans notice.

## Cost patterns

- **Spot**: allow `["spot", "on-demand"]` in one pool — on spot ICE the offering is cached
  unavailable (~3 min) and on-demand fills in automatically. Allocation is
  price-capacity-optimized: diversity (categories + generations, `NotIn` excludes, optional
  `minValues` floors) is what keeps interruption rates low. Deterministic spot/OD ratios:
  the `capacity-spread` label + topologySpread pattern (see nodepools.md).
- **Graviton**: widen arch to `["amd64", "arm64"]` once images are multi-arch; Karpenter
  picks Graviton when cheaper, automatically. Watch the "instance selection paradox":
  cheapest-first can choose older generations (m5a over m6a) and inflate replica counts —
  counter with `instance-generation Gt N` or generation-weighted pools.
- **RIs/Savings Plans**: weighted pool (`weight: 50`) sized to the commitment via `limits`,
  unweighted overflow pool behind it. **ODCRs**: native — `capacityReservationSelectorTerms`
  with capacity-type `reserved`; Karpenter fills reservations first and consolidates onto
  them (see ec2nodeclass.md).
- **Overprovisioning / headroom**: Deployment of `pause` pods with real requests and a
  negative-value PriorityClass (`value: -1000`, `globalDefault: false`). Real pods preempt
  placeholders in seconds; evicted placeholders go Pending and pull up the next node. Size
  placeholders to ~70–75% of a target node (≈1 spare node per replica) or mirror N replicas
  of the protected workload. Standing cost; consider scaling the placeholder Deployment
  down off-peak. Upstream is landing a native alternative — the SIG-Autoscaling
  `CapacityBuffer` API (`autoscaling.x-k8s.io/v1alpha1`, alpha gate, post-v1.13/expected
  v1.14): headroom via virtual pods sized by replicas/percentage against a scalableRef or
  podTemplateRef. Check the user's version before recommending it.
- **NodeOverlay** (`karpenter.sh/v1alpha1`, alpha gate since v1.7, off by default):
  requirement-matched overrides of instance-type `price` / `priceAdjustment` (absolute or
  `-10%`-style — model negotiated discounts so consolidation math matches your bill) and
  additive extended-resource `capacity` (hugepages, device resources); conflicts merge by
  `weight`. Feeds both provisioning and consolidation decisions.
- **CoreDNS on churning nodes**: tune lameduck duration + readiness probe, or DNS queries
  hit terminating pods during consolidation waves.
