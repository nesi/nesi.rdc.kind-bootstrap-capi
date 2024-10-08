# NeSI RDC Kind Bootstrap CAPI Cluster

This repo contains the ansible scripts to bootstrap a CAPI cluster using kind as the jump point to get it started.

This is based on [Kubernetes Cluster API Provider OpenStack](https://cluster-api-openstack.sigs.k8s.io/) under the getting started link.

You also need to ensure that a CAPI vm image is avaliable, the one used in the NeSI RDC is `ubuntu-2204-kube-v1.26.7`

## Install ansible dependencies

``` { .sh }
ansible-galaxy role install -r requirements.yml -p ansible/roles
ansible-galaxy collection install -r requirements.yml -p ansible/collections
```

## If looking to create ansible managed security groups

It is recommended to use a python virtual environment to contain the required dependencies.

``` { .sh }
# create a virtual environment using the Python3 virtual environment module
python3 -m venv ~/nesi-capi

# activate the virtual environment
source ~/nesi-capi/bin/activate

# install ansible into the venv
pip install ansible ansible-core

# install the openstacksdk
pip install "openstacksdk>=1.0.0"
```

## The breakdown

`terraform`

These are the terraform files used to provision the base kind compute instance to bootstrap the CAPI cluster

Make a copy of `terraform.tfvars.example` and rename it to `terraform.tfvars` and fill in the requried parameters

``` { .sh }
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Inside the `terraform/terraform.tfvars` file is some user configuration required.

``` { .sh }
tenant_name = "NeSI_RDC_PROJECT_NAME"

key_pair    = "NeSI_RDC_KEYPAIR_NAME"
key_file    = "NeSI_RDC_KEYFILE"

kind_flavor_id   = "6b2e76a8-cce0-4175-8160-76e2525d3d3d" # balanced1.2cpu4ram
kind_image_id    = "1a0480d1-55c8-4fd7-8c7a-8c26e52d8cbd" # Ubuntu 22.04
vm_user     = "IMAGE_USER" # Ubuntu is `ubuntu` as an exxample

kind_security_groups = ["6443_Allow_ALL", "SSH Allow All", "default"]
```

`NeSI_RDC_KEYPAIR_NAME` is your `Key Pair` name that is setup in NeSI RDC

`NeSI_RDC_KEYFILE` is the local location for your ssh key

`kind_security_groups` need to allow SSH from your ansible host so that the playbooks can run. Ensure you have the following ones created or are the same ports:

- `6443_Allow_ALL` - Allow 6443 to all
- `SSH Allow All` - Allow 22 to all

---

`ansible`

Make a copy of `group_vars/servers/servers.yml.example` and rename it to `servers.yml` and fill in the requried parameters

``` { .sh }
cp group_vars/servers/servers.yml.example group_vars/servers/servers.yml
```

Inside the `group_vars/servers/servers.yml` file is some user configuration required.

``` { .sh }
---
kubernetes_version: v1.28.5
capi_image_name: rocky-89-kube-v1.28.5

capi_provider_version: v0.8.0

cluster_name: CLUSTER_NAME
cluster_namespace: default

cluster_network: NeSI_RDC_PROJECT_NAME

openstack_ssh_key: NeSI_RDC_KEYPAIR_NAME

cluster_control_plane_count: 1
control_plane_flavor: balanced1.2cpu4ram

cluster_worker_count: 2
worker_flavour: balanced1.2cpu4ram

cluster_node_cidr: 10.30.0.0/24

cluster_pod_cidr: 172.168.0.0/16

bin_dir: /usr/local/bin

clouds_yaml_local_location: ~/.config/openstack/clouds.yaml
```

`CLUSTER_NAME` the name for your management cluster

`NeSI_RDC_PROJECT_NAME` the name of your NeSI RDC project space

`NeSI_RDC_KEYPAIR_NAME` is your `Key Pair` name that is setup in NeSI RDC

There are the following CAPI images available

``` { .sh }
Rocky 9

rocky-9-crio-v1.28.14
rocky-9-crio-v1.29.7
rocky-9-crio-v1.30.5
rocky-9-crio-v1.31.1

```

For management clusters we recommend Kuberenetes version 1.31+

If changing the `capi_image_name` within `servers.yml` please also ensure the `kubernetes_version` matches the same.

Example would be using the image `rocky-9-crio-v1.31.1` would mean the `kubernetes_version` would be `v1.31.1`

---

`clouds.yaml`

You will need to ensure you have downloaded the `clouds.yaml` from the NeSI RDC dashboard and placed it in `~/.config/openstack/clouds.yaml`

It is recommended that you use `Application Credentials` rather then your own credentials.

---

`deployment.sh`

To bootstrap the new CAPI cluster run the command ensuring you supply the following variables as envars

`NeSI_RDC_KEYFILE_LOCATION` location to your local keyfile
`VM_USERNAME` is the username for the kind image

``` { .sh }
export TF_VAR_key_file="NeSI_RDC_KEYFILE_LOCATION" export TF_VAR_vm_user="VM_USERNAME"
./deployment.sh bootstrap
```

This will run 3 playbooks.

`ansible-playbook setup-infra.yml -e operation=create`

This first creates the kind compute instance inside the NeSI RDC

`ansible-playbook -i host.ini ansible-kind.yml -u ubuntu --key-file '~/.ssh/id_flexi'`

Runs the ansible play `ansible-kind.yml` that installs kind onto the compute instance, installs the required dependencies to get it setup as a CAPI cluster, Creates a new workload cluster and promotes that to the management cluster.

You will need to update the values in `group_vars/servers/servers.yaml` with the main value being `clouds_yaml_local_location`

`ansible-playbook setup-infra.yml -e operation=destroy`

The final playbook to run is the terraform destroy, this will tear down the kind instance after the new CAPI Management cluster has been created.

## Notes

If running this outside of the NeSI RDC then you will need to adjust your values based on your cloud proivder. This also all based on the cloud provider running an `openstack` base
