# anatomy.md

> Auto-maintained by OpenWolf. Last scanned: 2026-05-04T22:41:50.541Z
> Files: 76 tracked | Anatomy hits: 0 | Misses: 0

## ./

- `.gitignore` — Git ignore rules (~64 tok)
- `ansible-kind.yml` (~181 tok)
- `CLAUDE.md` — OpenWolf (~57 tok)
- `clouds.yaml` — nesi-training-prod (~126 tok)
- `deployment.sh` (~150 tok)
- `flux-gitops-plan.md` — Plan: CAPI Workload Clusters via Flux GitOps — updated to cover two-repo architecture, ClusterResourceSet, GPU handling, secgroup migration, autoscaler on mgmt cluster (~7500 tok)
- `host.ini` (~110 tok)
- `internal-capi-mgmt-test.kubeconfig` (~1514 tok)
- `kahu-mgmt-test.kubeconfig` (~1494 tok)
- `rdc-capi-mgmt.kubeconfig` (~1493 tok)
- `README.md` — Project documentation (~3073 tok)
- `setup-infra.yml` (~173 tok)
- `stuff.md` — Initialize velero from scratch: (~151 tok)
- `test-cis-lockdown.kubeconfig` (~1501 tok)
- `updates.yml` — K8s ClusterRoleBinding: capi-cluster-manager-binding (~76 tok)
- `user-oidc-mgmt-test.kubeconfig` (~548 tok)

## .claude/

- `settings.json` (~441 tok)

## .claude/rules/

- `openwolf.md` (~313 tok)

## group_vars/

- `.gitkeep` (~0 tok)

## group_vars/servers/

- `servers.yml` (~517 tok)
- `servers.yml.example` (~460 tok)

## roles/ansible-k3s/defaults/

- `main.yml` (~72 tok)

## roles/ansible-k3s/tasks/

- `install.yml` (~185 tok)
- `main.yml` (~16 tok)

## roles/capi-cluster/management/defaults/

- `main.yml` (~35 tok)

## roles/capi-cluster/management/tasks/

- `main.yml` (~481 tok)

## roles/capi-cluster/workload/defaults/

- `main.yml` (~386 tok)

## roles/capi-cluster/workload/files/

- `create_base64_ca_cert.sh` — you may not use this file except in compliance with the License. (~812 tok)
- `create_base64_yaml.sh` — you may not use this file except in compliance with the License. (~1609 tok)
- `create_cloud_conf.sh` — you may not use this file except in compliance with the License. (~1844 tok)
- `env.rc` — you may not use this file except in compliance with the License. (~2230 tok)

## roles/capi-cluster/workload/tasks/

- `configure-install-clusterctl.yml` (~777 tok)
- `configure-oidc-roles.yml` (~213 tok)
- `install-cloud-manager.yml` (~618 tok)
- `main.yml` (~851 tok)
- `secgroups-control-plane.yml` (~714 tok)
- `secgroups-worker.yml` (~796 tok)

## roles/capi-cluster/workload/templates/

- `cluster-role-binding-oidc.yml.j2` (~72 tok)
- `cluster-role-oidc.yml.j2` (~496 tok)
- `cluster-template.yml.j2` (~1268 tok)
- `openstack-cluster-config.yml.j2` — Values for environment variable substitution (~248 tok)

## roles/cluster-ctl/cli-install/default/

- `main.yml` (~51 tok)

## roles/cluster-ctl/cli-install/tasks/

- `main.yml` (~104 tok)

## roles/cluster-ctl/cli-install/vars/

- `main.yml` (~39 tok)

## roles/cluster-ctl/initialize/default/

- `main.yml` (~58 tok)

## roles/cluster-ctl/initialize/tasks/

- `main.yml` (~118 tok)

## roles/infra/wait-for-hosts/tasks/

- `main.yml` (~148 tok)

## roles/kube-prometheus/

- `README.md` — Project documentation (~537 tok)

## roles/kube-prometheus/defaults/

- `main.yml` (~221 tok)

## roles/kube-prometheus/tasks/

- `main.yml` (~824 tok)

## roles/kube-prometheus/templates/

- `prometheus-user-secret.yml.j2` (~49 tok)
- `promtail.yml.j2` — - # Daemonset.yaml (~915 tok)

## roles/velero/

- `README.md` — Project documentation (~405 tok)

## roles/velero/defaults/

- `main.yml` (~187 tok)

## roles/velero/tasks/

- `check-velero-cli.yml` (~174 tok)
- `initialize-velero.yml` (~567 tok)
- `install-velero-cli.yml` (~246 tok)
- `main.yml` (~434 tok)
- `setup-velero-backup.yml` (~397 tok)

## roles/velero/templates/

- `openstack-credentials.yml.j2` (~42 tok)

## terraform/

- `.terraform.lock.hcl` — This file is maintained automatically by "terraform init". (~920 tok)
- `clouds.yaml` — nesi-training-prod (~126 tok)
- `main.tf` — Create services instance (~512 tok)
- `provider.tf` — Define required providers (~82 tok)
- `terraform.tfstate` (~1818 tok)
- `terraform.tfstate.backup` (~870 tok)
- `terraform.tfvars` (~87 tok)
- `terraform.tfvars.example` (~95 tok)
- `variables.tf` (~266 tok)

## terraform/.terraform/providers/registry.terraform.io/hashicorp/local/2.5.3/linux_amd64/

- `LICENSE.txt` (~4191 tok)

## terraform/.terraform/providers/registry.terraform.io/hashicorp/null/3.2.4/linux_amd64/

- `LICENSE.txt` (~4191 tok)

## terraform/.terraform/providers/registry.terraform.io/terraform-provider-openstack/openstack/1.51.1/linux_amd64/

- `CHANGELOG.md` — Change log (~27400 tok)
- `LICENSE` — Project license (~4460 tok)
- `README.md` — Project documentation (~670 tok)

## terraform/templates/

- `all-hosts.tpl` (~60 tok)
- `host.ini.tpl` (~62 tok)
