#!/bin/bash

DIR=$(dirname "$(realpath ${0})")
BASE_DIR=$(dirname ${DIR})

source ${DIR}/.envrc

tanzu package installed delete tap -n tap-install -y

tanzu package repository delete tanzu-tap-repository -y

tanzu secret registry delete tap-registry -y

kubectl delete ns tap-install

pushd ${TANZU_ESSENTIALS_DIR}
    export INSTALL_BUNDLE=${TANZU_ESSENTIALS_BUNDLE}
    export INSTALL_REGISTRY_HOSTNAME=${TAP_TANZU_REGISTRY_HOST}
    export INSTALL_REGISTRY_USERNAME=${TAP_TANZU_REGISTRY_USERNAME}
    export INSTALL_REGISTRY_PASSWORD=${TAP_TANZU_REGISTRY_PASSWORD}

    ./uninstall.sh --yes
popd

kubectl delete namespace tanzu-cluster-essentials

kubectl delete clusterrolebinding default-tkg-admin-privileged-binding