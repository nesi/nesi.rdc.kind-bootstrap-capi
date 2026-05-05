# Memory

> Chronological action log. Hooks and AI append to this file automatically.
> Old sessions are consolidated by the daemon weekly.

## Session: 2026-05-04 10:33

| Time | Action | File(s) | Outcome | ~Tokens |
|------|--------|---------|---------|--------|
| 10:36 | Created flux-gitops-plan.md | — | ~3209 |

## Session: 2026-05-05

| Time | Action | File(s) | Outcome | ~Tokens |
|------|--------|---------|---------|--------|
| session | Wrote Flux GitOps planning document | flux-gitops-plan.md | Draft plan for review — covers fleet repo structure, SOPS secrets, migration, open questions | ~2500 |
| 10:36 | Session end: 1 writes across 1 files (flux-gitops-plan.md) | 4 reads | ~8687 tok |
| 10:40 | Edited flux-gitops-plan.md | modified sequence() | ~682 |
| 10:41 | Edited flux-gitops-plan.md | modified approach() | ~501 |
| 10:41 | Edited flux-gitops-plan.md | expanded (+7 lines) | ~282 |
| 10:41 | Edited flux-gitops-plan.md | 3→5 lines | ~85 |
| 10:41 | Edited flux-gitops-plan.md | 6→7 lines | ~116 |
| 10:41 | Edited flux-gitops-plan.md | expanded (+8 lines) | ~78 |
| 10:41 | Edited flux-gitops-plan.md | cluster() → protection() | ~248 |
| 10:42 | Session end: 8 writes across 1 files (flux-gitops-plan.md) | 5 reads | ~13829 tok |
| 10:47 | Session end: 8 writes across 1 files (flux-gitops-plan.md) | 5 reads | ~13829 tok |

## Session: 2026-05-05 (mgmt bootstrap + fleet repo)

| Time | Action | File(s) | Outcome | ~Tokens |
|------|--------|---------|---------|--------|
| session | Created roles/flux-operator/ Ansible role | defaults/main.yml, tasks/main.yml, templates/flux-instance.yaml.j2 | Installs flux-operator + tf-controller via Helm, creates secrets, applies FluxInstance | ~600 |
| session | Updated servers.yml + ansible-kind.yml | group_vars/servers/servers.yml, ansible-kind.yml | Added Flux vars, wired flux-operator role after management promotion | ~200 |
| session | Created nesi-capi-fleet/ fleet repo | clusters/management/*, clusters/rdc-workload-1/**, infrastructure/** | Full fleet repo for single workload: secgroups TF, CAPI manifests, autoscaler, CRS, RBAC | ~4000 |

## Session: 2026-05-05 (continuation)

| Time | Action | File(s) | Outcome | ~Tokens |
|------|--------|---------|---------|--------|
| session | Read ansible-capi-workload repo (separate repo) | defaults/main.yml, tasks/main.yml, README.md, cluster-template.yml.j2, configure-install-clusterctl.yml, install-autoscaler.yml, autoscaler-deployment.yml.j2 | Full picture of both repos | ~6000 |
| session | Rewrote flux-gitops-plan.md | flux-gitops-plan.md | Updated plan: two-repo architecture, GPU handling, ClusterResourceSet for in-cluster components, autoscaler on mgmt cluster, security group migration, expanded fleet repo structure | ~8000 |
| session | Identified ORC secgroup blocker + 6443 issue | flux-gitops-plan.md | ORC missing remoteGroupRef; CAPO managed SGs expose 6443 to world — both ruled out | ~3000 |
| session | tf-controller chosen; rewrote secgroup sections; added ansible-capi-workload plan | flux-gitops-plan.md, ansible-capi-workload/gitops-migration-plan.md | Full Terraform HCL for secgroups; fleet repo structure with TF; generator playbook concept; component disposition table | ~6000 |
