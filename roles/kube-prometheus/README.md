# Monitoring ansible role

This role takes the [kube-promethueus](https://github.com/prometheus-operator/kube-prometheus) repo and deploys it with some minor modifcations.

These modifcations are to enable remote write and also deploy promtail to the kubernetes cluster

## Variables

The main variables are as follows

`enable_monitoring` this is set to `false` by default, this needs to be set to `true` should you want this role to run.

`mimir_endpoint` this is the URL to send your metrics to from prometheus, it only needs to be the domain `www.example.com` as the role completes the protocol and path. Currently the protocol is set to `HTTP` by default.

`loki_endpoint` this is the URL to send your logs to from promtail, it only needs to be the domain `www.example.com` as the role completes the protocol and path. Currently the protocol is set to `HTTP` by default.

`monitoring_username` and `monitoring_password` are the passwords used by both prometheus remote write and promtail remote write, this role currently does not seperate the 2 different endpoints with differnt users at this time.
