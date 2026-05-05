# Plan: CAPI Workload Clusters via Flux GitOps

**Status:** Draft for review  
**Date:** 2026-05-05  
**Scope:** Moving workload cluster lifecycle management from two Ansible repos to Flux-reconciled Git repositories, running on OpenStack via CAPO.

---

## 1. Goals

- Every CAPI workload cluster is defined declaratively in Git
- Creating, upgrading, or scaling a cluster = opening a merge request (MR)
- No ad-hoc `kubectl apply` or Ansible runs needed after initial mgmt cluster bootstrap
- Secrets never stored in plaintext in Git
- Existing workload clusters migrated without downtime
- GPU-enabled clusters managed via the same GitOps workflow

---

## 2. Current State

Two separate repos currently handle the full lifecycle:

```
[nesi-capi-seed] — Management cluster bootstrap
Operator → Ansible (nesi-capi-seed) → Kind (bootstrap) → CAPI mgmt cluster promoted on k3s
```

```
[ansible-capi-workload] — Workload cluster provisioning (separate repo/role)
Operator → Ansible (ansible-capi-workload role) → {
  ├── OpenStack SDK → Security Groups (Ansible-managed, capi_managed_secgroups: false)
  ├── clusterctl/kubectl → CAPI manifests → mgmt cluster → OpenStack VMs (workload nodes)
  └── kubectl (workload kubeconfig) → workload cluster gets:
      ├── CNI: Calico (default), Calico Operator, or Cilium
      ├── OpenStack Cloud Controller Manager (CCM)
      ├── Cluster Autoscaler (Deployment on mgmt cluster, reads workload kubeconfig Secret)
      ├── Metrics Server
      ├── MachineHealthChecks (control plane + worker)
      └── GPU: NVIDIA Operator or HaMi (optional, separate node pool)
}
```

Workload clusters are ephemeral Ansible targets. No single source of truth in Git post-creation.

Key variables driving per-cluster config (`ansible-capi-workload/defaults/main.yml`):
- Kubernetes version + image name (Rocky 9, v1.28–v1.33 available)
- Flavors: control plane, worker, GPU worker
- Node counts + max (autoscaler min/max)
- Network: node CIDR, pod CIDR, external network ID, additional networks
- Security groups: additional groups, Ansible vs CAPO managed
- OIDC config (optional, wired into KubeadmControlPlane apiServer extraArgs)
- CNI provider (`calico`, `calico-operator`, `cilium`)
- GPU: enabled flag, flavor, image, NVIDIA/HaMi choice, sharing type (MPS/time-slicing)

---

## 3. Target Architecture

```
GitLab repo
    ↓  (Flux GitRepository watches)
Flux on CAPI mgmt cluster
    ↓  (Kustomization reconciles every N minutes)
CAPI controllers (CAPO) on mgmt cluster
    ↓
OpenStack VMs (workload cluster nodes)
    ↓  (ClusterResourceSet bootstraps in-cluster components)
Workload cluster gets CNI, CCM, Metrics Server, HealthChecks on first boot
    ↓  (Autoscaler Deployment on mgmt cluster reads workload kubeconfig Secret)
Autoscaling operational
```

The management cluster bootstrap (nesi-capi-seed) stays largely unchanged. After bootstrap, a one-time step installs Flux on the management cluster and connects it to the cluster fleet repo.

Security groups move from Ansible-managed to CAPO-managed (`managedSecurityGroups` in OpenStackCluster spec) — see Section 4.5.

---

## 4. Component Breakdown

### 4.1 Flux Operator on the Management Cluster

Rather than `flux bootstrap` (which commits generated Flux manifests into the fleet repo and is harder to upgrade), we use the **Flux Operator** — a Helm-installed controller that manages the Flux controllers lifecycle via a `FluxInstance` custom resource.

**Why Flux Operator over `flux bootstrap`:**
- Flux upgrades are a single field change in `FluxInstance.spec.distribution.version`, MR-reviewed like any other change
- No generated/unowned manifests in `flux-system/` committed to the fleet repo
- Operator manages controller rollouts; no `flux bootstrap` re-runs needed
- `FluxInstance` lives in the fleet repo — Flux becomes fully self-describing

**Install sequence (Ansible task, runs once post-mgmt-cluster-promotion):**

```bash
# 1. Install the Flux Operator via Helm
helm install flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/flux-operator \
  --namespace flux-system \
  --create-namespace \
  --wait

# 2. Create GitLab token secret
kubectl create secret generic flux-gitlab-token \
  --namespace flux-system \
  --from-literal=username=git \
  --from-literal=password=<gitlab-access-token>

# 3. Create SOPS Age decryption secret
kubectl create secret generic sops-age \
  --namespace flux-system \
  --from-file=age.agekey=./age.agekey

# 4. Apply FluxInstance — operator installs Flux controllers + wires up fleet repo sync
kubectl apply -f flux-instance.yaml
```

**`flux-instance.yaml`** (committed to this repo, applied imperatively on first boot):

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux
  namespace: flux-system
spec:
  distribution:
    version: "2.x"
    registry: "ghcr.io/fluxcd"
  components:
    - source-controller
    - kustomize-controller
    - helm-controller
    - notification-controller
  cluster:
    type: kubernetes
    multitenant: false
    networkPolicy: true
    domain: cluster.local
  sync:
    kind: GitRepository
    url: "https://gitlab.com/nesi1/nesi-capi-fleet"
    ref: "refs/heads/main"
    path: "clusters/management"
    pullSecret: "flux-gitlab-token"
```

Once applied, the operator installs Flux controllers and creates a Kustomization reconciling `clusters/management` from the fleet repo. From that point, the `FluxInstance` itself is in Git — Flux upgrades are PRs, not CLI re-runs.

**Integration point with nesi-capi-seed:** New Ansible tasks at end of management promotion (after kubeconfig is available). Requires `helm`, `kubectl`, and a GitLab access token in `servers.yml` (not committed).

### 4.2 Fleet Repository Structure

Single monorepo approach (recommended over per-cluster repos for this scale):

```
nesi-capi-fleet/
├── clusters/
│   ├── management/                            # Reconciled by Flux (via FluxInstance sync.path)
│   │   ├── flux-instance.yaml                 # FluxInstance CR — Flux manages itself
│   │   ├── fleet-gitrepo.yaml                 # GitRepository source for this fleet repo
│   │   ├── rdc-workload-1-secgroups-tf.yaml   # Terraform CR — secgroups (no dependsOn)
│   │   ├── rdc-workload-1-ks.yaml             # Kustomization → clusters/rdc-workload-1 (dependsOn secgroups-tf)
│   │   ├── rdc-workload-1-autoscaler-ks.yaml  # Kustomization → autoscaler (dependsOn rdc-workload-1)
│   │   ├── rdc-gpu-1-secgroups-tf.yaml
│   │   ├── rdc-gpu-1-ks.yaml
│   │   └── rdc-gpu-1-autoscaler-ks.yaml
│   │
│   ├── rdc-workload-1/
│   │   ├── kustomization.yaml                 # Kustomize config (not a Flux resource)
│   │   ├── cluster.yaml                       # Cluster + OpenStackCluster
│   │   ├── control-plane.yaml                 # KubeadmControlPlane + OpenStackMachineTemplate (CP)
│   │   ├── workers.yaml                       # MachineDeployment + KubeadmConfigTemplate + OpenStackMachineTemplate (workers)
│   │   ├── healthchecks.yaml                  # MachineHealthCheck (control-plane + worker)
│   │   ├── cluster-resource-set.yaml          # ClusterResourceSet binding CNI + CCM + metrics-server
│   │   ├── cloud-config.yaml                  # Secret (SOPS encrypted) — clouds.yaml + CA cert
│   │   └── secgroups/
│   │       ├── main.tf                        # openstack_networking_secgroup_v2 + rules with remote_group_id
│   │       ├── variables.tf                   # cluster_name, cluster_namespace, source_ips
│   │       └── versions.tf                    # OpenStack provider pin
│   │
│   ├── rdc-workload-1/autoscaler/
│   │   ├── kustomization.yaml
│   │   └── autoscaler.yaml                    # Autoscaler Deployment on mgmt cluster
│   │
│   └── rdc-gpu-1/
│       ├── kustomization.yaml
│       ├── cluster.yaml
│       ├── control-plane.yaml
│       ├── workers.yaml
│       ├── gpu-workers.yaml                   # GPU MachineDeployment (separate pool)
│       ├── healthchecks.yaml
│       ├── cluster-resource-set.yaml
│       ├── cloud-config.yaml
│       ├── secgroups/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── versions.tf
│       └── autoscaler/
│           └── autoscaler.yaml
│
└── infrastructure/
    ├── autoscaler-rbac/                        # Shared ClusterRoles (cluster-scoped, applied once)
    │   └── rbac.yaml
    ├── openstack/
    │   └── shared-config.yaml                  # Shared values (external network ID, image names)
    └── workload-components/
        ├── cni-calico-configmap.yaml            # ConfigMap containing Calico install manifest
        ├── cni-cilium-configmap.yaml            # ConfigMap containing Cilium install manifest
        ├── ccm-openstack-configmap.yaml         # ConfigMap containing CCM install manifest
        └── metrics-server-configmap.yaml        # ConfigMap containing metrics-server manifest
```

**How the self-management loop works:**
1. Operator reconciles `clusters/management` → sees `flux-instance.yaml` → keeps Flux at declared version
2. `clusters/management` contains one Flux `Kustomization` per workload cluster (CAPI objects) plus one per autoscaler deployment
3. To add a cluster: add its directory + add Kustomization entries in `clusters/management` → one MR
4. To upgrade Flux: bump `spec.distribution.version` in `flux-instance.yaml` → MR → operator rolls out

### 4.3 Flux Resources per Cluster

**GitRepository** (shared, one for entire fleet):
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: nesi-capi-fleet
  namespace: flux-system
spec:
  interval: 1m
  url: https://gitlab.com/nesi1/nesi-capi-fleet
  ref:
    branch: main
  secretRef:
    name: flux-gitlab-token
```

**Terraform CR** — Secgroups (no dependsOn — must exist before CAPI Kustomization):
```yaml
apiVersion: infra.contrib.fluxcd.io/v1alpha2
kind: Terraform
metadata:
  name: rdc-workload-1-secgroups
  namespace: flux-system
spec:
  interval: 5m
  approvePlan: auto
  path: ./clusters/rdc-workload-1/secgroups
  sourceRef:
    kind: GitRepository
    name: nesi-capi-fleet
  vars:
    - name: cluster_name
      value: rdc-workload-1
    - name: cluster_namespace
      value: nesi-project
  varsFrom:
    - kind: Secret
      name: openstack-tf-credentials    # separate SOPS secret for TF provider auth
```

**Kustomization** — CAPI objects (dependsOn secgroups Terraform):
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: rdc-workload-1
  namespace: flux-system
spec:
  interval: 5m
  path: ./clusters/rdc-workload-1
  prune: true          # deletes cluster if removed from Git — see warning below
  dependsOn:
    - name: rdc-workload-1-secgroups   # secgroups must exist before machines reference them
  sourceRef:
    kind: GitRepository
    name: nesi-capi-fleet
  decryptionRef:
    provider: sops
    secretRef:
      name: sops-age
```

**Kustomization** — Autoscaler (dependsOn CAPI Kustomization):
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: rdc-workload-1-autoscaler
  namespace: flux-system
spec:
  interval: 5m
  path: ./clusters/rdc-workload-1/autoscaler
  prune: true
  dependsOn:
    - name: rdc-workload-1
  sourceRef:
    kind: GitRepository
    name: nesi-capi-fleet
```

> **Warning on `prune: true`:** Deleting a cluster directory from Git triggers Flux to delete the `Cluster` object, causing CAPI to deprovision all OpenStack VMs. The Terraform CR deletion also triggers tf-controller to destroy the security groups. Order matters: remove the CAPI Kustomization first (cluster deprovisioned), then remove the Terraform CR (secgroups destroyed). The easiest way is a two-MR approach: MR 1 removes the cluster directory + Kustomization entries, MR 2 (after cluster gone) removes the secgroup Terraform.

### 4.4 In-Cluster Component Bootstrap (ClusterResourceSet)

The `ansible-capi-workload` role currently installs CNI, CCM, and Metrics Server onto the workload cluster after CAPI provisions it. In the Flux workflow, this is handled by **CAPI's ClusterResourceSet** — a mechanism that applies ConfigMaps (or Secrets) as manifests onto matching workload clusters on first boot.

**ClusterResourceSet** (in each cluster's directory, or shared):
```yaml
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: rdc-workload-1-addons
  namespace: <cluster-namespace>
spec:
  strategy: ApplyOnce           # or Reconcile — see note below
  clusterSelector:
    matchLabels:
      cluster.x-k8s.io/cluster-name: rdc-workload-1
  resources:
    - name: cni-calico           # ConfigMap in infrastructure/workload-components/
      kind: ConfigMap
    - name: ccm-openstack
      kind: ConfigMap
    - name: metrics-server
      kind: ConfigMap
```

> **`strategy: ApplyOnce` vs `Reconcile`:** `ApplyOnce` applies manifests at cluster creation and never again — safe for CNI (prevents drift fights). `Reconcile` keeps re-applying — better for CCM where updates matter. Choose per-resource if the ClusterResourceSet controller version supports it; otherwise use separate CRS resources per strategy.

**MachineHealthChecks** (static, no ClusterResourceSet needed — these live on the mgmt cluster as CAPI objects):
```yaml
# healthchecks.yaml — included in each cluster's kustomization
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineHealthCheck
metadata:
  name: rdc-workload-1-worker-healthcheck
  namespace: <cluster-namespace>
spec:
  clusterName: rdc-workload-1
  selector:
    matchLabels:
      cluster.x-k8s.io/deployment-name: rdc-workload-1-md-0
  unhealthyConditions:
    - type: Ready
      status: "False"
      timeout: 5m
    - type: Ready
      status: Unknown
      timeout: 5m
```

**What ClusterResourceSet handles:**
| Component | Where applied | Strategy |
|-----------|--------------|----------|
| CNI (Calico/Cilium) | Workload cluster | `ApplyOnce` |
| OpenStack CCM | Workload cluster | `Reconcile` |
| Metrics Server | Workload cluster | `Reconcile` |
| MachineHealthCheck | Mgmt cluster (CAPI object) | Flux Kustomization |
| Cluster Autoscaler | Mgmt cluster (Deployment) | Flux Kustomization |
| GPU Operator | Workload cluster | Flux on workload cluster (see §4.6) |

### 4.5 Security Group Strategy — The Blocker

This is the **primary reason the GitOps migration has not been completed**. The analysis below explains the gap and the available paths forward.

#### What Ansible currently does

`ansible-capi-workload` creates two security groups per cluster (`secgroup-controlplane`, `secgroup-worker`), then adds rules that **cross-reference each other by OpenStack group ID** (`remote_group`):

| Rule | Security Group | References |
|------|---------------|------------|
| All traffic (any protocol) | controlplane SG | ← from controlplane SG (self) |
| All traffic (any protocol) | controlplane SG | ← from worker SG |
| IP-in-IP (protocol 4, Calico) | controlplane SG | ← from controlplane SG |
| IP-in-IP (protocol 4, Calico) | controlplane SG | ← from worker SG |
| BGP TCP:179 (Calico) | controlplane SG | ← from controlplane SG |
| BGP TCP:179 (Calico) | controlplane SG | ← from worker SG |
| Kubernetes API TCP:6443 | controlplane SG | ← from `source_ips` CIDR (163.7.144.0/21) |
| All traffic (any protocol) | worker SG | ← from controlplane SG |
| All traffic (any protocol) | worker SG | ← from worker SG (self) |
| IP-in-IP (protocol 4) | worker SG | ← from controlplane SG |
| IP-in-IP (protocol 4) | worker SG | ← from worker SG |
| BGP TCP:179 | worker SG | ← from controlplane SG |
| BGP TCP:179 | worker SG | ← from worker SG |
| NodePort TCP:30000-32767 | worker SG | ← 0.0.0.0/0 |
| NodePort UDP:30000-32767 | worker SG | ← 0.0.0.0/0 |

The Kubernetes API and NodePort rules use IP CIDRs (ORC can do these). Every other rule uses `remote_group` — referencing the other SG (or self) by OpenStack UUID.

#### Why ORC cannot do this today

ORC's `SecurityGroupRule` spec supports `RemoteIPPrefix` (CIDR) but has **no field for referencing another security group**. The `RemoteGroupID` field exists only in `SecurityGroupRuleStatus` (read from OpenStack, never set by spec). ORC's own API linter explicitly enforces this: raw OpenStack UUIDs in spec fields are banned. The linter test file even names `SecurityGroupRule.RemoteGroupID` as an example violation.

The actuator's `updateRules()` builds `rules.CreateOpts` without ever setting `RemoteGroupID` — because there is no spec field to read it from.

#### The correct ORC fix: `remoteGroupRef *KubernetesNameRef`

ORC's design principle: "ORC objects only reference other ORC objects, never OpenStack resources directly." So the correct spec addition is:

```go
// In SecurityGroupRule spec
RemoteGroupRef *KubernetesNameRef `json:"remoteGroupRef,omitempty"`
```

The controller's `updateRules()` would then:
1. For each rule with `remoteGroupRef` set, fetch the referenced ORC `SecurityGroup` object
2. If it isn't `Available` yet → requeue (no circular deadlock — SG creation is independent of rule creation)
3. Once Available → use `status.ID` as `RemoteGroupID` in `rules.CreateOpts`
4. In `rulesMatch()`: also compare `osRule.RemoteGroupID` against the resolved ID

**No circular creation deadlock:** OpenStack allows adding rules that reference other groups that already exist. The two SG objects are Created independently (Ansible does the same — create both groups first, then add cross-rules). `updateRules()` only runs post-creation. By the time CP SG's `updateRules` runs, Worker SG will either be Available (its ID can be resolved) or not yet (requeue). Same in reverse. No deadlock.

**Self-referencing** (CP SG rules referencing the CP SG itself): `remoteGroupRef` points to the same ORC object — the controller already has its OpenStack ID in hand, so no dependency wait needed.

This is a **missing feature in ORC** — a moderate-sized contribution to add.

#### Why the custom rules exist

The reason NeSI implemented custom Ansible-managed secgroups instead of using CAPO's `managedSecurityGroups` is that **CAPO's default managed security groups open port 6443 to `0.0.0.0/0`** — the Kubernetes API endpoint exposed to the public internet. This is unacceptable. The custom rules restrict 6443 to `source_ips: 163.7.144.0/21` (NeSI RDC network range) only.

This means CAPO `managedSecurityGroups` is **not a viable replacement** — it has the same 6443-open-to-world problem. Even with `allNodesSecurityGroupRules` you can only ADD rules, not remove or replace CAPO's default 6443 rule.

#### Decision: tf-controller for secgroups

Since cluster nodes may be on multiple networks, CIDR-based rules cannot safely approximate `remote_group` references. The chosen approach is **tf-controller** — Flux's Terraform controller — which runs OpenTofu/Terraform as a reconciled Kubernetes resource. Terraform's OpenStack provider supports `remote_group_id` natively, making it a direct translation of the Ansible tasks.

**Why tf-controller fits here:**
- Direct parity with existing Ansible secgroup logic — `remote_group_id` is a first-class Terraform field
- The project already uses the OpenStack Terraform provider (see `terraform/` in nesi-capi-seed)
- State stored as a Kubernetes Secret on the mgmt cluster — no external state backend needed
- Flux reconciles the `Terraform` CR on every interval — drift detection and correction included
- Secgroup ordering handled naturally: the CAPI `Kustomization` has `dependsOn` the `Terraform` CR

**tf-controller install** (added to `roles/flux-operator/` in nesi-capi-seed, runs once post-mgmt-cluster-promotion):
```bash
helm install tf-controller \
  oci://ghcr.io/weaveworks/charts/tf-controller \
  --namespace flux-system \
  --set replicaCount=1 \
  --wait
```

**OpenStack credentials for Terraform** — separate SOPS-encrypted Secret, referenced by `varsFrom` in the Terraform CR. Contains the application credential ID and secret as Terraform variables (or a `clouds.yaml` mounted as a file). This is distinct from the per-cluster CAPI `cloud-config.yaml` Secret:

```yaml
# openstack-tf-credentials.yaml (SOPS encrypted, committed to fleet repo)
apiVersion: v1
kind: Secret
metadata:
  name: openstack-tf-credentials
  namespace: flux-system
stringData:
  OS_AUTH_URL: https://cloud.nesi.org.nz:5000/v3
  OS_APPLICATION_CREDENTIAL_ID: <app-cred-id>
  OS_APPLICATION_CREDENTIAL_SECRET: <app-cred-secret>
```

The Terraform provider reads these as environment variables when `TF_VAR_` prefix is used, or via `varsFrom` in the Terraform CR.

**Secgroup Terraform files** (see `ansible-capi-workload/gitops-migration-plan.md` for full HCL — direct translation of `secgroups-control-plane.yml` and `secgroups-worker.yml`).

**Long-term:** Once `remoteGroupRef *KubernetesNameRef` is contributed to ORC, the Terraform secgroup files can be replaced with ORC `SecurityGroup` objects and tf-controller can be removed. The migration is non-disruptive: adopt existing secgroups into ORC via import, then delete the Terraform resources.

### 4.6 GPU Cluster Handling

GPU clusters require:
1. **Separate node pool** (`gpu-workers.yaml` — MachineDeployment with GPU flavor + GPU image `rocky-9-containerd-hpc-nvidia-v1.33.3`)
2. **NVIDIA GPU Operator or HaMi** — deployed on the workload cluster

GPU Operator is too complex for ClusterResourceSet (requires Helm, custom CRDs, lifecycle management). Recommended approach: **Flux on workload cluster** for GPU clusters specifically.

**For GPU-enabled clusters, after CAPI provisions the workload cluster:**
1. Install Flux on workload cluster (one-time, via Ansible or ClusterResourceSet bootstrap manifest)
2. Point it at a `clusters/rdc-gpu-1/workload-addons/` path in the fleet repo
3. That path contains HelmRelease for NVIDIA Operator with the `gpu-feature-discovery` and MPS config

This is scoped to GPU clusters only — standard clusters continue to use ClusterResourceSet for simplicity.

**MPS ConfigMap** (`nvidia-gpu-mps-config-all.yml.j2` equivalent) committed as static YAML per GPU cluster, applied via Flux.

---

## 5. Secrets Management

### Strategy: SOPS + Age

- Age key pair generated per environment (not per cluster)
- Public key committed to repo; private key stored as a Kubernetes Secret on the mgmt cluster
- Flux decrypts SOPS-encrypted files during reconciliation

**Setup (one-time):**
```bash
# Generate age key
age-keygen -o age.agekey

# Store private key on mgmt cluster
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=./age.agekey

# Configure SOPS to use this key (add to .sops.yaml in fleet repo)
```

**.sops.yaml in fleet repo root:**
```yaml
creation_rules:
  - path_regex: .*/cloud-config\.yaml$
    age: age1<public-key-here>
```

**What gets encrypted:**
- `cloud-config.yaml` — contains `clouds.yaml` (base64) + CA cert (base64) as a Kubernetes Secret
- Any per-cluster credentials

**What does NOT need encryption:**
- Cluster topology (node counts, flavors, versions) — not sensitive
- Network config, image names — not sensitive
- OIDC config — not sensitive

### Alternative: External Secrets Operator

If NeSI runs Vault or AWS Secrets Manager, External Secrets Operator can pull credentials at runtime instead of SOPS. More ops overhead but better rotation story. Not recommended for initial implementation.

---

## 6. Cluster Manifest Generation

Current: `ansible-capi-workload` renders `cluster-template.yml.j2` via Ansible, runs `clusterctl generate cluster`, then imperatively applies everything.

Target: Pre-rendered static YAML committed to the fleet repo, covering all components.

### Full component inventory per cluster (from ansible-capi-workload)

| Component | Current source | Fleet repo file | Applied where |
|-----------|---------------|-----------------|---------------|
| Secret (clouds.yaml + CA cert) | `cluster-template.yml.j2` head | `cloud-config.yaml` (SOPS) | Mgmt cluster |
| KubeadmConfigTemplate | `cluster-template.yml.j2` | `workers.yaml` | Mgmt cluster |
| Cluster | `cluster-template.yml.j2` | `cluster.yaml` | Mgmt cluster |
| OpenStackCluster | `cluster-template.yml.j2` | `cluster.yaml` | Mgmt cluster |
| MachineDeployment | `cluster-template.yml.j2` | `workers.yaml` | Mgmt cluster |
| KubeadmControlPlane (+ OIDC args) | `cluster-template.yml.j2` | `control-plane.yaml` | Mgmt cluster |
| OpenStackMachineTemplate (CP) | `cluster-template.yml.j2` | `control-plane.yaml` | Mgmt cluster |
| OpenStackMachineTemplate (workers) | `cluster-template.yml.j2` | `workers.yaml` | Mgmt cluster |
| MachineHealthCheck | `install-healthchecks.yml` | `healthchecks.yaml` | Mgmt cluster |
| Autoscaler Deployment + RBAC | `autoscaler-deployment.yml.j2` | `autoscaler/autoscaler.yaml` | Mgmt cluster |
| CNI (Calico/Cilium) | `cni-*.yml` tasks | ConfigMap in `infrastructure/workload-components/` | Workload (via ClusterResourceSet) |
| OpenStack CCM | `install-cloud-manager.yml` | ConfigMap in `infrastructure/workload-components/` | Workload (via ClusterResourceSet) |
| Metrics Server | `install-metrics-server.yml` | ConfigMap in `infrastructure/workload-components/` | Workload (via ClusterResourceSet) |
| GPU MachineDeployment | `cluster-template-gpu-node.yml.j2` | `gpu-workers.yaml` | Mgmt cluster |
| NVIDIA Operator / HaMi | `gpu-nvidia-operator.yml` | Flux on workload cluster | Workload |
| MPS config | `nvidia-gpu-mps-config-all.yml.j2` | Flux on workload cluster | Workload |
| OIDC ClusterRole + Binding | `configure-oidc-roles.yml` | `oidc-rbac.yaml` | Workload (via ClusterResourceSet or Flux) |
| OpenStack security groups | `secgroups-*.yml` (Ansible) | `managedSecurityGroups` in `cluster.yaml` | CAPO-managed |

### Autoscaler note on ownerReferences

Current Ansible: embeds `cluster_uid` in `ownerReferences` so garbage collection happens automatically. With Flux `prune: true`, this is unnecessary — Flux deletes the autoscaler Deployment when the cluster Kustomization is deleted. Omit `ownerReferences` in the fleet repo autoscaler manifests. The RBAC resources (ClusterRole/ClusterRoleBinding) are shared across all autoscalers — use a dedicated `infrastructure/autoscaler-rbac/` path reconciled once, not per-cluster.

### Migration Tool (one-off for existing clusters)

Export current CAPI state from mgmt cluster:
```bash
kubectl get cluster,openstackcluster,kubeadmcontrolplane,openstackmachinetemplate,\
machinedeployment,kubeadmconfigtemplate,machinehealthcheck \
  -n <cluster-namespace> -l cluster.x-k8s.io/cluster-name=<cluster-name> \
  -o yaml > raw-export.yaml
```

Strip `status`, `managedFields`, and controller-added annotations, then split into the per-resource files. Then separately export the autoscaler Deployment (it's in `kube-system`, not namespaced to the cluster).

### New Cluster Workflow

1. Copy an existing cluster directory as template
2. Edit: cluster name, namespace, node counts, flavor, Kubernetes version, CNI choice
3. If OIDC: set flag and OIDC vars in the KubeadmControlPlane spec
4. If GPU: copy `gpu-workers.yaml` template, set GPU flavor + image
5. Encrypt `cloud-config.yaml`: `sops -e cloud-config.plain.yaml > cloud-config.yaml`
6. Add Kustomization entries to `clusters/management/`
7. MR → review → merge → Flux reconciles → cluster provisions

---

## 7. Cluster Lifecycle Operations

### Create
MR adding new directory under `clusters/` + Kustomization entries in `clusters/management/`. Merge = Flux applies = CAPI provisions.

### Scale Workers
Edit `replicas` in `workers.yaml`, open MR, merge.

### Kubernetes Upgrade
Edit `version` in `workers.yaml` and `control-plane.yaml` + update `image.filter.name`, open MR. CAPI does rolling upgrade.

### Add GPU Node Pool
Add `gpu-workers.yaml` to existing cluster directory, add `machineDeployments` entry. MR → merge → GPU pool appears.

### Scale GPU Workers
Edit `replicas` in `gpu-workers.yaml`, MR, merge.

### Delete Cluster
Delete the cluster directory from Git, MR. **Requires second approval.** Merge = Flux prunes all objects = CAPI deprovisions. Autoscaler Kustomization pruned automatically via `prune: true`.

### Emergency Break Glass
Suspend reconciliation without touching Git:
```bash
flux suspend kustomization rdc-workload-1
flux suspend kustomization rdc-workload-1-autoscaler
```
Resume with:
```bash
flux resume kustomization rdc-workload-1
flux resume kustomization rdc-workload-1-autoscaler
```

---

## 8. OIDC Integration

Current OIDC config in `cluster-template.yml.j2` maps directly to `KubeadmControlPlane` spec `apiServer.extraArgs`. Same in fleet repo — static YAML in `control-plane.yaml`. No logic change needed.

The `ClusterRole` and `ClusterRoleBinding` for OIDC (currently applied by `configure-oidc-roles.yml` to the workload cluster) should move to the fleet repo as a `ClusterResourceSet`-delivered ConfigMap, or as workload cluster Flux manifests. They are non-sensitive and don't need SOPS.

OIDC is per-cluster — include/exclude from individual cluster `cluster-resource-set.yaml` based on whether OIDC is enabled.

---

## 9. Management Cluster Bootstrap Changes (nesi-capi-seed)

Minimal changes to `nesi-capi-seed`:

1. **New vars in `servers.yml`** — add `flux_gitlab_token` (GitLab access token), `flux_age_key_path`. Never committed.

2. **New Ansible role or tasks: `roles/flux-operator/`** — runs after management cluster is promoted:
   - `helm install flux-operator` (idempotent)
   - `helm install tf-controller` (idempotent)
   - `kubectl create secret generic flux-gitlab-token` (idempotent via `--dry-run=client | kubectl apply`)
   - `kubectl create secret generic sops-age` (same pattern)
   - `kubectl apply -f flux-instance.yaml`
   - Wait for `FluxInstance` to report `Ready`
   - Apply shared `infrastructure/autoscaler-rbac/` manifests once (ClusterRoles are cluster-scoped)

3. **`flux-instance.yaml` committed to this repo** — Jinja2-parameterised for `flux_fleet_repo_url` and `flux_fleet_branch`.

4. **`ansible-capi-workload` role deprecation path** — the role remains functional for ad-hoc use but is superseded by the Flux workflow for production. The workload role is a **separate repo** (not embedded in nesi-capi-seed) so its deprecation is independent. Document it as "manual bootstrap path" for initial cluster standup before Flux adoption, not for ongoing lifecycle.

No changes needed to Terraform, k3s role, or management promotion tasks.

---

## 10. Migration Plan for Existing Workload Clusters

Phased approach to avoid any downtime:

**Phase 1 — Fleet repo setup (no impact on running clusters)**
- Create `nesi-capi-fleet` GitLab repo at `https://gitlab.com/nesi1/nesi-capi-fleet` with protected `main` branch (require MR + 1 approval, no direct push)
- Export manifests for each existing cluster (CAPI objects + autoscaler Deployment), clean them up, commit to fleet repo
- Commit CNI/CCM/Metrics Server manifests as ConfigMaps in `infrastructure/workload-components/`
- Commit shared autoscaler RBAC in `infrastructure/autoscaler-rbac/`
- Do NOT create Flux Kustomizations yet

**Phase 2 — Install Flux Operator on mgmt cluster**
- Helm install `flux-operator` into `flux-system`
- Apply secrets (`flux-gitlab-token`, `sops-age`) imperatively
- Apply `FluxInstance` CR pointing at `clusters/management` in fleet repo
- Apply shared `infrastructure/autoscaler-rbac/` manifests (ClusterRoles exist cluster-wide)
- Verify operator installs Flux controllers and Kustomization reports `Ready`

**Phase 3 — Migrate secgroups to tf-controller (one cluster at a time)**
- Write Terraform HCL for cluster X secgroups (see `ansible-capi-workload/gitops-migration-plan.md` §4)
- Import existing Ansible-created secgroups into Terraform state: `terraform import openstack_networking_secgroup_v2.controlplane <existing-sg-id>`
- Commit HCL + apply `Terraform` CR to fleet repo; verify tf-controller reconciles without recreating rules
- CAPI Kustomization gets `dependsOn` the Terraform CR — no disruption to running cluster

**Phase 4 — Adopt existing CAPI objects into Flux**
- For cluster X: create Kustomization pointing at its directory
- Flux applies manifests — CAPI sees existing resources, reconciles (no reprovision if spec matches)
- Monitor: `flux get kustomizations`, `kubectl get cluster -A`
- Create autoscaler Kustomization with `dependsOn` — verify autoscaler continues to function
- Repeat for each cluster

**Phase 5 — Retire ansible-capi-workload for production use**
- Mark `ansible-capi-workload` repo as "fleet entry generator" tool only (see its migration plan)
- All new cluster requests go through fleet repo PRs
- Secgroup Ansible tasks superseded by tf-controller; keep Ansible playbooks as reference/fallback only

---

## 11. Open Questions / Decisions Required

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|
| 1 | One fleet repo or per-cluster repos? | Monorepo vs many repos | Monorepo — simpler, fewer GitLab tokens, easier cross-cluster changes |
| 2 | Flux reconcile interval? | 1m / 5m / 10m | 5m for clusters (CAPI operations are slow) |
| 3 | Who can merge to fleet repo? | All team / infra team only | Infra team only; configure GitLab protected branch to require 1 approval; add CODEOWNERS rule requiring 2 approvals for `clusters/*/` deletions |
| 4 | SOPS age key rotation? | Manual / automated | Start manual, document rotation runbook |
| 5 | Flux on workload clusters? | Yes (for GPU app layers) / No | Yes for GPU clusters (NVIDIA Operator complexity); No for standard clusters |
| 6 | Notification on drift/failure? | Flux Alerts → Slack | Recommended — add Flux Alert + Provider resources |
| 7 | `clouds.yaml` long-term? | Hardcoded / OpenStack app credentials | Application credentials per cluster (already best practice) |
| 8 | tf-controller: import existing secgroups or recreate? | `terraform import` / delete + recreate | Import — avoids any networking disruption to running clusters |
| 9 | GPU cluster fleet management? | ClusterResourceSet (limited) / Flux on workload cluster | Flux on workload cluster for GPU clusters only |
| 10 | Autoscaler RBAC (ClusterRoles) — shared or per-cluster? | Shared `infrastructure/` path / per-cluster | Shared — ClusterRoles are cluster-scoped, duplicating per namespace fails |
| 11 | CNI choice per cluster? | Calico default / override per cluster | Default Calico ConfigMap in CRS; GPU clusters can use Cilium (eBPF for better GPU network perf) |

---

## 12. Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Accidental cluster deletion via Git | Low (with branch protection) | High | Require 2 approvals for directory deletions; consider `prune: false` initially |
| SOPS age key loss | Low | High | Back up age key to secure location during bootstrap |
| Flux reconciliation causing unwanted CAPI machine rollouts | Low | Medium | Pin `interval` conservatively; test with non-production cluster first |
| Secrets leak via unencrypted commit | Low (with `.sops.yaml`) | High | Add pre-commit hook to fleet repo blocking unencrypted `cloud-config.yaml` |
| Security group migration breaks cluster networking | Medium | High | Test on isolated cluster; verify CAPO rules match Ansible rules before deleting old groups |
| ORC `remoteGroupRef` missing — cross-group rules unrepresentable | **Confirmed** | High | Addressed by tf-controller interim; contribute `remoteGroupRef` to ORC for long-term removal of Terraform dependency |
| CAPO `managedSecurityGroups` opens 6443 to world | **Confirmed** | Critical | Do not use — this is why custom rules were built. tf-controller maintains the restricted 6443 rule. |
| tf-controller: Terraform state drift if secgroups edited in OpenStack console | Low | Medium | tf-controller reconciles on interval and corrects drift; monitor `terraform plan` output in tf-controller logs |
| tf-controller: secgroup import during migration misses a rule | Low | Medium | Verify all rules present after import with `terraform plan` (should show no changes); compare against Ansible task list |
| ClusterResourceSet `strategy: ApplyOnce` skips CNI updates | Medium | Low | For CNI updates use a new CRS or switch to `strategy: Reconcile` for CCM/metrics; test carefully |
| GPU Operator version mismatch with kernel/driver on node image | Low | High | Pin operator version in fleet repo; test against `rocky-9-containerd-hpc-nvidia-*` image before committing |
| Autoscaler RBAC shared ClusterRoles cause conflicts on update | Low | Medium | Keep RBAC in `infrastructure/autoscaler-rbac/` as a single source; use `kubectl apply` semantics (Flux handles this) |

---

## 13. Tooling Requirements

| Tool | Purpose | Where needed | Already installed? |
|------|---------|-------------|-------------------|
| `helm` | Install Flux Operator | Mgmt bootstrap host | No — add to nesi-capi-seed bootstrap |
| `flux` CLI | Monitor, debug, suspend/resume reconciliation | Operator workstation | No — add to operator workstation |
| `age` / `age-keygen` | SOPS key generation | Operator workstation | No |
| `sops` | Encrypt/decrypt secrets locally | Operator workstation | No |
| GitLab access token | Flux pulls fleet repo from GitLab | nesi-capi-seed `servers.yml` | Needs creating — Project Access Token or Personal Access Token with `read_repository` scope |
| `clusterctl` | One-off manifest export for migration | Operator workstation | Yes (in ansible-capi-workload flow) |
| `openstacksdk` / `openstack` CLI | Look up existing secgroup IDs for Terraform import | Operator workstation | Yes (in ansible-capi-workload venv) |
| tf-controller (Helm chart) | Runs Terraform as Flux-reconciled resource for secgroups | Mgmt cluster | No — add to nesi-capi-seed bootstrap alongside flux-operator |
| `tofu` / `terraform` CLI | Local plan/import during secgroup migration | Operator workstation | No — add to operator workstation |

---

## 14. Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-05 | Flux Operator over `flux bootstrap` | Operator manages Flux lifecycle declaratively; upgrades are PRs not CLI re-runs; no generated unowned manifests in fleet repo |
| 2026-05-05 | ClusterResourceSet for standard cluster in-cluster components | Simpler than Flux-on-workload-cluster; sufficient for CNI, CCM, metrics-server; avoids separate Flux install per standard cluster |
| 2026-05-05 | Flux on workload cluster for GPU clusters only | NVIDIA Operator requires Helm + lifecycle management beyond ClusterResourceSet capability |
| 2026-05-05 | Shared autoscaler RBAC in `infrastructure/` path | ClusterRoles are cluster-scoped; per-cluster duplication would conflict; shared path avoids drift |
| 2026-05-05 | Separate autoscaler Kustomization with `dependsOn` | Autoscaler must start after workload cluster is Ready; `dependsOn` ensures ordering without polling |
| 2026-05-05 | ORC SecurityGroup missing `remoteGroupRef` — root cause identified | ORC's `SecurityGroupRule` spec has no field for cross-group references; linter bans raw UUIDs in spec; correct fix is `remoteGroupRef *KubernetesNameRef` ORC contribution. |
| 2026-05-05 | CAPO `managedSecurityGroups` ruled out | Opens port 6443 to 0.0.0.0/0 by default; cannot remove or restrict that default rule. This is the original reason custom Ansible secgroups were built. |
| 2026-05-05 | tf-controller chosen for secgroup GitOps (interim) | Nodes may be on multiple networks so CIDR approximation is unsafe; tf-controller runs Terraform which supports `remote_group_id` natively; project already uses the OpenStack Terraform provider; state stored in mgmt cluster K8s Secrets. Long-term: ORC `remoteGroupRef` replaces this. |

---

## 16. Disaster Recovery

### The two sources of truth

The fleet repo and Velero serve complementary roles — **both are required** for full recovery. Neither alone is sufficient:

| Source | What it stores | What it cannot recover |
|--------|---------------|----------------------|
| Fleet repo (GitLab) | Desired spec: `Cluster`, `MachineDeployment`, `KubeadmControlPlane`, `OpenStackMachineTemplate`, etc. | Runtime state: which OpenStack VM is which machine |
| Velero backup | Runtime state: `Machine` (with `providerID`), `OpenStackMachine`, `MachineSet`, kubeconfig Secrets, tf-controller Terraform state | Nothing — it has everything |

**The critical object is `Machine.spec.providerID`** — this is the OpenStack VM UUID that CAPI uses to identify an existing VM. It only exists in the management cluster's etcd, never in Git. Without it, CAPI cannot distinguish "this VM already exists" from "provision a new VM" and will create duplicates.

### What Velero must cover

The existing `roles/velero/` in nesi-capi-seed must be configured to back up all of the following:

**Namespaces to include:**

| Namespace | Contains |
|-----------|---------|
| `capi-system` | CAPI core controller state |
| `capi-kubeadm-bootstrap-system` | Kubeadm bootstrap controller state |
| `capi-kubeadm-control-plane-system` | Control plane controller state |
| `capo-system` | OpenStack provider controller state |
| `flux-system` | Flux controllers, SOPS age Secret, GitLab token Secret, tf-controller Terraform state Secrets |
| `kube-system` | Autoscaler Deployments, ServiceAccounts |
| All cluster namespaces | `Cluster`, `Machine`, `OpenStackMachine`, `MachineSet`, kubeconfig Secrets, `<name>-cloud-config` Secrets |

**Critical objects within cluster namespaces:**
- `Machine` — has `spec.providerID: openstack:////<vm-uuid>` ← the most critical field
- `OpenStackMachine` — references actual OpenStack instance
- `MachineSet` — intermediate controller object
- `KubeadmConfig` — per-machine bootstrap config
- `Secret/<name>-kubeconfig` — workload cluster admin kubeconfig
- `Secret/<name>-ca`, `Secret/<name>-etcd`, `Secret/<name>-sa` — cluster PKI

**Critical objects in `flux-system`:**
- `Secret/flux-gitlab-token` — Flux pulls fleet repo with this
- `Secret/sops-age` — Flux decrypts SOPS secrets with this
- `Secret/tfstate-default-<name>-secgroups` — tf-controller Terraform state per cluster (one per cluster, named by the `Terraform` CR name)

> **If Terraform state Secrets are lost:** tf-controller loses track of which OpenStack secgroups it manages and will try to create new ones. See §16.4 for the re-import procedure.

**Recommended Velero backup configuration:**

```yaml
# velero/setup-velero-backup.yml additions
schedule: "0 2 * * *"      # 02:00 daily
ttl: "168h"                 # 7-day retention
includedNamespaces:
  - capi-system
  - capi-kubeadm-bootstrap-system
  - capi-kubeadm-control-plane-system
  - capo-system
  - flux-system
  - kube-system
  - "*"                     # include all cluster namespaces
storageLocation: <external-swift-bucket>   # MUST be external to this OpenStack project
```

Storage location must be **outside the OpenStack project** that hosts the management cluster — if the project itself is impaired, you need the backup accessible from elsewhere (separate Swift container, S3-compatible, or another provider).

### Recovery procedure

**Scenario: Management cluster destroyed or unrecoverable. Workload clusters still running in OpenStack.**

```
Step 1 — Rebuild management cluster infrastructure
  terraform apply    (from nesi-capi-seed/terraform/)
  ansible-playbook setup-infra.yml

Step 2 — Bootstrap k3s + promote to CAPI management cluster
  ansible-playbook ansible-kind.yml
  (Kind bootstrap → clusterctl init → promote to k3s → management cluster ready)

Step 3 — Install Flux Operator + tf-controller (WITHOUT applying FluxInstance yet)
  helm install flux-operator ...
  helm install tf-controller ...
  kubectl create secret generic flux-gitlab-token ...
  kubectl create secret generic sops-age ...
  # DO NOT apply flux-instance.yaml yet — Flux must not reconcile before Velero restore

Step 4 — Restore from Velero backup
  velero restore create mgmt-recovery \
    --from-backup <latest-successful-backup> \
    --wait
  
  # Verify critical objects restored
  kubectl get machine -A                    # must show all machines with providerIDs
  kubectl get cluster -A                    # all clusters present
  kubectl get secret -n flux-system | grep tfstate   # tf state per cluster

Step 5 — Verify Machine providerIDs intact
  kubectl get machine -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.providerID}{"\n"}{end}'
  # Every machine must have a non-empty providerID (openstack:////<uuid>)
  # If any are empty → that machine's VM will be reprovisioned (see §16.3)

Step 6 — Apply FluxInstance → Flux starts reconciling
  kubectl apply -f flux-instance.yaml
  
  # Flux applies fleet repo objects. CAPI controllers see existing Machine objects
  # with providerIDs → recognises existing VMs → no new VMs created.
  
  # Monitor
  flux get kustomizations -A
  kubectl get cluster -A
  kubectl get machine -A

Step 7 — Verify tf-controller secgroup state
  kubectl get terraform -n flux-system
  # All Terraform CRs should reach Ready=True without creating new secgroups
  # Verify: openstack security group list | grep <cluster-name>
  # Should show exactly the same groups as before — no duplicates

Step 8 — Verify workload clusters accessible
  kubectl get secret -n <namespace> <cluster-name>-kubeconfig -o jsonpath='{.data.value}' \
    | base64 -d > /tmp/wl.kubeconfig
  kubectl --kubeconfig /tmp/wl.kubeconfig get nodes
```

**RTO (Recovery Time Objective):** 1–2 hours (mgmt cluster rebuild ~45 min + Velero restore ~15 min + verification ~30 min)  
**RPO (Recovery Point Objective):** up to 24 hours (last successful daily backup) — any CAPI scaling or upgrades performed after the last backup require manual reconciliation

### Handling missing or stale providerIDs

If Velero backup is stale and `Machine` objects are missing or have empty `providerIDs`:

```bash
# List existing OpenStack VMs for a cluster
openstack server list --name <cluster-name> -f json

# For each VM, find its existing Machine object or create one with the correct providerID
# If Machine object exists but providerID is empty, patch it:
kubectl patch machine <machine-name> -n <namespace> \
  --type merge \
  -p '{"spec":{"providerID":"openstack:////<vm-uuid>"}}'

# Then patch the corresponding OpenStackMachine
kubectl patch openstackmachine <machine-name> -n <namespace> \
  --type merge \
  -p '{"spec":{"providerID":"openstack:////<vm-uuid>"}}'
```

If Machine objects are entirely absent (Velero backup too old), **suspend all CAPI Kustomizations immediately**:
```bash
flux suspend kustomization --all
```
Then manually recreate Machine and OpenStackMachine objects with correct providerIDs before resuming. See `ansible-capi-workload/gitops-migration-plan.md §13` for the last-resort manual recovery path.

### Terraform state recovery

If `tfstate-default-<name>-secgroups` Secrets are missing from the restore (tf-controller lost state):

```bash
# tf-controller will try to create new secgroups — suspend it first
flux suspend kustomization <name>-secgroups-tf

# Re-import existing secgroups into a new local Terraform state
cd clusters/<name>/secgroups
terraform init
openstack security group list --project <project> -f json  # get IDs

terraform import \
  -var="cluster_name=<name>" -var="cluster_namespace=<ns>" \
  openstack_networking_secgroup_v2.controlplane <cp-sg-uuid>

terraform import \
  openstack_networking_secgroup_v2.worker <worker-sg-uuid>

# Push state to cluster (tf-controller uses kubernetes backend)
# OR: let tf-controller re-import by setting approvePlan: auto and watching
flux resume kustomization <name>-secgroups-tf
# tf-controller will plan — it should show only rule differences (if any)
# approve the plan if rules are correct
```

### Bootstrap changes to support DR

Add a `dr_mode` flag to `roles/flux-operator/`:

```yaml
# roles/flux-operator/tasks/main.yml
- name: Apply FluxInstance
  kubectl apply -f flux-instance.yaml
  when: not dr_mode | default(false)

- name: DR mode — skip FluxInstance (apply after Velero restore)
  debug:
    msg: "DR mode: apply flux-instance.yaml manually after Velero restore completes"
  when: dr_mode | default(false)
```

During DR: `ansible-playbook setup-infra.yml -e dr_mode=true`  
After Velero restore confirmed: `kubectl apply -f flux-instance.yaml`

### Recovery runbook (quick reference)

```
MANAGEMENT CLUSTER LOSS — WORKLOAD CLUSTERS STILL RUNNING

1. terraform apply (infra)
2. ansible-playbook ansible-kind.yml (bootstrap)
3. helm install flux-operator + tf-controller
4. kubectl create secret flux-gitlab-token + sops-age
5. velero restore create --from-backup <latest> --wait
6. kubectl get machine -A → verify all have providerIDs
7. kubectl apply -f flux-instance.yaml
8. flux get kustomizations -A → wait for all Ready
9. kubectl get terraform -n flux-system → verify no secgroup changes
10. kubectl get cluster -A → all clusters present
11. kubectl --kubeconfig <wl-kubeconfig> get nodes → workload nodes healthy
```

---

## 15. Next Steps

1. **Review and approve both plans** — this plan + `ansible-capi-workload/gitops-migration-plan.md`
2. **Create `nesi-capi-fleet` GitLab repo** at `https://gitlab.com/nesi1/nesi-capi-fleet` — protect `main` branch (require MR + 1 approval, no force push); add CODEOWNERS for cluster deletion approvals
3. **Generate Age key pair** — store private key securely, commit public key to fleet repo `.sops.yaml`
4. **Add `roles/flux-operator/` tasks** to nesi-capi-seed — `helm install flux-operator`, `helm install tf-controller`, secret creation, FluxInstance apply
5. **Generate fleet repo entries** for existing clusters using `ansible-capi-workload` generator playbook (see `ansible-capi-workload/gitops-migration-plan.md`)
6. **Write secgroup Terraform HCL** for each cluster (direct translation from Ansible tasks — see workload migration plan §4)
7. **Commit CNI/CCM/Metrics Server ConfigMaps** to `infrastructure/workload-components/`
8. **Commit shared autoscaler RBAC** to `infrastructure/autoscaler-rbac/`
9. **Test on non-production mgmt cluster** — full bootstrap including flux-operator + tf-controller
10. **Migrate one cluster's secgroups** to tf-controller via `terraform import`; verify no rule changes
11. **Adopt that cluster's CAPI objects** into Flux Kustomization; verify no disruption
12. **Repeat for each cluster** — secgroups first, then CAPI Kustomization
13. **Adopt one GPU cluster** via Flux on workload cluster; verify NVIDIA Operator lifecycle
14. **Write runbooks** for: new cluster creation, GPU cluster creation, scaling, Kubernetes upgrades, Flux version bump, age key rotation, emergency suspend, secgroup import, tf-controller state management
