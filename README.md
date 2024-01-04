# NeSI RDC Kind Bootstrap CAPI Cluster

This repo contains the ansible scripts to bootstrap a CAPI cluster using kind as the jump point to get it started.

This is based on [Kubernetes Cluster API Provider OpenStack](https://cluster-api-openstack.sigs.k8s.io/) under the getting started link.

You also need to ensure that a CAPI vm image is avaliable, the one used in the NeSI RDC is `ubuntu-2204-kube-v1.26.7`

## The breakdown

`terraform`

These are the terraform files used to provision the base kind compute instance to bootstrap the CAPI cluster

Make a copy of `terraform.tfvars.example` and rename it to `terraform.tfvars` and fill in the requried parameters

```
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Inside the `terraform/terraform.tfvars` file is some user configuration required.

```
tenant_name = "NeSI_RDC_PROJECT_NAME"

key_pair    = "NeSI_RDC_KEYPAIR_NAME"
key_file    = "NeSI_RDC_KEYFILE"

kind_flavor_id   = "6b2e76a8-cce0-4175-8160-76e2525d3d3d" # balanced1.2cpu4ram
kind_image_id    = "1a0480d1-55c8-4fd7-8c7a-8c26e52d8cbd" # Ubuntu 22.04
vm_user     = "IMAGE_USER" # Ubuntu is `ubuntu` as an exxample

kind_security_groups = ["6443_Allow_ALL", "SSH Allow All", "default"]
```

where

- `NeSI_RDC_KEYPAIR_NAME` is your `Key Pair` name that is setup in NeSI RDC
- `NeSI_RDC_KEYFILE` is the local location for your ssh key

`kind_security_groups` need to allow SSH from your ansible host so that the playbooks can run. Ensure you have the following ones created or are the same ports:
- `6443_Allow_ALL` - Allow 6443 to all
- `SSH Allow All` - Allow 22 to all

`clouds.yaml`

You will need to ensure you have downloaded the `clouds.yaml` from the NeSI RDC dashboard and placed it in `~/.config/openstack/clouds.yaml`

It is recommended that you use `Application Credentials` rather then your own credentials.

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
