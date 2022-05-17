#!/bin/bash -e

DIR=$(dirname "$(realpath ${0})")
BASE_DIR=$(dirname ${DIR})

if [[ -f "${DIR}/env" ]]; then
    echo "env file exists"
    source ${DIR}/env
elif [[ -f "${DIR}/.envrc" ]]; then
    echo ".envrc file found"
    source ${DIR}/.envrc
else
    echo "could not find the env or .envrc file, exiting"
    exit 1
fi

uninstall_tap() {
    tanzu package installed delete tap -n tap-install -y

    tanzu package repository delete tanzu-tap-repository -y

    tanzu secret registry delete tap-registry -y

    kubectl delete ns tap-install
}

uninstall_tkg_essentials() {
    pushd ${TANZU_ESSENTIALS_DIR}
        export INSTALL_BUNDLE=${TANZU_ESSENTIALS_BUNDLE}
        export INSTALL_REGISTRY_HOSTNAME=${TAP_TANZU_REGISTRY_HOST}
        export INSTALL_REGISTRY_USERNAME=${TAP_TANZU_REGISTRY_USERNAME}
        export INSTALL_REGISTRY_PASSWORD=${TAP_TANZU_REGISTRY_PASSWORD}

        ./uninstall.sh --yes
    popd

    kubectl delete namespace tanzu-cluster-essentials
}

delete_psp_for_tkgs() {
    kubectl delete clusterrolebinding default-tkg-admin-privileged-binding
}

uninstall_tap
uninstall_tkg_essentials
delete_psp_for_tkgs