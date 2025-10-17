https://velero.io/docs/v1.16/basic-install/

https://github.com/vmware-tanzu/velero/releases/download/v1.16.2/velero-v1.16.2-linux-amd64.tar.gz

tar -xvf <RELEASE-TARBALL-NAME>.tar.gz

Move the extracted velero binary to somewhere in your $PATH (/usr/local/bin for most users).



# Initialize velero from scratch:
velero install \
       --provider "community.openstack.org/openstack" \
       --plugins lirt/velero-plugin-for-openstack:v0.6.0 \
       --bucket <SWIFT_CONTAINER_NAME> \
       --no-secret

https://github.com/Lirt/velero-plugin-for-openstack/blob/master/docs/installation-using-cli.md