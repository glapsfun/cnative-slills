# EC2NodeClass reference (`karpenter.k8s.aws/v1`, self-hosted only)

EC2NodeClass holds the AWS-specific half of node config. Many fields carry security or
drift consequences — defaults are deliberately safe; deviate only with a reason. On EKS Auto
Mode none of this applies — see [auto-mode.md](auto-mode.md).

## Production baseline

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@v20250601        # PIN in prod; @latest = auto-upgrade + fleet-wide drift
  role: KarpenterNodeRole-my-cluster # Karpenter creates/manages the instance profile
  subnetSelectorTerms:
    - tags: {karpenter.sh/discovery: my-cluster}
  securityGroupSelectorTerms:
    - tags: {karpenter.sh/discovery: my-cluster}
  metadataOptions:                   # these ARE the defaults — shown for review visibility
    httpEndpoint: enabled
    httpTokens: required             # IMDSv2 only
    httpPutResponseHopLimit: 1       # pods cannot reach IMDS -> can't steal node creds
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs: {volumeSize: 100Gi, volumeType: gp3, encrypted: true}
  tags:
    team: platform
```

## Field notes (what matters and why)

**`amiSelectorTerms` (required since v1).** Terms are ORed; fields within a term are ANDed.
Forms: `alias: <family>@<version>` (al2023/bottlerocket/windows2019|2022|2025;
`@v20250601` pins, `@latest` floats), `tags`, `name` (+`owner`, default `self,amazon` —
owner scoping exists to prevent AMI impersonation; never select by bare name across all
accounts), `id`, `ssmParameter`. Multiple matches → newest wins. A new AMI matching the
selector **drifts every out-of-date node** — that's the whole fleet rolling on AWS's release
schedule if you float `@latest` in prod. Deprecated AMIs surface in `status.amis[].deprecated`
and the `AMIsDeprecated` condition. AL2 is EOL for newer K8s — default to AL2023.
`amiFamily` only controls userData generation + default block devices when using non-alias
selectors; `Custom` means you own bootstrap entirely.

**`role` vs `instanceProfile`** — exactly one. `role`: Karpenter creates the instance
profile (controller needs IAM perms). `instanceProfile`: user-managed; required in private
clusters without an IAM VPC endpoint. The node role must be authorized to join: EKS access
entry (or aws-auth with `system:bootstrappers`/`system:nodes`) — forgetting this is the
classic "instances launch, register times out after 15 minutes, repeat" loop.

**`subnetSelectorTerms` / `securityGroupSelectorTerms`.** Use a dedicated
`karpenter.sh/discovery: <cluster>` tag. Do NOT select security groups by the
`kubernetes.io/cluster/<name>` tag — the AWS Load Balancer Controller requires exactly one
SG with that tag and breaks. Karpenter launches into the matched subnet with the most free
IPs. Changing selectors drifts nodes.

**`metadataOptions`.** Defaults: IMDSv2 required, hop limit 1. Raising hop limit to 2 lets
every non-hostNetwork pod assume the node's IAM role via IMDS — use IRSA/Pod Identity for
pod credentials instead. Treat `httpTokens: optional` in a review as a security finding.

**`blockDeviceMappings`.** Defaults: AL2/AL2023 `/dev/xvda` 20Gi gp3 encrypted; Bottlerocket
4Gi root + `/dev/xvdb` 20Gi data; Windows 50Gi. 20Gi fills up fast with large images —
size for image churn. If you specify mappings, Karpenter uses them verbatim (no merging with
defaults). `gp2` in a new config is a review finding (gp3 is cheaper and faster).
`instanceStorePolicy: RAID0` stripes local NVMe and counts it as ephemeral-storage for
scheduling (great for high-IO; data is per-node ephemeral).

**`userData`** merge semantics by family — users often assume their userData replaces
Karpenter's; it doesn't:

- AL2/Windows: your MIME part runs first, Karpenter appends its bootstrap last.
- AL2023: you may provide shell/NodeConfig/MIME; Karpenter appends its NodeConfig and **its
  values win** (cluster info, labels, taints, kubelet settings).
- Bottlerocket: TOML deep-merge, Karpenter's keys win.
- Custom amiFamily: **no merge** — you must fully bootstrap, register with the
  `karpenter.sh/unregistered:NoExecute` taint, and mirror `spec.kubelet` yourself.

**`kubelet`** (lives here since v1, not on NodePool): `maxPods`, `podsPerCore`,
`systemReserved`, `kubeReserved`, eviction thresholds, `imageGCHighThresholdPercent`,
`clusterDNS`, `cpuCFSQuota`. Set them here — Karpenter feeds these into its allocatable
math; hand-rolling them in userData desynchronizes binpacking from reality.

**`tags`.** Merged with defaults (`Name`, `karpenter.sh/nodeclaim`, `karpenter.sh/nodepool`,
`karpenter.k8s.aws/ec2nodeclass`, `kubernetes.io/cluster/<name>: owned`,
`eks:eks-cluster-name`). Cannot override `karpenter.sh/*` / `kubernetes.io/cluster/*` keys.
v1 adds `eks:eks-cluster-name/-arn` tags usable for ABAC/IAM scoping.

**Other:** `detailedMonitoring: true` (1-min CloudWatch metrics, extra cost);
`associatePublicIPAddress` (explicit override of subnet default);
`networkInterfaces[]` (`interface` | `efa-only`) for EFA on static capacity — primary NIC
must be `interface`, EFA-only NICs consume no IPs; `ipPrefixCount` (IPv4/IPv6 prefix
delegation); connection-tracking timeouts (`tcpEstablishedTimeout`, `udpStreamTimeout`,
`udpTimeout`). (`cpuOptions.nestedVirtualization` exists only on the main branch as of
v1.13 — do not present it as released API.)

**Status / readiness.** Conditions `SubnetsReady`, `SecurityGroupsReady`, `AMIsReady`,
`InstanceProfileReady`, `Ready`. A NodePool referencing a non-Ready NodeClass is excluded
from scheduling — `kubectl describe ec2nodeclass` is the first stop when "nothing launches".
IAM validation results are cached: after fixing IAM, touch an annotation on the NodeClass to
force re-validation.

## Capacity reservations (ODCRs) — native since v1.3, beta and on by default since v1.6

```yaml
spec:
  capacityReservationSelectorTerms:
    - id: cr-0123456789abcdef0
    - tags: {team: ml}
      ownerID: "111122223333"
```

- Reserved capacity is a third capacity type: `karpenter.sh/capacity-type: reserved`.
  Priority: **reserved → spot → on-demand**. The NodePool must include `reserved` in its
  capacity-type requirement to use it.
- Scheduler prices reservations near-zero (pre-paid), so consolidation actively migrates
  spot/OD pods onto unused reservations, and consolidates between reservations using
  on-demand price for relative ordering.
- Gotcha: pods with `nodeSelector: {karpenter.sh/capacity-type: on-demand}` will never land
  on reserved nodes — use `NotIn [spot]` instead.
- Expiry behavior: when an ODCR lapses, the node keeps running as plain on-demand (label
  flipped, no drift/replacement; consolidation may then remove it). Capacity Blocks
  (`capacity-reservation-type: capacity-block`): Karpenter drains 10 minutes before EC2
  begins reclaiming, and EC2 reclaims 30 minutes before block end (60 for UltraServers) —
  so plan for pods to leave ~40 minutes before the block ends.
- Reserved Instances / Savings Plans are NOT ODCRs — model them as a weighted NodePool
  (`weight: 50`) with `limits` matching the commitment + an unweighted overflow pool.

## Placement groups

`spec.placementGroupSelector: {name: ...}` (one per NodeClass); `PlacementGroupReady` gates
launches. Labels `karpenter.k8s.aws/placement-group-id` / `placement-group-partition`
(partition usable in topology spread). Strategy caveats: cluster PGs pin to the first AZ —
pin the AZ in NodePool requirements; spread PGs cap at 7 instances/AZ and block
replace-before-terminate disruption at capacity.

## What no longer exists (catch these in reviews)

- Custom launch templates (`launchTemplateName`) — removed at v1beta1; express everything
  via NodeClass fields.
- `karpenter.sh/do-not-evict` / `do-not-consolidate` annotations → `karpenter.sh/do-not-disrupt`.
- Provisioner/Machine/AWSNodeTemplate CRDs → NodePool/NodeClaim/EC2NodeClass.
- Ubuntu amiFamily (v1) — use `Custom` + amiSelectorTerms.
- Kubelet config on the NodePool (v1) — moved to EC2NodeClass.
