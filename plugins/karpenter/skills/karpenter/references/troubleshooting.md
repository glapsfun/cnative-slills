# Troubleshooting

Diagnose from evidence before changing config. The evidence chain, in order:

1. `kubectl describe nodeclaim <name>` — status conditions (`Launched`, `Registered`,
   `Initialized`, `Ready`) + events tell you *which phase* failed.
2. `kubectl get nodepool -o wide` / `kubectl describe nodepool` — `Ready` condition,
   `status.resources` vs `spec.limits`, `NodeRegistrationHealthy` condition.
3. `kubectl describe ec2nodeclass` — `SubnetsReady`/`SecurityGroupsReady`/`AMIsReady`/
   `InstanceProfileReady`; a non-Ready NodeClass silently excludes its NodePools.
4. Pod events (`FailedScheduling` messages quote the exact unmet requirement).
5. Controller logs: `kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter`
   (`--set logLevel=debug` if needed). On **Auto Mode** there are no controller logs — use
   kube-apiserver audit logs in CloudWatch Logs Insights (see auto-mode.md).

## Pods Pending, no node launches

`FailedScheduling: no instance type met the scheduling requirements...`:

- Pod constraints ∩ NodePool requirements = ∅ — wrong label namespace
  (`karpenter.k8s.aws/*` vs `eks.amazonaws.com/*`), zone-pinned PV vs zone-restricted pool,
  arch mismatch, missing toleration for the pool's taint.
- Requests larger than any allowed instance — remember DaemonSet requests count.
- **NodePool limit reached** — log-only failure (`...exceeds limit...`), nothing on the pod
  beyond Pending. Check `status.resources` vs `limits` first; it's the most-missed cause.
- 100-requirement cap exceeded (heavily-labeled pods propagate into the NodeClaim).
- NodeClass not Ready (see chain above) — e.g. amiSelectorTerms matching zero AMIs.

## Instances launch, then disappear every ~15 minutes

Registration timeout: the instance never joins, Karpenter terminates it and retries.

- Node role missing from EKS access entries / aws-auth (`Unauthorized` in kubelet logs;
  aws-auth username must be `system:node:{{EC2PrivateDNSName}}`).
- Encrypted root volume, KMS key policy missing EC2 grants (instances die immediately).
- Private cluster missing STS/SSM endpoints; broken userData for Custom amiFamily (must
  register with the `karpenter.sh/unregistered:NoExecute` taint).
- Security groups blocking kubelet→API server (NodeRegistrationHealthy=False on the pool).
- Spot service-linked role absent (`ServiceLinkedRoleCreationNotPermitted`).
- After fixing IAM, touch an annotation on the EC2NodeClass — validation results are cached.

## Node joins but never Ready / never Initialized

- CNI not ready: `NetworkPluginNotReady` → check `aws-node`; declare CNI/CSI readiness
  taints as `startupTaints` (`node.cilium.io/agent-not-ready`,
  `ebs.csi.aws.com/agent-not-ready`).
- GPU nodes stuck uninitialized: device plugin daemonset missing → `nvidia.com/gpu` never
  appears in allocatable (self-hosted; Auto Mode bundles it).
- Outdated VPC CNI: `No entry for <type> in eni-max-pods.txt`.
- Allocatable mismatch (`ConsistentStateFound=False`): tune `VM_MEMORY_OVERHEAD_PERCENT`
  (default 7.5%).

## Provisioning loops / runaway scale-up

A taint appears on nodes that Karpenter didn't expect (applied by daemonset or userData) →
pods "can't schedule" → another node launches, forever. Declare it in `startupTaints`.
Also: bad AMI NotReady-looping (pin a known-good AMI; `limits` are the blast-radius cap —
this is why every pool needs them).

## Excessive churn (nodes living minutes)

- `consolidateAfter: 0s` with bursty workloads → raise to 5–15m; check the node-lifetime
  metric distribution for a sub-15-min mass.
- NTH running alongside Karpenter (rebalance-drain loop) → remove NTH.
- Unstable placement: preferred affinities / ScheduleAnyway topology spread make the
  consolidation simulation flip-flop → make them `required`/`DoNotSchedule` or budget it.
- Deploy-time surge nodes consolidating minutes later is normal; budgets smooth it.

## Nodes won't scale down

Read the `Unconsolidatable`/`DisruptionBlocked` events first — they name the cause:

- Blocking PDB (`maxUnavailable: 0`, duplicate selectors, unhealthy single-replica apps).
- `karpenter.sh/do-not-disrupt` pods (forgotten `"true"` annotations; prefer durations).
- Pods without a controller owner; un-drainable local storage expectations (emptyDir).
- "Can't replace with a lower-priced node": already optimal, or instance diversity too
  narrow; spot pools without the `SpotToSpotConsolidation` gate only consolidate when empty
  (and spot→spot replacement needs ≥15 cheaper types).
- `consolidateAfter: Never` / `WhenEmpty` on a pool that never empties.
- Node not Initialized (startup taint stuck, missing extended resource) — not a candidate.
- Fix for "must make progress regardless": `terminationGracePeriod` on the pool.

## Drift storms (mass node replacement "out of nowhere")

- `@latest` AMI alias + new AMI release → whole fleet Drifted. Pin in prod.
- Karpenter upgrade changed the NodeClaim hash → same effect. Tighten budgets pre-upgrade.
- Edited subnet/SG selectors or requirements → expected; pace with `reasons: [Drifted]`
  budgets. Remember behavioral fields (`weight`, `limits`, `disruption.*`) never drift.
- v1.12-era CA-bundle change drifts all nodes once after that specific upgrade.

## Stuck deletes / finalizers

Node stuck terminating after Karpenter was uninstalled or broke: the
`karpenter.sh/termination` finalizer has no controller to act —
`kubectl patch node <n> --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'`
(instance may keep running; terminate via EC2). Never delete a Karpenter node by deleting
only the EC2 instance — drain via `kubectl delete nodeclaim` instead.

## Networking / IP pressure

- `failed to assign an IP address to container` → subnet IP exhaustion: prefix delegation,
  custom networking/secondary CIDRs, IPv6, or spread across more/bigger subnets.
- Security-groups-for-pods: pods stuck ContainerCreating on `vpc.amazonaws.com/pod-eni` up
  to 30 min — label the pool `vpc.amazonaws.com/has-trunk-attached: "false"` and set
  `RESERVED_ENIS=1`.

## Spot-specific

- "Karpenter refuses to launch type X": ICE cache — failed offerings are blacklisted ~3
  minutes per type+zone; with both capacity types allowed, on-demand fills the gap.
- Frequent interruptions: too-narrow type list (PCO needs choices); verify the interruption
  queue is configured at all (`settings.interruptionQueue`) — without it, spot nodes die
  with no drain.
