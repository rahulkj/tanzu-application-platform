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

install_tanzu_plugins() {
   pushd ${TANZU_CLI_DIR}
      export TANZU_CLI_NO_INIT=true
      tanzu plugin install all -l .
   popd
}

docker_login_to_tanzunet() {
   docker login registry.tanzu.vmware.com -u ${TAP_TANZU_REGISTRY_USERNAME} -p ${TAP_TANZU_REGISTRY_PASSWORD}
}

configure_psp_for_tkgs(){
   kubectl create clusterrolebinding default-tkg-admin-privileged-binding --clusterrole=psp:vmware-system-privileged --group=system:authenticated
}

install_tkg_essentials() {
   kubectl create namespace kapp-controller

   kubectl create secret generic kapp-controller-config \
      --namespace kapp-controller \
      --from-file caCerts=${HARBOR_CA_CERT_PATH}

   pushd ${TANZU_ESSENTIALS_DIR}
      export INSTALL_BUNDLE=${TANZU_ESSENTIALS_BUNDLE}
      export INSTALL_REGISTRY_HOSTNAME=${TAP_TANZU_REGISTRY_HOST}
      export INSTALL_REGISTRY_USERNAME=${TAP_TANZU_REGISTRY_USERNAME}
      export INSTALL_REGISTRY_PASSWORD=${TAP_TANZU_REGISTRY_PASSWORD}

      ./install.sh --yes
   popd
}

copy_images_to_registry() {
   export INSTALL_REGISTRY_USERNAME=${TAP_HARBOR_REGISTRY_USERNAME}
   export INSTALL_REGISTRY_PASSWORD=${TAP_HARBOR_REGISTRY_PASSWORD}
   export INSTALL_REGISTRY_HOSTNAME=${TAP_HARBOR_REGISTRY_HOST}
   export TAP_VERSION=${TAP_VERSION}

   imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:${TAP_VERSION} \
      --to-repo ${INSTALL_REGISTRY_HOSTNAME}/${TAP_HARBOR_PROJECT}/${TAP_HARBOR_TAP_PACKAGES_REPOSITORY} \
      --registry-ca-cert-path ${HARBOR_CA_CERT_PATH}
}

stage_for_tap_install() {
   export INSTALL_REGISTRY_USERNAME=${TAP_HARBOR_REGISTRY_USERNAME}
   export INSTALL_REGISTRY_PASSWORD=${TAP_HARBOR_REGISTRY_PASSWORD}
   export INSTALL_REGISTRY_HOSTNAME=${TAP_HARBOR_REGISTRY_HOST}
   export TAP_VERSION=${TAP_VERSION}

   kubectl create ns tap-install

   tanzu secret registry add tap-registry \
   --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} \
   --server ${INSTALL_REGISTRY_HOSTNAME} \
   --export-to-all-namespaces --yes --namespace tap-install

   tanzu package repository add tanzu-tap-repository \
   --url ${INSTALL_REGISTRY_HOSTNAME}/${TAP_HARBOR_PROJECT}/${TAP_HARBOR_TAP_PACKAGES_REPOSITORY}:${TAP_VERSION} \
   --namespace tap-install

   tanzu package repository get tanzu-tap-repository --namespace tap-install

   tanzu package available list --namespace tap-install

   ytt -f ${BASE_DIR}/template/tap-values-template.yaml --data-values-env TAP \
      --data-value-file harbor.certificate=${HARBOR_CA_CERT_PATH} > ${BASE_DIR}/config/tap-values.yaml
}

install_tap() {
   tanzu package install tap -p tap.tanzu.vmware.com \
      -v ${TAP_VERSION} --values-file ${BASE_DIR}/config/tap-values.yaml \
      -n tap-install
}

install_tanzu_plugins
docker_login_to_tanzunet
configure_psp_for_tkgs
install_tkg_essentials
copy_images_to_registry
stage_for_tap_install
install_tap