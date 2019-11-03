#!/usr/bin/env bash

set -euo pipefail
shopt -s globstar

# find the script path
ROOT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

PROJECT_NAMESPACE=${CI_PROJECT_NAMESPACE:-"deavon-and-tiffany"}
PROJECT_NAME=${CI_PROJECT_NAME:="helm"}
ARTIFACTS_PAGES_PATH=$ROOT_PATH/artifacts/pages

# remove artifacts
rm -rf $ARTIFACTS_PAGES_PATH

# create artifacts for pages
mkdir -p $ARTIFACTS_PAGES_PATH

# initialize helm client
helm init --client-only

# find all helm charts
for chart in $ROOT_PATH/charts/**/Chart.yaml; do

    # get the chart dir
    chartdir=$(dirname $chart)

    # lint the chart
    # helm lint $chartdir

    # package the helm chart
    helm package $chartdir --destination $ARTIFACTS_PAGES_PATH
done

# create the index
helm repo index --url https://$PROJECT_NAMESPACE.gitlab.io/$PROJECT_NAME $ARTIFACTS_PAGES_PATH
