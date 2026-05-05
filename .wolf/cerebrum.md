# Cerebrum

> OpenWolf's learning memory. Updated automatically as the AI learns from interactions.
> Do not edit manually unless correcting an error.
> Last updated: 2026-05-04

## User Preferences

<!-- How the user likes things done. Code style, tools, patterns, communication. -->

## Key Learnings

- **Project:** nesi-capi-seed
- **Description:** Ansible automation for bootstrapping a CAPI management cluster on NeSI RDC (OpenStack). Uses temporary Kind cluster to bootstrap, then promotes a k3s node as the permanent management cluster.
- **Two-repo architecture:** `nesi-capi-seed` (mgmt cluster bootstrap) + `ansible-capi-workload` (separate repo — workload cluster provisioning role). The workload role is NOT embedded in nesi-capi-seed.
- **ansible-capi-workload scope:** Does more than CAPI manifest generation — also manages OpenStack security groups (Ansible-owned), installs CNI (Calico/Calico-operator/Cilium), CCM, Cluster Autoscaler (on mgmt cluster), Metrics Server, MachineHealthChecks, and GPU operators (NVIDIA/HaMi).
- **Autoscaler placement:** Autoscaler Deployment runs on the **management cluster** (not workload), reads workload kubeconfig Secret (`{{ cluster_name }}-kubeconfig`), uses `--cloud-provider=clusterapi`. Namespace: `kube-system`.
- **Security groups:** `capi_managed_secgroups: false` default means Ansible/OpenStack SDK creates and owns them. Migration path: CAPO `managedSecurityGroups` in OpenStackCluster spec.
- **CAPI images available:** Rocky 9, v1.28–v1.33 (`rocky-9-containerd-v1.X.X`); GPU image: `rocky-9-containerd-hpc-nvidia-v1.33.3`.
- **GPU:** NVIDIA Operator or HaMi; sharing via MPS or time-slicing; separate MachineDeployment with GPU flavor + GPU image.

- **ORC SecurityGroup `remoteGroupRef` gap (CONFIRMED BLOCKER):** ORC's `SecurityGroupRule` spec has no field for referencing another security group by ID or name. Status has `remoteGroupID` (read-only from OpenStack). The ORC API linter explicitly bans raw UUID fields in spec (enforced: `SecurityGroupRule.RemoteGroupID` is a named linter test case). Correct ORC fix: add `remoteGroupRef *KubernetesNameRef` to spec. Interim: ORC CIDR-based rules (if each cluster has unique node CIDR). Ansible secgroup cross-group rules (IP-in-IP, BGP, all-traffic) ALL use `remote_group` — none can be expressed in ORC today.
- **CAPO `managedSecurityGroups` is NOT viable:** opens port 6443 to 0.0.0.0/0 by default. Cannot remove or restrict that default rule via `allNodesSecurityGroupRules`. This is the ORIGINAL REASON custom Ansible secgroups were built. Do not recommend CAPO managed secgroups for this project.
- **Why the GitOps migration stalled:** ORC limitation is the primary blocker. Custom secgroups were deliberately chosen to restrict 6443 to `163.7.144.0/21` (NeSI RDC range). CAPO's default exposes 6443 to the world — unacceptable.
- **Viable interim:** ORC CIDR-based rules (`remoteIPPrefix: cluster_node_cidr`) IF clusters have unique node CIDRs. Need to verify this. Default `cluster_node_cidr: 10.10.0.0/24` in ansible-capi-workload defaults — if all clusters use this same CIDR, CIDR approach would be insecure.

- **OpenStack auth URL:** `https://keystone.akl-1.cloud.nesi.org.nz`, region `akl-1`, `verify: false`
- **External network ID (for OpenStackCluster):** `3f405cc9-28a3-4973-b5a1-7f50f112e5d5`
- **OPENSTACK_FAILURE_DOMAIN:** `nova`
- **Fleet repo location:** `/home/kanderson/scm/kahu/capi-project/reannz-capi-fleet/` — push to `https://gitlab.com/nesi1/rebase/reannz-capi-fleet`
- **CAPI image base:** Ubuntu 24 (`ubuntu-24-containerd-vX.Y.Z`), not Rocky 9 — mgmt uses `ubuntu-24-containerd-v1.35.3`
- **Workload cluster (rdc-workload-1):** k8s v1.35.3, image ubuntu-24-containerd-v1.35.3, namespace NeSI-Training-Prod, 1 CP + 2 workers, node CIDR 10.2.0.0/24 (different from mgmt 10.1.0.0/24)
- **Age public key:** `age1myy9zc6dnd9acw360ekxt9fae044emf382xkxssvgr0p8cpavqlsxnujal` — already in `.sops.yaml`
- **Flux vars needed in servers.yml:** `flux_gitlab_token`, `flux_age_key_path`, `openstack_auth_url`, `openstack_app_credential_id`, `openstack_app_credential_secret` — all sensitive, never commit
- **tf-controller chart:** `oci://ghcr.io/flux-iac/charts/tofu-controller` (project renamed from tf-controller to tofu-controller after Weaveworks shutdown)
- **CCM credentials flow:** `ccm-cloud-config.yaml` (SOPS-encrypted Secret on mgmt cluster) → ClusterResourceSet → applies `cloud-config` Secret to workload `kube-system`

## Do-Not-Repeat

<!-- Mistakes made and corrected. Each entry prevents the same mistake recurring. -->
<!-- Format: [YYYY-MM-DD] Description of what went wrong and what to do instead. -->

- **Fleet repo is GitLab, not GitHub:** `https://gitlab.com/nesi1/nesi-capi-fleet`. Secret name `flux-gitlab-token`. Token type: Project Access Token or Personal Access Token with `read_repository` scope. Branch protection = GitLab protected branch + MR approval rules. Use "MR" not "PR" throughout.

## Decision Log

<!-- Significant technical decisions with rationale. Why X was chosen over Y. -->

- **[2026-05-05] Flux Operator over `flux bootstrap github`** — User confirmed. Operator manages Flux controllers via `FluxInstance` CR; upgrades are Git PRs not CLI re-runs; no generated manifests committed to fleet repo.
- **[2026-05-05] ClusterResourceSet for standard cluster in-cluster components** — CNI, CCM, Metrics Server bootstrapped via CAPI ClusterResourceSet (ConfigMap strategy). Avoids Flux-on-workload-cluster for simple clusters.
- **[2026-05-05] Flux on workload cluster only for GPU clusters** — NVIDIA Operator too complex for ClusterResourceSet (needs Helm + lifecycle). GPU clusters get Flux installed; standard clusters do not.
- **[2026-05-05] Autoscaler RBAC shared in `infrastructure/autoscaler-rbac/`** — ClusterRoles are cluster-scoped; per-cluster duplication would conflict. Single shared path.
- **[2026-05-05] Separate autoscaler Kustomization with `dependsOn`** — Autoscaler must start after workload cluster Ready; `dependsOn: [cluster-ks]` ensures ordering.
- **[2026-05-05] No `ownerReferences` in fleet repo autoscaler YAML** — Flux `prune: true` handles autoscaler lifecycle; Ansible's UID-based ownerReferences not needed.
