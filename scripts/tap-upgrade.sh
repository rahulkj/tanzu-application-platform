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

update_package_repository() {
   export INSTALL_REGISTRY_HOSTNAME="${TAP_INTERNAL_REGISTRY_HOST}"
   export INSTALL_REGISTRY_USERNAME="${TAP_INTERNAL_REGISTRY_USERNAME}"
   export INSTALL_REGISTRY_PASSWORD="${TAP_INTERNAL_REGISTRY_PASSWORD}"
   export TAP_VERSION="${TAP_VERSION}"
   export TAP_REGISTRY_NAME="${TAP_REPOSITORY_NAME}"

   tanzu package repository add "${TAP_REGISTRY_NAME}" \
   --url "${INSTALL_REGISTRY_HOSTNAME}/${TAP_INTERNAL_PROJECT}/${TAP_INTERNAL_TAP_PACKAGES_REPOSITORY}:${TAP_VERSION}" \
   --namespace "${TAP_INSTALL_NAMESPACE}"

   tanzu package repository get "${TAP_REGISTRY_NAME}" --namespace "${TAP_INSTALL_NAMESPACE}"

   tanzu package available list --namespace "${TAP_INSTALL_NAMESPACE}"
}

upgrade_tap() {
   tanzu package installed update tap -p tap.tanzu.vmware.com \
      -v "${TAP_VERSION}" --values-file "${BASE_DIR}/config/${ENV}-tap-values-final.yaml" \
      -n "${TAP_INSTALL_NAMESPACE}"
}

logAndExecute check_for_required_clis
logAndExecute validate_all_arguments
logAndExecute install_tanzu_plugins
logAndExecute prompt_user_kubernetes_login
logAndExecute docker_login_to_tanzunet
logAndExecute copy_images_to_registry
logAndExecute update_package_repository
logAndExecute generate_tap_values
logAndExecute upgrade_tap