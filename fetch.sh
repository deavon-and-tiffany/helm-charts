#!/usr/bin/env bash

# find the script path
ROOT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# emit a warning indicating that this should not be run from CI servers
if [ ! -z "${CI:-}" ]; then
    echo
    echo "WARNING: DO NOT FETCH CHARTS FROM CI SERVERS. THIS SHOULD BE DONE BY DEVOPS AND SUBMITTED WITH A PR/MR."
    echo
    exit 1
fi

# detect whether or not helm is available
if [ ! type helm 1>/dev/null 2>&1 ]; then

    # download and install helm
    curl -L https://git.io/get_helm.sh | bash
fi

# make sure the helm client is initialized
helm init --client-only

# add upstream repositories
helm repo add fluxcd https://charts.fluxcd.io
helm repo add istio https://storage.googleapis.com/istio-release/releases/1.3.3/charts/
helm repo add elastic https://helm.elastic.co

# reset and redownload latest stable charts
rm -rf $ROOT_PATH/charts/stable/*
helm fetch --untar --untardir $ROOT_PATH/charts/stable stable/minio
helm fetch --untar --untardir $ROOT_PATH/charts/stable stable/prometheus
helm fetch --untar --untardir $ROOT_PATH/charts/stable stable/grafana
helm fetch --untar --untardir $ROOT_PATH/charts/stable stable/sealed-secrets
helm fetch --untar --untardir $ROOT_PATH/charts/stable stable/cert-manager
helm fetch --untar --untardir $ROOT_PATH/charts/stable stable/velero
helm fetch --untar --untardir $ROOT_PATH/charts/stable stable/fluent-bit

# reset and redownload flux charts
rm -rf $ROOT_PATH/charts/fluxcd/*
helm fetch --untar --untardir $ROOT_PATH/charts/fluxcd fluxcd/flux
helm fetch --untar --untardir $ROOT_PATH/charts/fluxcd fluxcd/helm-operator

# reset and redownload istio charts
rm -rf $ROOT_PATH/charts/istio/*
helm fetch --untar --untardir $ROOT_PATH/charts/istio istio/istio-init
helm fetch --untar --untardir $ROOT_PATH/charts/istio istio/istio

# reset and redownload elastic charts
rm -rf $ROOT_PATH/charts/elastic/*
helm fetch --untar --untardir $ROOT_PATH/charts/elastic elastic/elasticsearch
helm fetch --untar --untardir $ROOT_PATH/charts/elastic elastic/kibana
