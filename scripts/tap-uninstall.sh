#!/bin/bash -e

DIR=$(dirname "$(realpath ${0})")
BASE_DIR=$(dirname ${DIR})

source ${DIR}/common.sh

if [[ -z ${ENV} ]]; then
   echo "Please supply the variable ENV and ensure you have the file ${DIR}/ENV-env in this directory. Use the scripts/env template to build your version"
   exit 1
fi

if [[ ! -f ${DIR}/${ENV}-env ]]; then
   echo "Ensure you have the file ${DIR}/${ENV}-env in this directory. Use the scripts/env template to build your version"
   exit 1
fi

source ${DIR}/${ENV}-env

uninstall_tap() {
    tanzu package installed delete tap -n "${TAP_INSTALL_NAMESPACE}" -y

    tanzu package repository delete "${TAP_FULL_DEPS_REPOSITORY_NAME}" -n "${TAP_INSTALL_NAMESPACE}" -y

    tanzu package repository delete "${TAP_REPOSITORY_NAME}" -n "${TAP_INSTALL_NAMESPACE}" -y

    tanzu secret registry delete "${TAP_REGISTRY_SECRET_NAME}" -n "${TAP_INSTALL_NAMESPACE}" -y

    kubectl delete ns "${TAP_INSTALL_NAMESPACE}"
}

uninstall_tkg_essentials() {
    pushd ${TANZU_ESSENTIALS_DIR}
        export INSTALL_BUNDLE="${TANZU_NETWORK_ESSENTIALS_BUNDLE}"
        export INSTALL_REGISTRY_HOSTNAME="${TAP_TANZU_NETWORK_REGISTRY_HOST}"
        export INSTALL_REGISTRY_USERNAME="${TAP_TANZU_NETWORK_REGISTRY_USERNAME}"
        export INSTALL_REGISTRY_PASSWORD="${TAP_TANZU_NETWORK_REGISTRY_PASSWORD}"

        ./uninstall.sh --yes
    popd

    kubectl delete namespace tanzu-cluster-essentials
}

delete_psp_for_tkgs() {
    set +e
    CRB_EXISTS=$(kubectl get clusterrolebindings.rbac.authorization.k8s.io | grep "${CLUSTER_ROLE_BINDING_NAME}")
    set -e

    if [[ ! -z "${CRB_EXISTS}" ]]; then
        kubectl delete clusterrolebinding default-tkg-admin-privileged-binding
    fi
}


logAndExecute prompt_user_kubernetes_login
logAndExecute uninstall_tap
logAndExecute uninstall_tkg_essentials
logAndExecute delete_psp_for_tkgs