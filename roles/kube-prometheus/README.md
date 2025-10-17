# Monitoring ansible role

This role takes the [kube-promethueus](https://github.com/prometheus-operator/kube-prometheus) repo and deploys it with some minor modifcations.

These modifcations are to enable remote write and also deploy promtail to the kubernetes cluster

## Variables

The main variables are as follows

`enable_monitoring` this is set to `false` by default, this needs to be set to `true` should you want this role to run.

`kube_config_path` is needed as that is the kubernetes cluster that this role will target. Its current default value is `/tmp/{{ cluster_name }}.kubeconfig` where the variable `cluster_name` is also used to determine the name that should be passed to mimir for metrics

`mimir_domain` this is the URL to send your metrics to from prometheus, it only needs to be the domain `www.example.com` as the role completes the protocol and path. Currently the protocol is set to `HTTP` by default, this can be changed by setting the variable `mimir_protocol`. The current mimir path is also set via the variable `mimir_path` this can be changed, please ensure the path begins with a `/`

`loki_domain` this is the URL to send your logs to from promtail, it only needs to be the domain `www.example.com` as the role completes the protocol and path. Currently the protocol is set to `HTTP` by default, this can be changed by setting the variable `loki_protocol`. The current mimir path is also set via the variable `loki_path` this can be changed, please ensure the path begins with a `/`

`monitoring_username` and `monitoring_password` are the passwords used by both prometheus remote write and promtail remote write. These variables are the default for both the mimir and loki basic auth.

Should you wish to have a different username for mimir and loki then you need to set the respective vars.

`mimir_username` and `mimir_password` for mimir

`loki_username` and `loki_password` for loki

These are currently defaulting like so
```
mimir_username: "{{ monitoring_username }}"
mimir_password: "{{ monitoring_password }}"

loki_username: "{{ monitoring_username }}"
loki_password: "{{ monitoring_password }}"
```