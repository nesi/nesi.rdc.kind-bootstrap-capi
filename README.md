# NeSI RDC CAPI Management Cluster Bootstrap

## Overview

Ansible automation for bootstrapping a Cluster API (CAPI) management cluster on NeSI RDC (Research and Development Cloud) OpenStack infrastructure. A temporary k3s instance on a bootstrap VM serves as the pivot point — CAPI is initialized there, the target management cluster is provisioned on OpenStack, then CAPI is moved (`clusterctl move`) to the new cluster and the bootstrap VM is torn down.

After bootstrap, Flux Operator is installed on the management cluster and pointed at the fleet GitOps repository (`reannz-capi-fleet`), from which Flux continuously reconciles workload clusters.

### Architecture

```
Ansible host
  │
  ├── Terraform: provisions bootstrap VM on OpenStack
  │
  └── Ansible → bootstrap VM (k3s):
        ├── Install clusterctl + CAPI (OpenStack provider)
        ├── Generate + apply cluster manifests → provisions management cluster VMs on OpenStack
        ├── clusterctl move → pivots CAPI from k3s to new management cluster
        ├── Install Flux Operator + FluxInstance → points Flux at reannz-capi-fleet
        └── Install tofu-controller (Terraform runner for Flux)
```

Bootstrap VM is destroyed after `clusterctl move`. The management cluster is fully self-managed from that point.

### Supported Kubernetes Versions and Images

**Available CAPI Images (Ubuntu 24 base):**

| Image name | Kubernetes version |
|---|---|
| `ubuntu-24-containerd-v1.35.3` | v1.35.3 |
| `ubuntu-24-containerd-v1.34.x` | v1.34.x |
| `ubuntu-24-containerd-v1.33.x` | v1.33.x |

The `capi_image_name` in `servers.yml` must match the Kubernetes minor version. The `cloud_provider_openstack_version` must also match the Kubernetes minor version (e.g. `1.35` for k8s v1.35.x).

**Note:** Ubuntu 24 runs `apt-get update` on first boot. Expect ~14 minutes before control plane nodes become Ready.

### Management Support Matrix

| Management Version | Workload Version |
|--------------------|-----------------|
| v0.2.X | v0.3.X |
| v0.4.X | v0.4.X |

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Flux GitOps Integration](#flux-gitops-integration)
- [Extending Features](#extending-features)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Access
- Active NeSI RDC project with OpenStack API access
- SSH key pair registered in NeSI RDC
- Sufficient compute and network quotas (3 control plane + 2 worker nodes minimum)
- GitLab Personal Access Token with `read_repository` scope for the fleet repo
- Age private key for SOPS decryption (must correspond to the public key in `.sops.yaml` of the fleet repo)

### Required Tools (on Ansible host)
- Ansible 2.15+ and ansible-core
- Terraform 1.0+
- Python 3.8+
- OpenStack SDK (`pip install openstacksdk>=1.0.0`)

### Environment Setup

```bash
python3 -m venv ~/nesi-capi
source ~/nesi-capi/bin/activate
pip install ansible ansible-core openstacksdk
ansible-galaxy role install -r requirements.yml -p ansible/roles
ansible-galaxy collection install -r requirements.yml -p ansible/collections
```

### OpenStack Credentials
- Download `clouds.yaml` from NeSI RDC dashboard (use Application Credentials, not personal credentials)
- Place at `~/.config/openstack/clouds.yaml` (or a custom path — set `clouds_yaml_local_location` in `servers.yml`)

### Pre-created Security Groups
Required in your NeSI RDC project:

- `6443_Allow_ALL` — port 6443 inbound (Kubernetes API)
- `SSH Allow All` — port 22 inbound
- `default` — default OpenStack security group

## Quick Start

1. **Configure Terraform variables:**
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # Edit: tenant_name, key_pair, key_file, bootstrap VM flavor and image IDs
   ```

2. **Configure Ansible variables:**
   ```bash
   cp group_vars/servers/servers.yml.example group_vars/servers/servers.yml
   # Edit: cluster_name, kubernetes_version, capi_image_name, network settings, Flux variables
   ```

3. **Deploy:**
   ```bash
   export TF_VAR_key_file="/path/to/your/key"
   export TF_VAR_vm_user="ubuntu"
   ./deployment.sh bootstrap
   ```

The bootstrap process will:
1. Create a temporary VM for k3s
2. Install clusterctl and initialize CAPI on k3s
3. Provision the management cluster on OpenStack
4. Move CAPI to the management cluster
5. Install Flux Operator and configure fleet GitOps
6. Destroy the temporary bootstrap VM

The management cluster kubeconfig is written to `<cluster_name>.kubeconfig` in the repo root.

## Configuration

### Terraform Variables (`terraform/terraform.tfvars`)

| Variable | Description |
|---|---|
| `tenant_name` | NeSI RDC project name |
| `key_pair` | SSH key pair name in NeSI RDC |
| `key_file` | Local path to SSH private key |
| `kind_flavor_id` | Bootstrap VM flavor ID |
| `kind_image_id` | Bootstrap VM image ID (Ubuntu 22.04 or 24.04) |
| `vm_user` | SSH username (`ubuntu`) |
| `kind_security_groups` | Security groups for bootstrap VM |

### Ansible Variables (`group_vars/servers/servers.yml`)

**Cluster:**

| Variable | Example | Description |
|---|---|---|
| `kubernetes_version` | `v1.35.3` | Target Kubernetes version |
| `capi_image_name` | `ubuntu-24-containerd-v1.35.3` | CAPI node image — must match k8s version |
| `cloud_provider_openstack_version` | `1.35` | CCM version — must match k8s minor version |
| `k3s_version` | `v1.35.0+k3s1` | k3s version for bootstrap VM |
| `clusterctl_version` | `v1.10.4` | clusterctl CLI version |
| `clusterctl_provider_version` | `v0.12.4` | CAPO (OpenStack provider) version |
| `cluster_name` | `my-mgmt-cluster` | Unique cluster name |
| `cluster_namespace` | `default` | Kubernetes namespace for CAPI objects |
| `cluster_control_plane_count` | `3` | Control plane node count (1 or 3) |
| `control_plane_flavor` | `balanced1.2cpu4ram` | OpenStack flavor for CP nodes |
| `cluster_worker_count` | `2` | Worker node count |
| `worker_flavour` | `balanced1.4cpu8ram` | OpenStack flavor for workers |
| `cluster_node_cidr` | `10.1.0.0/24` | IP range for cluster nodes |
| `cluster_pod_cidr` | `172.16.0.0/16` | IP range for pods |
| `cluster_network` | `NeSI-Training-Prod` | OpenStack network/project name |
| `openstack_ssh_key` | `my-key` | SSH key pair name in OpenStack |

**Flux GitOps:**

| Variable | Description |
|---|---|
| `flux_fleet_repo_url` | HTTPS URL of the fleet GitOps repo |
| `flux_fleet_branch` | Branch to sync (default: `main`) |
| `flux_gitlab_token` | GitLab PAT with `read_repository` scope |
| `flux_age_key_path` | Local path to Age private key (e.g. `~/.config/sops/age.agekey`) |
| `openstack_auth_url` | OpenStack Keystone URL (from `clouds.yaml`) |
| `openstack_app_credential_id` | OpenStack application credential ID |
| `openstack_app_credential_secret` | OpenStack application credential secret |

**Important:** `cluster_namespace` must be a valid RFC 1123 DNS label (lowercase alphanumeric and hyphens only). Use `default` or `nesi-training-prod`, not `NeSI-Training-Prod`.

### OIDC Authentication (Optional)

Set in `servers.yml` to enable OIDC login for the management cluster API:

| Variable | Example | Description |
|---|---|---|
| `kube_oidc_auth` | `true` | Enable OIDC |
| `kube_oidc_hostname` | `iam.nesi.org.nz` | OIDC provider hostname |
| `kube_oidc_url` | `https://iam.nesi.org.nz/realms/admin` | OIDC issuer URL |
| `kube_oidc_client_id` | `nesi-capi-mgmt` | OIDC client ID |
| `kube_oidc_username_claim` | `email` | JWT claim for username |
| `kube_oidc_groups_claim` | `groups` | JWT claim for groups |
| `kube_oidc_groups` | `/kubernetes/administrator` | Group bound to CAPI manager ClusterRole |

## Deployment

```bash
export TF_VAR_key_file="/path/to/your/key"
export TF_VAR_vm_user="ubuntu"

# Full bootstrap (create VM, run playbook, destroy VM):
./deployment.sh bootstrap

# Create VM + run playbook only (leave VM running):
./deployment.sh create

# Destroy bootstrap VM:
./deployment.sh destroy
```

To run the Ansible playbook directly (after `create`):
```bash
ansible-playbook -i host.ini ansible-kind.yml -u ubuntu --key-file "/path/to/key"
```

### Playbook Role Sequence (`ansible-kind.yml`)

| Role | Purpose |
|---|---|
| `ansible-k3s` | Installs k3s on the bootstrap VM |
| `cluster-ctl/cli-install` | Downloads `clusterctl` binary |
| `cluster-ctl/initialize` | Runs `clusterctl init` with OpenStack provider |
| `capi-cluster/workload` | Generates cluster manifests and applies them to k3s, waits for cluster VMs to be Ready |
| `capi-cluster/management` | Runs `clusterctl move` to pivot CAPI to the new cluster, writes kubeconfig |
| `flux-operator` | Installs Flux Operator, creates required secrets, applies FluxInstance and fleet GitRepository, installs tofu-controller |
| `kube-prometheus` | (Optional) Installs Prometheus/Grafana monitoring stack |
| `velero` | (Optional) Installs Velero for cluster backups |

## Flux GitOps Integration

The `flux-operator` role performs:

1. Installs Flux Operator helm chart (`oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator`)
2. Creates secrets on the management cluster:
   - `flux-gitlab-token` — GitLab PAT for pulling the fleet repo
   - `sops-age` — Age private key for decrypting SOPS secrets
   - `openstack-tf-credentials` — OpenStack app credentials for tofu-controller Terraform
3. Applies the `FluxInstance` CR (syncs `clusters/management/` path of the fleet repo)
4. Waits for FluxInstance to become Ready
5. Installs tofu-controller helm chart (`oci://ghcr.io/flux-iac/charts/tofu-controller`) — **must run after FluxInstance is Ready** as it requires Flux CRDs

After the `flux-operator` role completes, Flux begins reconciling the fleet repo and CAPI workload cluster definitions will start provisioning automatically.

## Extending Features

### Monitoring with kube-prometheus
Enable in `servers.yml`:
```yaml
enable_monitoring: true
```

Installs Prometheus, Grafana, Alertmanager, Promtail, and Loki. See [kube-prometheus Role README](roles/kube-prometheus/README.md).

### Backup with Velero
Enable in `servers.yml`:
```yaml
enable_backup: true
```

Installs Velero with S3-compatible backup storage. See [Velero Role README](roles/velero/README.md).

## Troubleshooting

**Control plane nodes not becoming Ready (timeout after ~30 min):**
Ubuntu 24 runs `apt-get update` on first boot (~14 min). Ensure `retries: 60` in `configure-install-clusterctl.yml` (30 min max wait). Check VM console logs in OpenStack Horizon.

**`namespaces "..." not found` when extracting kubeconfig:**
`cluster_namespace` in `servers.yml` does not match where `clusterctl generate` placed the objects. Verify `--target-namespace` is being passed to `clusterctl generate cluster`. Namespace must be lowercase RFC 1123.

**`no matches for kind "OCIRepository"`:**
tofu-controller was installed before FluxInstance became Ready. Flux CRDs (including `OCIRepository`) are installed by the FluxInstance reconcile. tofu-controller must be installed after.

**`Unable to locate any tags: oci://ghcr.io/controlplaneio-fluxcd/flux-operator`:**
Missing `charts/` prefix. Correct path: `oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator`.

**CAPI cluster creation failures:**
- Verify `capi_image_name` matches `kubernetes_version` exactly
- Check `cloud_provider_openstack_version` matches k8s minor version (e.g. `1.35` for v1.35.x)
- Verify OpenStack quotas and network/router IDs in `servers.yml`
- Check CAPO controller logs: `kubectl logs -n capo-system -l control-plane=capo-controller-manager`

**Ansible connection failures:**
- Verify `TF_VAR_key_file` path and permissions
- Confirm `TF_VAR_vm_user` is `ubuntu`
- Check security groups allow SSH from your IP

**Logs and debugging:**
```bash
# CAPI controller logs
kubectl logs -n capi-system -l control-plane=controller-manager
kubectl logs -n capo-system -l control-plane=capo-controller-manager

# Cluster status
kubectl get cluster,machine,openstackcluster -A

# Flux status
kubectl get kustomization,gitrepository -A
flux get all
```
