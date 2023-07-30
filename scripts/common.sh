#!/bin/bash

DIR=$(dirname "$(realpath ${0})")
BASE_DIR=$(dirname ${DIR})

check_for_required_clis() {
   CLIS=(pivnet kp docker kubectl ytt)
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

   pushd ${TANZU_DOWNLOADS_DIR}
      if [[ "${OS}" == "Linux" ]]; then
         pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version="${TANZU_ESSENTIALS_VERSION}" --glob='tanzu-cluster-essentials-linux-amd64-*.tgz'
      elif [[ "${OS}" == "Darwin" ]]; then
         pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version="${TANZU_ESSENTIALS_VERSION}" --glob='tanzu-cluster-essentials-darwin-amd64-*.tgz'
      fi

      mkdir -p ${TANZU_ESSENTIALS_DIR}
      tar zxvf ${TANZU_DOWNLOADS_DIR}/tanzu-cluster-essentials-* -C ${TANZU_ESSENTIALS_DIR}
      rm ${TANZU_DOWNLOADS_DIR}/tanzu-cluster-essentials-*
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

   pushd ${TANZU_DOWNLOADS_DIR}
      if [[ "${OS}" == "Linux" ]]; then
         pivnet download-product-files --product-slug='tanzu-application-platform' --release-version="${TAP_VERSION}" --glob='tanzu-cli-linux-amd64.*.gz'
      elif [[ "${OS}" == "Darwin" ]]; then
         pivnet download-product-files --product-slug='tanzu-application-platform' --release-version="${TAP_VERSION}" --glob='tanzu-cli-darwin-amd64.*.gz'
      fi
   
      mkdir -p ${TANZU_CLI_DIR}
      tar zxvf ${TANZU_DOWNLOADS_DIR}/tanzu-cli-* -C ${TANZU_CLI_DIR}
      rm ${TANZU_DOWNLOADS_DIR}/tanzu-cli-*
   popd

   tanzu_network_logout
}

install_tanzu_plugins() {
   pushd ${TANZU_CLI_DIR}
      TANZU_CLI_PATH=$(find . -name tanzu-cli-*)
      cp ${TANZU_CLI_PATH} /usr/local/bin/tanzu

      export TANZU_CLI_NO_INIT=true
      tanzu plugin install --group vmware-tap/default:v${TAP_VERSION}
   popd
}

docker_login_to_tanzunet() {
   docker login registry.tanzu.vmware.com -u ${TAP_TANZU_REGISTRY_USERNAME} -p ${TAP_TANZU_REGISTRY_PASSWORD}
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

logAndExecute() {
   echo "**** Executing ${1} ****"
   $1
   echo "**** Done Executing ${1} ****"
   echo
}