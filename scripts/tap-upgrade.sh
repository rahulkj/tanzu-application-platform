#!/bin/bash -e

DIR=$(dirname "$(realpath ${0})")
BASE_DIR=$(dirname ${DIR})

if [[ -z ${ENV} ]]; then
   echo "Please supply the variable ENV and ensure you have the file ${DIR}/ENV-env in this directory. Use the scripts/env template to build your version"
   exit 1
fi

if [[ ! -f ${DIR}/${ENV}-env ]]; then
   echo "Ensure you have the file ${DIR}/${ENV}-env in this directory. Use the scripts/env template to build your version"
   exit 1
fi

source ${DIR}/${ENV}-env

check_for_required_clis() {
   CLIS=(pivnet docker kubectl ytt)
   MISSING=false

   for cli in "${CLIS[@]}"; do
      INSTALLED=$(which $cli)
      if [[ -z $INSTALLED ]]; then
         echo "Missing CLI: $cli"
         MISSING=true
      fi
   done

   if [[ ${MISSING} == true ]]; then 
      echo "Install the required CLI's."
      exit 1
   fi
}

validate_all_arguments() {
   for var in "$@"
   do
      echo "$var"
      if [[ -z ${var} ]]; then
         echo "${var} Not set"
         exit 1
      fi
   done

   if [[ ! -d ${TANZU_CLI_DIR} ]]; then
      echo "Tanzu CLI Directory: ${TANZU_CLI_DIR} does not exist."
      if [[ ! -z "${TANZU_DOWNLOADS_DIR}" ]]; then
         download_tanzu_application_platform
      else
         echo "TANZU_DOWNLOADS_DIR Not set"
         exit 1
      fi
   fi

   if [[ ! -d ${TANZU_ESSENTIALS_DIR} ]]; then
      echo "Tanzu CLI Directory: ${TANZU_ESSENTIALS_DIR} does not exist."
      if [[ ! -z "${TANZU_DOWNLOADS_DIR}" ]]; then
         download_tanzu_essentials
      else
         echo "TANZU_DOWNLOADS_DIR Not set"
         exit 1
      fi      
   fi
}

prompt_user_kubernetes_login() {
   read -p "Have you logged into the kubernetes cluster (yes/no): " RESPONSE
   if [[ (-z "${RESPONSE}") || ("${RESPONSE}" == "no" ) ]]; then
      echo "Cannot proceed as you need to be logged into your k8s cluster"
      exit 1
   fi
}

tanzu_network_login() {
   if [[ ! -z "${TANZU_NETWORK_TOKEN}" ]]; then
      pivnet login --api-token ${TANZU_NETWORK_TOKEN}
   else
      echo "TANZU_NETWORK_TOKEN variable not set"
   fi
}

tanzu_network_logout() {
   pivnet logout
}

download_tanzu_essentials() {
   OS=$(uname)

   tanzu_network_login

   if [[ ! -d ${TANZU_DOWNLOADS_DIR} ]]; then
      echo "Tanzu CLI Directory: ${TANZU_DOWNLOADS_DIR} does not exist."
      mkdir -p ${TANZU_DOWNLOADS_DIR}
   fi

   if [[ "${OS}" == "Linux" ]]; then
      pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version="${TANZU_ESSENTIALS_VERSION}" --glob=tanzu-cluster-essentials-linux-amd64-*.tgz
   elif [[ "${OS}" == "Darwin" ]]; then
      pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version="${TANZU_ESSENTIALS_VERSION}" --glob=tanzu-cluster-essentials-darwin-amd64-*.tgz
   fi
   mv tanzu-cluster-essentials-* ${TANZU_DOWNLOADS_DIR}/

   pushd ${TANZU_DOWNLOADS_DIR}
      mkdir -p ${TANZU_ESSENTIALS_DIR}
      cd ${TANZU_ESSENTIALS_DIR}
         tar zxvf ${TANZU_DOWNLOADS_DIR}/tanzu-cluster-essentials-*
      cd ..
   popd

   tanzu_network_logout
}

download_tanzu_application_platform() {
   OS=$(uname)

   tanzu_network_login

   if [[ ! -d ${TANZU_DOWNLOADS_DIR} ]]; then
      echo "Tanzu CLI Directory: ${TANZU_CLI_DIR} does not exist."
      mkdir -p ${TANZU_DOWNLOADS_DIR}
   fi

   if [[ "${OS}" == "Linux" ]]; then
      pivnet download-product-files --product-slug='tanzu-application-platform' --release-version="${TAP_VERSION}" --glob=tanzu-framework-linux-amd64-*.*.tar
   elif [[ "${OS}" == "Darwin" ]]; then
      pivnet download-product-files --product-slug='tanzu-application-platform' --release-version="${TAP_VERSION}" --glob=tanzu-framework-darwin-amd64-*.*.tar
   fi
   mv tanzu-framework-* ${TANZU_DOWNLOADS_DIR}/
   pushd ${TANZU_DOWNLOADS_DIR}
      tar zxvf ${TANZU_DOWNLOADS_DIR}/tanzu-framework-*
   popd

   tanzu_network_logout
}

docker_login_to_tanzunet() {
   docker login registry.tanzu.vmware.com -u ${TAP_TANZU_REGISTRY_USERNAME} -p ${TAP_TANZU_REGISTRY_PASSWORD}
}

install_tanzu_plugins() {
   pushd ${TANZU_CLI_DIR}
      TANZU_CLI_PATH=$(find . -name tanzu-core*)
      cp ${TANZU_CLI_PATH} /usr/local/bin/tanzu

      export TANZU_CLI_NO_INIT=true
      tanzu plugin install all -l .
   popd
}

copy_images_to_registry() {
   export INSTALL_REGISTRY_HOSTNAME=${TAP_INTERNAL_REGISTRY_HOST}
   export INSTALL_REGISTRY_USERNAME=${TAP_INTERNAL_REGISTRY_USERNAME}
   export INSTALL_REGISTRY_PASSWORD=${TAP_INTERNAL_REGISTRY_PASSWORD}
   export TAP_VERSION=${TAP_VERSION}

   imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:${TAP_VERSION} \
      --to-repo ${INSTALL_REGISTRY_HOSTNAME}/${TAP_INTERNAL_PROJECT}/${TAP_INTERNAL_TAP_PACKAGES_REPOSITORY} \
      --registry-ca-cert-path ${INTERNAL_REGISTRY_CA_CERT_PATH}
}

update_package_repository() {
   export INSTALL_REGISTRY_HOSTNAME=${TAP_INTERNAL_REGISTRY_HOST}
   export INSTALL_REGISTRY_USERNAME=${TAP_INTERNAL_REGISTRY_USERNAME}
   export INSTALL_REGISTRY_PASSWORD=${TAP_INTERNAL_REGISTRY_PASSWORD}
   export TAP_VERSION=${TAP_VERSION}
   export TAP_REGISTRY_NAME=tanzu-tap-repository

   tanzu package repository add ${TAP_REGISTRY_NAME} \
   --url ${INSTALL_REGISTRY_HOSTNAME}/${TAP_INTERNAL_PROJECT}/${TAP_INTERNAL_TAP_PACKAGES_REPOSITORY}:${TAP_VERSION} \
   --namespace tap-install

   tanzu package repository get ${TAP_REGISTRY_NAME} --namespace tap-install

   tanzu package available list --namespace tap-install
}

generate_tap_values() {
   ( echo "cat <<EOF >${BASE_DIR}/config/${ENV}-tap-values.yaml";
      cat ${BASE_DIR}/template/tap-values-template.yaml
      echo "EOF";
   ) >${BASE_DIR}/config/temp.yml
   . ${BASE_DIR}/config/temp.yml

   rm ${BASE_DIR}/config/temp.yml
   
   ytt -f ${BASE_DIR}/config/${ENV}-tap-values.yaml --data-values-env TAP \
      --data-value-file harbor.certificate=${INTERNAL_REGISTRY_CA_CERT_PATH} > ${BASE_DIR}/config/${ENV}-tap-values-final.yaml
}

upgrade_tap() {
   tanzu package installed update tap -p tap.tanzu.vmware.com \
      -v ${TAP_VERSION} --values-file ${BASE_DIR}/config/${ENV}-tap-values-final.yaml \
      -n tap-install
}

check_for_required_clis
validate_all_arguments
prompt_user_kubernetes_login
install_tanzu_plugins
docker_login_to_tanzunet
copy_images_to_registry
update_package_repository
generate_tap_values
upgrade_tap