#!/usr/bin/env sh

set -eu

# emit a warning indicating that this should not be run from CI servers
if [ -n "${CI:-}" ]; then
    echo
    echo "WARNING: DO NOT FETCH CHARTS FROM CI SERVERS. THIS SHOULD BE DONE BY DEVOPS AND SUBMITTED WITH A PR."
    echo
    exit 1
fi

# detect whether or not helm is available
if ! command -v helm 1>/dev/null 2>&1; then

    # download and install helm
    curl -L https://git.io/get_helm.sh | bash
fi

rm -rf ./charts/*

# cert manager
helm repo add jetstack https://charts.jetstack.io
helm fetch --untar --untardir ./charts jetstack/cert-manager
helm fetch --untar --untardir ./charts jetstack/cert-manager-istio-csr
helm fetch --untar --untardir ./charts jetstack/cert-manager-csi-driver
helm fetch --untar --untardir ./charts jetstack/cert-manager-approver-policy

# prometheus
helm repo add prometheus https://prometheus-community.github.io/helm-charts
helm fetch --untar --untardir ./charts prometheus/prometheus
helm fetch --untar --untardir ./charts prometheus/prometheus-elasticsearch-exporter

# grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm fetch --untar --untardir ./charts grafana/grafana

# istio
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm fetch --untar --untardir ./charts istio/base
helm fetch --untar --untardir ./charts istio/istiod
helm fetch --untar --untardir ./charts istio/gateway
helm fetch --untar --untardir ./charts istio/cni

# elastic
helm repo add elastic https://helm.elastic.co
helm fetch --untar --untardir ./charts elastic/elasticsearch
helm fetch --untar --untardir ./charts elastic/kibana

# flux
helm repo add flux https://fluxcd-community.github.io/helm-charts
helm fetch --untar --untardir ./charts flux/flux2
helm fetch --untar --untardir ./charts flux/flux2-notification
helm fetch --untar --untardir ./charts flux/flux2-sync

# flagger
helm repo add flagger https://flagger.app
helm fetch --untar --untardir ./charts flagger/flagger

# find charts -depth 2 -min -name 'Chart.yaml' -print0 | \
#     xargs -0 -I {} echo helm template "$(basename {})"

# find ./charts/ -name 'Chart.yaml' -print0 \
#     xargs -I {} helm template "$(basename {})" | yq --no-doc eval-all '.. | select(has("image")) | .image' -
