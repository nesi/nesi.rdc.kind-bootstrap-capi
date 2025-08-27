# Velero ansible role

This role will install velero into a specified kubernetes cluster with the openstack plugin

The variable `kubeconfig_path` will be the determinig factor into what kubernetes cluster that is, This role does not fall back onto the default cluster so the variable needs to be defined.

That config location is local to the ansible controller.

## Variables

The main variables within this role are the following

`enable_backup` this is set to `false` by default, this needs to be set to `true` for the role to run

As explained above the `kubeconfig_path` is the kubernetes config file for the cluster that you want to install and setup velero into.

`velero_bucket_name` since we are deploying the openstack plugin we require a swift container name to write the backups too

`clouds_yaml_local_location` this is the `clouds.yaml` file on the local instance that has permissions to create auth tokens for the above bucket. This would be the application credentials for the project where the kubernetes cluster is deployed.


## Backups

Currently this role only sets up a scheduled monthly backup with the backups lasting for 1 year. This may be improved on in the future where we have a variable to set differnt backup schedules, but for now its only 1 a month


## Notes

[Velero documentation](https://velero.io/docs/v1.16/)

[Velero openstack plugin](https://github.com/Lirt/velero-plugin-for-openstack/blob/master/README.md)