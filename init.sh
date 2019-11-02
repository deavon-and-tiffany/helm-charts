#!/usr/bin/env bash

# exit on error, unset variable, or when a pipe fails
set -euo pipefail

# enable globstar
shopt -s globstar

# get the current path
CURRENT_PATH=$(pwd)

# find the script path
ROOT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

CLR_INFO='\033[1;33m'       # BRIGHT YELLOW
CLR_FAILURE='\033[1;31m'    # BRIGHT RED
CLR_SUCCESS='\033[1;32m'    # BRIGHT GREEN
CLR_CLEAR='\033[0m'         # DEFAULT COLOR

BIN_PATH="$ROOT_PATH/.bin"

KUBECTL=$(type -p kubectl)
HELM=$(type -p helm)
KUBESEAL=$(type -p kubeseal)

__cluster_init() {

    # set defaults
    local CLOUD_PLATFORM=${CLOUD_PLATFORM:-""}
    local CONFIGURATION_BUCKET=${CONFIGURATION_BUCKET:-""}
    local CONFIGURATION_BUCKET_REGION=${CONFIGURATION_BUCKET_REGION:-""}
    local KUBE_CONTEXT=${KUBE_CONTEXT:-""}
    local FLUX_GIT_URL=${FLUX_GIT_URL:-""}
    local FLUX_GIT_BRANCH=${FLUX_GIT_BRANCH:-"master"}
    local FLUX_GIT_USERNAME=${FLUX_GIT_USERNAME:-}
    local FLUX_GIT_PASSWORD=${FLUX_GIT_PASSWORD:-}
    local INIT_WORKDIR=$(mktemp -d)

    # continue testing for arguments
    while [[ $# > 0 ]]; do
        case $1 in
            -h|-\?|--help)
                __cluster_init_help
                exit 0
                ;;
            -f|--flux-git-url)
                shift
                FLUX_GIT_URL="${1#https://}"
                ;;
            -u|--flux-git-username)
                shift
                FLUX_GIT_USERNAME=$1
                ;;
            -p|--flux-git-password)
                shift
                FLUX_GIT_PASSWORD=$1
                ;;
            -b|--branch)
                shift
                FLUX_GIT_BRANCH=$1
                ;;
            -p|--platform)
                shift
                CLOUD_PLATFORM=$1
                ;;
            -cb|--configuration-bucket)
                shift
                CONFIGURATION_BUCKET=$1
                ;;
            -c|--context)
                shift
                KUBE_CONTEXT=$1
                ;;
            -r|--region)
                shift
                CONFIGURATION_BUCKET_REGION=$1
                ;;
            -nc|--no-color)
                CLR_INFO=
                CLR_FAILURE=
                CLR_SUCCESS=
                CLR_CLEAR=
                ;;
            -d|--debug)
                set -x
                ;;
            *)
                echo
                __cluster_init_help
                __fail "Invalid argument $1..."
                exit 1
                ;;
        esac
        shift
    done

    # ensure prerequisites
    __prerequisites

    # handle config
    __config

    GLOBAL_PATH=$ROOT_PATH/platform/global
    PLATFORM_PATH=$ROOT_PATH/platform/$CLOUD_PLATFORM
    CLUSTER_PATH=$ROOT_PATH/cluster/$KUBE_CONTEXT
    CHART_PATH=$ROOT_PATH/charts

    # create paths
    mkdir -p $CLUSTER_PATH/namespaces 1>/dev/null 2>&1
    mkdir -p $CLUSTER_PATH/manifests 1>/dev/null 2>&1
    mkdir -p $CLUSTER_PATH/secrets 1>/dev/null 2>&1
    mkdir -p $CLUSTER_PATH/helm 1>/dev/null 2>&1

    # keep paths
    touch $CLUSTER_PATH/namespaces/.gitkeep
    touch $CLUSTER_PATH/manifests/.gitkeep
    touch $CLUSTER_PATH/secrets/.gitkeep
    touch $CLUSTER_PATH/helm/.gitkeep

    # apply all of the cluster namespaces and manifests
    for resource in $GLOBAL_PATH/namespaces/** $GLOBAL_PATH/manifests/** \
        $PLATFORM_PATH/namespaces/** $PLATFORM_PATH/manifests/** \
        $CLUSTER_PATH/namespaces/** $CLUSTER_PATH/manifests/**; do

        # skip directories and marker files
        if [[ -d $resource || "${resource##*.}" != "yaml" ]]; then

            # move on immediately
            continue
        fi

        # apply the resource
        $KUBECTL apply -f "$resource" --wait=true
    done

    # test for sealed secrets backup
    if [ -f "$SEALED_SECRETS_CREDENTIALS" ]; then

        # restore the sealed secrets key
        $KUBECTL apply -f "$SEALED_SECRETS_CREDENTIALS" --wait=true
    fi

    # deploy sealed secrets controller
    $HELM upgrade sealed-secrets $CHART_PATH/stable/sealed-secrets \
        --values=$GLOBAL_PATH/helm/security-system/sealed-secrets.yaml \
        --namespace=security-system --install --wait

    # test for sealed secrets backup
    if [ ! -f "$SEALED_SECRETS_CREDENTIALS" ]; then

        # backup the sealed secrets key
        $KUBECTL --namespace=security-system get secrets \
            --selector=sealedsecrets.bitnami.com/sealed-secrets-key=active --output=yaml > $SEALED_SECRETS_CREDENTIALS
    fi

    # test for sealed secrets certificate
    if [ ! -f "$SEALED_SECRETS_CERTIFICATE" ]; then

        # get the sealed secrets certificate
        $KUBESEAL --controller-namespace=security-system --controller-name=sealed-secrets \
            --fetch-cert > $SEALED_SECRETS_CERTIFICATE
    fi

    # apply all of the cluster secrets
    for resource in $GLOBAL_PATH/secrets/** $PLATFORM_PATH/secrets/** $CLUSTER_PATH/secrets/**; do

        # skip directories
        if [ -d $resource ]; then

            # move on immediately
            continue
        fi

        # apply the resource
        $KUBECTL apply -f "$resource" --wait=true
    done

    # test for flux-git-credentials
    if [ ! $($KUBECTL --namespace gitops-system get secret flux-git-credentials 1>/dev/null 2>&1) ]; then

        # create the flux-git-credentials secret
        $KUBECTL --namespace gitops-system create secret generic flux-git-credentials --dry-run --output=yaml \
            --from-literal="FLUX_GIT_USERNAME=$FLUX_GIT_USERNAME" \
            --from-literal="FLUX_GIT_PASSWORD=$FLUX_GIT_PASSWORD" \
            | $KUBESEAL --format=yaml --cert $SEALED_SECRETS_CERTIFICATE > $INIT_WORKDIR/flux-git-credentials.yaml

        # apply the secret
        $KUBECTL apply -f $INIT_WORKDIR/flux-git-credentials.yaml
    fi

    # deploy flux
    $HELM upgrade flux $CHART_PATH/fluxcd/flux \
        --values=$GLOBAL_PATH/helm/gitops-system/flux.yaml \
        --set=git.url="$FLUX_GIT_URL" \
        --set=git.label="$KUBE_CONTEXT-$FLUX_GIT_BRANCH-flux" \
        --set=git.branch=$FLUX_GIT_BRANCH \
        --namespace=gitops-system --install --wait

    # deploy helm-operator
    # $HELM upgrade helm-operator $CHART_PATH/fluxcd/helm-operator \
    #     --values=$GLOBAL_PATH/helm/gitops-system/helm-operator.yaml \
    #     --namespace=gitops-system --install --wait
}

__prerequisites() {

    # test for required variables
    if [[ -z "${FLUX_GIT_URL:-}" || -z "${FLUX_GIT_USERNAME:-}" || -z "${FLUX_GIT_PASSWORD:-}" ]]; then

        # we error out
        __cluster_init_help
        echo

        if [ -z "${FLUX_GIT_URL:-}" ]; then
            __fail "The --flux-git-url argument or FLUX_GIT_URL environment variable must be set."
        fi

        if [ -z "${FLUX_GIT_USERNAME:-}" ]; then
            __fail "The --flux-git-username argument or FLUX_GIT_USERNAME environment variable must be set."
        fi

        if [ -z "${FLUX_GIT_PASSWORD:-}" ]; then
            __fail "The --flux-git-password argument or FLUX_GIT_PASSWORD environment variable must be set."
        fi

        exit 1
    fi

    # set the flux git url in include credentials
    FLUX_GIT_URL="https://\$(FLUX_GIT_USERNAME):\$(FLUX_GIT_PASSWORD)@$FLUX_GIT_URL"

    # detect kubectl
    if [ -z "${KUBECTL:-}" ]; then

        # warn that this should not be trusted
        __fail "prerequisites" "WARNING: add a verified copy of kubectl to the build agent -- the download signature is not being verified."
        local uname=$(uname | tr '[:upper:]' '[:lower:]')
        local release=${KUBECTL_VERSION:-$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)}

        if [ ! -d "$BIN_PATH" ]; then
            mkdir -p "$BIN_PATH" 1>/dev/null
        fi

        KUBECTL="$BIN_PATH/kubectl"

        curl -L https://storage.googleapis.com/kubernetes-release/release/$release/bin/$uname/amd64/kubectl -o $KUBECTL
        chmod +x $KUBECTL
    fi

    # detect helm
    if [ -z "${HELM:-}" ]; then

        # warn that this should not be trusted
        __fail "prerequisites" "WARNING: add a verified copy of helm to the build agent -- the download signature is not being verified."

        # download and install helm
        curl -L https://git.io/get_helm.sh | bash
        HELM=$(type -p helm)
    fi

    # detect kubeseal
    if [ -z "${KUBESEAL:-}" ]; then

        # warn that this should not be trusted
        __fail "prerequisites" "WARNING: add a verified copy of kubeseal to the build agent -- the download signature is not being verified."

        if [ ! -d "$BIN_PATH" ]; then
            mkdir -p "$BIN_PATH" 1>/dev/null
        fi

        KUBESEAL="$BIN_PATH/kubeseal"
        OS=$(uname -s | tr [:upper:] [:lower:])

        curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.9.3/kubeseal-$OS-amd64 -o $KUBESEAL
        chmod +x $KUBESEAL
    fi

    # emit the versions of kubectl and helm
    echo
    __info "CLIENT CONFIGURATION"
    echo
    echo "helm     : $($HELM version --client --short)"
    echo "kubectl  : $($KUBECTL version --client --short)"
    echo "kubeseal : $($KUBESEAL --version)"
    echo

    # add the bin path to the path
    export PATH="$BIN_PATH:$PATH"
}

__config() {

    # detect if the cloud platform is not set
    if [ -z "${CLOUD_PLATFORM:-}" ]; then

        # determine if the configuration bucket is set
        if [ ! -z "${CONFIGURATION_BUCKET:-}" ]; then

            # we can just ignore the configuration bucket if specified (likely in env-var) -- secret will be
            # save/restored locally
            __fail "init" "WARNING: the supplied configuration bucket ${CONFIGURATION_BUCKET} will be ignored."

            # clear the configuration bucket
            CONFIGURATION_BUCKET=
        fi

        # set the cloud platform to local
        CLOUD_PLATFORM="minikube"

    elif [ -z "${CONFIGURATION_BUCKET:-}" ]; then

            # we need to die here, since we cannot assume that the currently selected context on the local file system
            # matches the expected cloud platform provider
            __fail "init" "ERROR: the configuration bucket is not set for provider ${CLOUD_PLATFORM}."
            exit 1
    fi

    # test if kube config path has not been set
    if [ -z "${KUBE_CONFIG_PATH:-}" ]; then

        # generate a kube config path
        KUBE_CONFIG_PATH="$INIT_WORKDIR/config"

        # save the kube config to the workdir
        $KUBECTL config view --raw > $KUBE_CONFIG_PATH
    fi

    # test for the kube context
    if [ -z "${KUBE_CONTEXT:-}" ]; then

        # set the kube context to the currently configured context
        KUBE_CONTEXT=$($KUBECTL config current-context)
    fi

    # add the config and context to the kubectl cmd
    KUBE_CONFIG="--kubeconfig=$KUBE_CONFIG_PATH --context=$KUBE_CONTEXT"
    KUBECTL="$KUBECTL $KUBE_CONFIG"
    KUBESEAL="$KUBESEAL $KUBE_CONFIG"
    HELM="$HELM --kubeconfig $KUBE_CONFIG_PATH --kube-context $KUBE_CONTEXT"
    SEALED_SECRETS_CREDENTIALS="$INIT_WORKDIR/sealed-secrets.yaml"
    SEALED_SECRETS_CERTIFICATE="$INIT_WORKDIR/sealed-secrets.cert"

    # start tiller and wait 5 seconds
    __info "Starting tiller outside of the cluster (secure)... please wait..."
    tiller --storage=secret &
    local TILLER_JOB_ID=$!

    # kill the tiller job on exit
    trap "kill $TILLER_JOB_ID" EXIT INT TERM
    sleep 2

    # set helm to read from local tiller
    HELM="$HELM --host :44134"

    # ensure connection to cluster and helm tiller
    echo
    __info "SERVER CONFIGURATION"
    echo
    __info "KUBERNETES"
    echo "command : $KUBECTL"
    echo "config  : $KUBE_CONFIG_PATH"
    echo "context : $KUBE_CONTEXT"
    $KUBECTL version --short
    echo
    __info "HELM"
    echo "command : $HELM"
    $HELM version --short
    echo
    __info "SEALED SECRETS"
    echo "credentials : $SEALED_SECRETS_CREDENTIALS"
    echo "certificate : $SEALED_SECRETS_CERTIFICATE"
    echo
}

__info() {
    if [ $# != 1 ]; then
        local SCOPE=$1
        shift
        echo -e "${CLR_INFO}$SCOPE: $@${CLR_CLEAR}"
    else
        echo -e "${CLR_INFO}$@${CLR_CLEAR}"
    fi
}

__success() {
    if [ $# != 1 ]; then
        local SCOPE=$1
        shift
        echo -e "${CLR_SUCCESS}$SCOPE: $@${CLR_CLEAR}"
    else
        echo -e "${CLR_SUCCESS}$@${CLR_CLEAR}"
    fi
}

__fail() {
    if [ $# != 1 ]; then
        local SCOPE=$1
        shift
        echo -e "${CLR_FAILURE}$SCOPE: $@${CLR_CLEAR}"
    else
        echo -e "${CLR_FAILURE}$@${CLR_CLEAR}"
    fi
}

__cluster_init_help() {
    echo
    __success "KUBERNETES CLUSTER INITIALIZATION TOOL"
    echo
    __info "USAGE:"
    echo
    echo "./init.sh [-p|--platform <PLATFORM>] [-b|--configuration-bucket <BUCKET_NAME>] [-c|--context <CONTEXT>] \\"
    echo "   [-f|--flux-git-url <URL>] [-u|--flux-git-username <USERNAME>] [-p|--flux-git-password <PASSWORD>] \\"
    echo "   [-b|--branch <BRANCH_NAME>] [-r|--region <REGION>] [-nc|--no-color] [-d|--debug]"
    echo
    __info "ARGUMENTS:"
    echo
    __info "-f|--flux-git-url <URL>"
    echo "  the flux repository url used to retain the state of the cluster through gitops manifests"
    echo "  ALLOWED VALUES: The URL must not include a protocol. It is assumed to use HTTPS"
    __fail "  REQUIRED, ENVIRONMENT VARIABLE: FLUX_GIT_URL"
    echo
    __info "-u|--flux-git-username <USERNAME>"
    echo "  the username for authenticating to the git repository"
    __fail "  REQUIRED, ENVIRONMENT VARIABLE: FLUX_GIT_USERNAME"
    echo
    __info "-p|--flux-git-password <USERNAME>"
    echo "  the username for authenticating to the git repository"
    echo "  ALLOWED VALUES: While any valid value works, it is recommended to use a long-lived token or service account key"
    __fail "  REQUIRED, ENVIRONMENT VARIABLE: FLUX_GIT_PASSWORD"
    echo
    __info "-b|--branch <BRANCH NAME>"
    echo "  the name of the branch within the specified flux git url where kubernetes manifests are stored"
    echo "  OPTIONAL, DEFAULT: master, ENVIRONMENT VARIABLE: FLUX_GIT_BRANCH"
    echo
    __info "-p|--platform <PLATFORM>"
    echo "  the cloud platform provider that hosts the Kubernetes cluster and configuration bucket"
    echo "  ALLOWED VALUES: gcp, aws, azure, minikube"
    echo "  OPTIONAL, DEFAULT: minikube, ENVIRONMENT VARIABLE: CLOUD_PLATFORM"
    echo
    __info "-cb|--configuration-bucket <BUCKET NAME>"
    echo "  the name of the configuration bucket that contains the kubernetes configuration file used to authenticate to"
    echo "  the cluster"
    echo "  OPTIONAL, ENVIRONMENT VARIABLE: CONFIGURATION_BUCKET"
    echo
    __info "-r|--region <REGION>"
    echo "  the region where the configuration bucket exists, if necessary"
    echo "  OPTIONAL, ENVIRONMENT VARIABLE: CONFIGURATION_BUCKET_REGION"
    echo
    __info "-c|--context <CONTEXT>"
    echo "  the Kubernetes context within the kube configuration file to use to initialize the cluster."
    echo "  OPTIONAL, DEFAULT: <current context>, ENVIRONMENT VARIABLE: KUBE_CONTEXT"
    echo
    __info "-h|-?|--help"
    echo "  print this help -- yay, you already found it!"
    echo
    __info "-nc|--no-color"
    echo "  do not emit color codes when running this script"
    echo
    __info "-d|--debug"
    echo "  print all commands that are executed"
    echo
    __info "NOTES:"
    echo
    echo "The account under which the script is currently executing must have permission to read and write to the"
    echo "configuration bucket. This is used to provision an encryption key for sealed-secrets that is saved and"
    echo "restored from the bucket. This can be accomplished via the metadata endpoint within cloud platform providers,"
    echo "by setting platform-specific environment variables, or using shared credential files."
    echo
    echo "When the cloud platform provider is not set, the currently selected context on the local system will be used"
    echo "to attempt to initialize the cluster. The configuration bucket is NOT used in this mode. The sealed secret key"
    echo "will be backed up to ~/.kube/sealed-secrets/<context-name>.yaml. This should ONLY be used for local "
    echo "development scenarios."
    echo
    echo "The initialization of a cluster intentionally relies on the use of a CNCF sandbox project called Flux, which"
    echo "uses gitops to maintain the state of ALL resouorces within the cluster. A git repository URL must be specified"
    echo "that supports the SSH protocol. (Do not use an HTTPS git url). If the branch argument or FLUX_GIT_BRANCH"
    echo "environment variable is not specified, then the branch will be assumed to be master"
    echo
    __info "EXAMPLES:"
    echo
    __success "# initialize a cluster from the local file system using the default (currently selected) context"
    echo "./init.sh"
    echo "      --flux-git-username org-gitops --flux-git-password some-pat-token \\"
    echo "      --flux-git-url https://github.com/organization/gitops.git"
    echo
    __success "# initialize a cluster from the local file system using the minikube context"
    echo "./init.sh --context minikube"
    echo "      --flux-git-username org-gitops --flux-git-password some-pat-token \\"
    echo "      --flux-git-url https://github.com/organization/gitops.git"
    echo
    __success "# initialize a cluster hosted on aws with configuration from the example-config-bucket using the default context"
    echo "./init.sh --platform aws --configuration-bucket example-config-bucket \\"
    echo "      --flux-git-username org-gitops --flux-git-password some-pat-token \\"
    echo "      --flux-git-url https://github.com/organization/gitops.git"
    echo
    __success "# initialize a cluster hosted on aws with configuration from the example-config-bucket using context"
    __success "# example-kube-dev and kubernetes manifests in the dev branch"
    echo "./init.sh --platform aws --configuration-bucket example-config-bucket --context example-kube-dev \\"
    echo "      --flux-git-username org-gitops --flux-git-password some-pat-token \\"
    echo "      --flux-git-url https://github.com/organization/gitops.git --branch dev"
    echo
    __success "# initialize using environment variables"
    echo "CLOUD_PLATFORM=\"aws\" \\"
    echo "REGION=\"us-west-1\" \\"
    echo "CONFIGURATION_BUCKET=\"example-config-bucket\" \\"
    echo "KUBE_CONTEXT=\"example-kube-dev\" \\"
    echo "FLUX_GIT_USERNAME=\"org-gitops\" \\"
    echo "FLUX_GIT_PASSWORD=\"some-pat-token\" \\"
    echo "FLUX_GIT_URL=\"https://github.com/organization/gitops.git\" \\"
    echo "./init.sh"
}

__cluster_init $@
