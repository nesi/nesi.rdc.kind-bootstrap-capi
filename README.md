# NeSI RDC Kind Bootstrap CAPI Cluster

## Overview

This repository provides Ansible automation scripts for bootstrapping a Cluster API (CAPI) management cluster on NeSI RDC (Research and Development Cloud) infrastructure. It uses a temporary Kind (Kubernetes in Docker) instance as the jump point to provision and configure the cluster, leveraging the Kubernetes Cluster API Provider OpenStack.

### Key Features
- Automated CAPI cluster provisioning with OpenStack integration
- Self-hosted management cluster creation
- Built-in monitoring and backup capabilities
- Support for Rocky Linux-based Kubernetes node images
- Compatible with NeSI RDC environment

### Architecture Summary
The workflow creates a temporary VM for Kind, installs CAPI components, provisions the target cluster on OpenStack, promotes it to management status, and tears down the bootstrap infrastructure. Optional roles can add monitoring (kube-prometheus) and backups (Velero).

### Management Support Matrix

The following versions represent recommended pairings between management and workload repositories:

| Management Version | Workload Version |
|--------------------|------------------|
| v0.2.X             | v0.3.X          |
| v0.4.X             | v0.4.X          |

Related repository: [CAPI Workload](https://github.com/lbrick/ansible-capi-workload)

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Extending Features](#extending-features)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Prerequisites

### Required Access
- Active NeSI RDC project with OpenStack API access
- SSH key pair registered in NeSI RDC
- Sufficient compute and network quotas for cluster deployment

### Required Tools
- Ansible 2.15+ and ansible-core
- Terraform 1.0+
- Python 3.8+
- OpenStack SDK (`pip install openstacksdk>=1.0.0`)

### Environment Setup
It is recommended to use a Python virtual environment to isolate dependencies:

```bash
# Create virtual environment
python3 -m venv ~/nesi-capi

# Activate
source ~/nesi-capi/bin/activate

# Install dependencies
pip install ansible ansible-core openstacksdk
```

### Install Ansible Dependencies
```bash
ansible-galaxy role install -r requirements.yml -p ansible/roles
ansible-galaxy collection install -r requirements.yml -p ansible/collections
```

### OpenStack Credentials
- Download `clouds.yaml` from NeSI RDC dashboard
- Place at `~/.config/openstack/clouds.yaml`
- Use Application Credentials rather than personal credentials for security

### Pre-created Security Groups
The deployment requires specific security groups that allow SSH (port 22) and Kubernetes API (port 6443) access from your Ansible host:

- `6443_Allow_ALL` - Open port 6443 inbound
- `SSH Allow All` - Open port 22 inbound
- `default` - Default OpenStack security group

## Quick Start

For experienced users familiar with NeSI RDC:

1. **Setup Credentials:**
   ```bash
   # Place clouds.yaml in ~/.config/openstack/clouds.yaml
   # Ensure SSH key pair is available locally
   ```

2. **Configure Variables:**
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   cp group_vars/servers/servers.yml.example group_vars/servers/servers.yml
   # Edit both files with your NeSI RDC details
   ```

3. **Deploy:**
   ```bash
   export TF_VAR_key_file="/path/to/your/key"
   export TF_VAR_vm_user="ubuntu"  # or appropriate VM user
   ./deployment.sh bootstrap
   ```

The bootstrap process will:
- Create temporary K3s infrastructure
- Install and configure CAPI components
- Provision your management cluster
- Set up optional monitoring and backups
- Clean up temporary resources

Monitor the output for any required interventions or errors.

## Detailed Setup

### 1. Terraform Configuration
Configure your infrastructure settings by creating the Terraform variables file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

**Required Variables:**
- `tenant_name`: Your NeSI RDC project name
- `key_pair`: Name of your SSH key pair in NeSI RDC
- `key_file`: Local path to your SSH private key
- `kind_flavor_id`: VM flavor ID for the Kind instance (e.g., `6b2e76a8-cce0-4175-8160-76e2525d3d3d` for balanced compute)
- `kind_image_id`: Image ID for the Kind instance (e.g., `1a0480d1-55c8-4fd7-8c7a-8c26e52d8cbd` for Ubuntu 22.04)
- `vm_user`: Username for VM SSH (Ubuntu: `ubuntu`)
- `kind_security_groups`: List of security groups as shown above

### 2. Ansible Variables
Configure cluster-specific settings by creating the Ansible variables file:

```bash
cp group_vars/servers/servers.yml.example group_vars/servers/servers.yml
```

**Required Variables:**
- `kubernetes_version`: Target Kubernetes version (e.g., `v1.28.5`)
- `capi_image_name`: Pre-built CAPI image name matching the Kubernetes version
- `capi_provider_version`: Cluster API provider version (e.g., `v0.8.0`)
- `cluster_name`: Unique name for your management cluster
- `cluster_namespace`: Kubernetes namespace (default: `default`)
- `cluster_network`: NeSI RDC project name
- `openstack_ssh_key`: Name of your SSH key pair
- `cluster_control_plane_count`: Number of control plane nodes (recommended: 1 or 3)
- `control_plane_flavor`: VM flavor for control plane nodes
- `cluster_worker_count`: Number of worker nodes
- `worker_flavor`: VM flavor for worker nodes
- `cluster_node_cidr`: IP range for cluster nodes
- `cluster_pod_cidr`: IP range for Kubernetes pods
- `bin_dir`: Directory for CAPI binaries (default: `/usr/local/bin`)
- `clouds_yaml_local_location`: Path to your clouds.yaml file

### Supported Kubernetes Versions and Images

**Available CAPI Images (Rocky 9 base):**
- `rocky-9-containerd-v1.28.14`
- `rocky-9-containerd-v1.29.7`
- `rocky-9-containerd-v1.30.5`
- `rocky-9-containerd-v1.31.1`
- `rocky-9-containerd-v1.31.6`
- `rocky-9-containerd-v1.32.2`
- `rocky-9-containerd-v1.32.7`
- `rocky-9-containerd-v1.33.3` (recommended for management clusters)

**Important Notes:**
- Kubernetes version in `servers.yml` must match the CAPI image version
- For management clusters, use Kubernetes 1.31+ when possible
- Ensure your `capi_image_name` corresponds to the exact Kubernetes version

## Deployment

### Bootstrap Process
The deployment is orchestrated by `./deployment.sh` with three operation modes:

**Bootstrap (Recommended):**
```bash
export TF_VAR_key_file="/path/to/your/key"
export TF_VAR_vm_user="ubuntu"
./deployment.sh bootstrap
```

This performs:
1. Infrastructure provisioning (`setup-infra.yml -e operation=create`)
2. Bootstrap configuration (`ansible-kind.yml`)
3. Infrastructure cleanup (`setup-infra.yml -e operation=destroy`)

**Manual Operations:**
```bash
# Create infrastructure only
./deployment.sh create

# Destroy infrastructure only
./deployment.sh destroy
```

### What Happens During Bootstrap

1. **Infrastructure Creation**: Terraform provisions a temporary VM in NeSI RDC for Kind hosting
2. **Dependency Installation**: The bootstrap VM gets k3s, clusterctl, and CAPI components
3. **Cluster Provisioning**: A target cluster is created on OpenStack via CAPI
4. **Management Promotion**: The new cluster becomes the management cluster
5. **Resource Cleanup**: Temporary bootstrap infrastructure is destroyed

### Running the Bootstrap Playbook Directly
If you need more control:
```bash
# After infrastructure provisioning
ansible-playbook -i host.ini ansible-kind.yml -u ${TF_VAR_vm_user} --key-file "${TF_VAR_key_file}"
```

### Verification
After successful deployment, verify cluster connectivity:
```bash
kubectl --kubeconfig=./path/to/kubeconfig get nodes
```

### Destroying the Cluster
To tear down the entire cluster and infrastructure:
```bash
./deployment.sh destroy
```

## Extending Features

This repository includes optional roles for enhanced functionality:

### Monitoring with kube-prometheus
The `kube-prometheus` role sets up comprehensive monitoring:
- Prometheus for metrics collection
- Grafana for visualization
- Alertmanager for notifications
- Promtail and Loki for log aggregation

See: [kube-prometheus Role README](roles/kube-prometheus/README.md)

### Backup with Velero
The `velero` role enables cluster backup and disaster recovery:
- Automated backup schedules
- Restore capabilities
- Multi-cloud backup targets

See: [Velero Role README](roles/velero/README.md)

## Troubleshooting

### Common Issues

**Ansible Connection Failures:**
- Verify SSH key permissions and path in `TF_VAR_key_file`
- Ensure security groups allow SSH access from your IP
- Confirm VM username in `TF_VAR_vm_user`

**Terraform Provisioning Errors:**
- Check NeSI RDC quotas for compute instances
- Verify OpenStack credentials and permissions
- Confirm flavor and image IDs are valid and available

**CAPI Cluster Creation Failures:**
- Ensure CAPI image matches the specified Kubernetes version
- Verify network settings and security group configurations
- Check node CIDR ranges for conflicts with existing networks

**Port and Access Issues:**
- Confirm ports 22 (SSH) and 6443 (Kubernetes API) are open
- Verify security group rules allow access from your Ansible host

### Logs and Debugging
- Bootstrap playbook logs are output to console
- Kubernetes cluster logs: `kubectl logs -n capi-system`

### Getting Help
- Review NeSI RDC documentation for infrastructure-specific issues
- Check upstream CAPI documentation for cluster creation problems
- Ensure you're using compatible component versions

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit pull requests for review
4. Follow existing code structure and naming conventions

## Notes

This setup is specifically designed for NeSI RDC OpenStack environment. For other cloud providers, adjust variables and configuration accordingly while maintaining the CAPI-based provisioning approach.