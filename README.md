# Helm Charts for Kubernetes

> A reference implementation of a helm repository for use with flux deployments.

## Vitals

| Info     | Badge                                                 |
|----------|-------------------------------------------------------|
| License  | [![License][license-image]][license-url]              |
| Build    | [![Build][build-image]][build-url]                    |
| FOSSA    | [![FOSSA Status][fossa-badge-image]][fossa-badge-url] |

## Purpose

The general purpose of this repository is to act as a reference implementation of kubernetes infrastructure, application
deployment, management, and monitoring via GitOps workflows. All changes beyond the initial initialization of the
cluster should be performed via GitOps, which provides end-to-end traceability and is entirely reproducible. A cluster
can be destroyed and recreated with minimal intervention and return to a fully usable state.

Some general guidelines:

* full traceability through GitOps workflows
* single source of truth for infrastructure and cluster state
* clusters should be secure by default
* completely self-service
  * use git workflows for change control management, if desired
* use [Cloud Native Computing Foundation (CNCF)][cncf-url] projects where possible

This repository works in combination with the following repositories to meet the aforementioned goals:

| Name                          | Purpose                           | Repository                                             |
|-------------------------------|-----------------------------------|--------------------------------------------------------|
| terraform-org                 | infrastructure as code            | https://github.com/deavon-and-tiffany/terraform-org    |
| helm                          | helm charts                       | https://github.com/deavon-and-tiffany/helm-charts      |
| deployments (this repository) | deployment manifests for clusters | https://github.com/deavon-and-tiffany/kube-deployments |

## Systems

This deployment supports the following systems:

| Name              | Purpose                                   | Documentation                                  |
|------------------ |-------------------------------------------|----------------------------------------------- |
| prometheus (cncf) | metrics collection and time series        | https://www.prometheus.io                      |
| fluent-bit (cncf) | light weight log processor and forwarder  | https://fluentbit.io                           |
| flux (cncf)       | gitops operator for kubernetes            | https://fluxcd.io                              |
| grafana           | metrics visualization                     | https://www.grafana.org                        |
| elasticsearch     | json-based search and analytics (logging) | https://www.elastic.co/products/elasticsearch  |
| kibana            | visualization for elasticsearch (logging) | https://www.elastic.co/products/kibana         |
| minio             | emulation for cloud native object storage | https://min.io                                 |
| istio             | service mesh and gateway                  | https://istio.io                               |
| sealed secrets    | encrypted secrets via gitops              | https://github.com/bitnami-labs/sealed-secrets |
| velero            | kubernetes backup, migration, and restore | https://velero.io                              |

## How it Works

Continuous Delivery of Containers:

![Deployment Pipeline](https://github.com/fluxcd/flux/blob/master/docs/_files/flux-cd-diagram.png?raw=true)

1. Commits are applied to a git repository for an application
2. Application is built within a ci/cd pipeline that publishes images to an OCI-complaint registry, such as
   [Docker Registry][docker-registry-url]
3. The updated image is detected by an agent operating in the cluster (flux)
4. The agent updates the image version within Kubernetes manifests and commits the change to this repository
5. The agent detects any commits made to this repository and applies any modified manifests
6. The agent records the current state using a git tag associated with the commit that was applied.

Continuous Delivery of Helm Charts:

![GitOps Helm Operator][helm-operator-image]

1. Helm chart version is updated in a helm repository, such as our [example repository][helm-repo-url]
2. Change is detected by an agent operating in the cluster (helm-operator)
3. The agent updates the chart version within Kubernetes manifests (HelmRelease) and commits the change to this
   repository
4. The agent detects any commits made to this repository and applies any modified manifests

Copyright (c) 2020. Deavon McCaffery and Tiffany Wang
See [LICENSE][license-url] for details.

Notice:

Logical diagrams are taken from the fabulous [Flux][flux-url] [CNCF][cncf-url] project. Special thanks goes to the
maintainers and contributors.

For a list of all open source dependencies, see [NOTICE][notice-url].

[![FOSSA Status][fossa-scan-image]][fossa-scan-url]

[build-image]: https://github.com/deavon-and-tiffany/helm-charts/workflows/release/badge.svg
[build-url]: https://github.com/deavon-and-tiffany/helm-charts/actions?query=workflow%3Arelease

[cncf-url]: https://cncf.io

[docker-registry-url]: https://hub.docker.com

[flux-url]: https://fluxcd.io
[flux-pipeline-image]: https://github.com/fluxcd/flux/blob/master/docs/_files/flux-cd-diagram.png?raw=true

[fossa-badge-image]: https://app.fossa.com/api/projects/custom%2B14462%2Fref-kube-deploy.svg?type=small
[fossa-badge-url]: https://app.fossa.com/projects/custom%2B14462%2Fref-kube-deploy?ref=badge_small

[fossa-scan-image]: https://app.fossa.com/api/projects/custom%2B14462%2Fref-kube-deploy.svg?type=large
[fossa-scan-url]: https://app.fossa.com/projects/custom%2B14462%2Fref-kube-deploy?ref=badge_large

[license-image]: https://img.shields.io/badge/license-MIT-blue.svg
[license-url]: LICENSE

[notice-url]: NOTICE.md

[helm-operator-image]:https://github.com/fluxcd/helm-operator/blob/master/docs/_files/fluxcd-helm-operator-diagram.png?raw=true
[helm-repo-url]: https://deavon-and-tiffany.gitlab.io/helm-charts/index.yaml

[tiller-sidecar-pr-url]: https://github.com/fluxcd/helm-operator/pull/79
