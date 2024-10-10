#!/bin/bash

DIR=$(dirname "$(realpath ${0})")
BASE_DIR=$(dirname ${DIR})

check_for_required_clis() {
   CLIS=(pivnet kp docker kubectl ytt)
   MISSING=false

   for cli in "${CLIS[@]}"; do
      INSTALLED=$(which $cli)
      if [[ -z "${INSTALLED}" ]]; then
         echo "Missing CLI: ${cli}"
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
      if [[ -z "${var}" ]]; then
         echo "${var} Not set"
         exit 1
      fi
   done

   if [[ ! -z "${TANZU_DOWNLOADS_DIR}" ]]; then
      create_downloads_folder
   else
      echo "TANZU_DOWNLOADS_DIR variable is not set"
      exit 1
   fi

   if [[ ! -z "${TANZU_CLI_DIR}" ]]; then
      download_tanzu_application_platform
   else
      echo "TANZU_CLI_DIR variable is not set"
      exit 1
   fi

   if [[ ! -z "${TANZU_ESSENTIALS_DIR}" ]]; then
      download_tanzu_essentials
   else
      echo "TANZU_ESSENTIALS_DIR variable is not set"
      exit 1
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
      pivnet login --api-token "${TANZU_NETWORK_TOKEN}"
   else
      echo "TANZU_NETWORK_TOKEN variable not set"
   fi
}

tanzu_network_logout() {
   pivnet logout
}

create_downloads_folder() {
   if [[ ! -d "${TANZU_DOWNLOADS_DIR}" ]]; then
      echo "Tanzu downloads directory: ${TANZU_DOWNLOADS_DIR} does not exist."
   else
      echo "Tanzu downloads directory: ${TANZU_DOWNLOADS_DIR} exists, and will be deleted"
   fi

   mkdir -p ${TANZU_DOWNLOADS_DIR}
}

download_tanzu_essentials() {
   OS=$(uname)

   tanzu_network_login

   if [[ ! -d "${TANZU_ESSENTIALS_DIR}" ]]; then
      echo "Tanzu CLI Directory: ${TANZU_ESSENTIALS_DIR} does not exist."
   else
      echo "Tanzu CLI Directory: ${TANZU_ESSENTIALS_DIR} exists, hence deleting it"
      rm -rf "${TANZU_ESSENTIALS_DIR}"
   fi

   pushd "${TANZU_DOWNLOADS_DIR}"
      if [[ "${OS}" == "Linux" ]]; then
         pivnet download-product-files \
         --product-slug='tanzu-cluster-essentials' \
         --release-version="${TANZU_ESSENTIALS_VERSION}" \
         --glob='tanzu-cluster-essentials-linux-amd64-*.tgz'
      elif [[ "${OS}" == "Darwin" ]]; then
         pivnet download-product-files \
         --product-slug='tanzu-cluster-essentials' \
         --release-version="${TANZU_ESSENTIALS_VERSION}" \
         --glob='tanzu-cluster-essentials-darwin-amd64-*.tgz'
      fi

      mkdir -p "${TANZU_ESSENTIALS_DIR}"
      TAR_FILE=$(find . -name 'tanzu-cluster-essentials-*.tgz')
      tar zxvf "${TAR_FILE}" -C "${TANZU_ESSENTIALS_DIR}"
      rm "${TAR_FILE}"
   popd

   tanzu_network_logout
}

download_tanzu_application_platform() {
   OS=$(uname)

   tanzu_network_login

   if [[ ! -d "${TANZU_CLI_DIR}" ]]; then
      echo "Tanzu CLI Directory: ${TANZU_CLI_DIR} does not exist."
   else
      echo "Tanzu CLI Directory: ${TANZU_CLI_DIR} exists ,so deleting it"
      rm -rf "${TANZU_CLI_DIR}"
   fi

   pushd "${TANZU_DOWNLOADS_DIR}"
      if [[ "${OS}" == "Linux" ]]; then
         pivnet download-product-files \
         --product-slug='tanzu-application-platform' \
         --release-version="${TAP_VERSION}" \
         --glob='tanzu-cli-linux-amd64*.*.gz'
      elif [[ "${OS}" == "Darwin" ]]; then
         pivnet download-product-files \
         --product-slug='tanzu-application-platform' \
         --release-version="${TAP_VERSION}" \
         --glob='tanzu-cli-darwin-amd64*.*.gz'
      fi
   
      mkdir -p "${TANZU_CLI_DIR}"
      TAR_FILE=$(find . -name 'tanzu-cli-*.tar.gz')
      tar zxvf "${TAR_FILE}" -C "${TANZU_CLI_DIR}"
      rm "${TAR_FILE}"
   popd

   tanzu_network_logout
}

install_tanzu_plugins() {
   pushd "${TANZU_CLI_DIR}"
      TANZU_CLI_PATH=$(find . -name tanzu-cli-*)
      cp "${TANZU_CLI_PATH}" /usr/local/bin/tanzu

      export TANZU_CLI_NO_INIT=true
      tanzu plugin install --group vmware-tap/default:v${TAP_VERSION}
   popd
}

docker_login_to_tanzunet() {
   docker login "${TAP_TANZU_NETWORK_REGISTRY_HOST}" -u "${TAP_TANZU_NETWORK_REGISTRY_USERNAME}" -p "${TAP_TANZU_NETWORK_REGISTRY_PASSWORD}"
}

docker_login_to_internal_registry() {
   docker login "${TAP_INTERNAL_REGISTRY_HOST}" -u "${TAP_INTERNAL_REGISTRY_USERNAME}" -p "${TAP_INTERNAL_REGISTRY_PASSWORD}"
}

copy_images_to_registry() {
   export INSTALL_REGISTRY_HOSTNAME="${TAP_INTERNAL_REGISTRY_HOST}"
   export INSTALL_REGISTRY_USERNAME="${TAP_INTERNAL_REGISTRY_USERNAME}"
   export INSTALL_REGISTRY_PASSWORD="${TAP_INTERNAL_REGISTRY_PASSWORD}"
   export TAP_VERSION="${TAP_VERSION}"

   # imgpkg copy -b ${TAP_TANZU_NETWORK_REGISTRY_HOST}/${TAP_TANZU_NETWORK_PROJECT}/${TAP_TANZU_NETWORK_PACKAGES_REPOSITORY_NAME}:${TAP_VERSION} \
   #    --to-tar tap-packages-${TAP_VERSION}.tar \
   #    --include-non-distributable-layers

   # imgpkg copy \
   #    --tar product/tap-packages-$TAP_VERSION.tar \
   #    --to-repo "${INSTALL_REGISTRY_HOSTNAME}/${TAP_INTERNAL_REGISTRY_PROJECT}/${TAP_INTERNAL_REGISTRY_TAP_PACKAGES_REPOSITORY}" \
   #    --include-non-distributable-layers \
   #    --registry-ca-cert-path ${TAP_INTERNAL_REGISTRY_CA_CERT_PATH}

   imgpkg copy -b ${TAP_TANZU_NETWORK_REGISTRY_HOST}/${TAP_TANZU_NETWORK_PROJECT}/${TAP_TANZU_NETWORK_PACKAGES_REPOSITORY_NAME}:${TAP_VERSION} \
      --to-repo "${INSTALL_REGISTRY_HOSTNAME}/${TAP_INTERNAL_REGISTRY_PROJECT}/${TAP_INTERNAL_REGISTRY_TAP_PACKAGES_REPOSITORY}" \
      --registry-ca-cert-path "${TAP_INTERNAL_REGISTRY_CA_CERT_PATH}"

   if [[ "${TAP_PROFILE}" == "full" ]]; then

      # imgpkg copy -b ${TAP_TANZU_NETWORK_REGISTRY_HOST}/${TAP_TANZU_NETWORK_PROJECT}/${TAP_TANZU_NETWORK_FULL_DEPS_REPOSITORY_NAME}:${TAP_VERSION} \
      #    --to-tar full-deps-${TAP_VERSION}.tar \
      #    --include-non-distributable-layers

      # imgpkg copy \
      #    --tar product/full-deps-$TAP_VERSION.tar \
      #    --to-repo ${INSTALL_REGISTRY_HOSTNAME}/${TAP_INTERNAL_REGISTRY_PROJECT}/${TAP_INTERNAL_REGISTRY_FULL_DEPS_PACKAGES_REPOSITORY} \
      #    --include-non-distributable-layers \
      #    --registry-ca-cert-path ${TAP_INTERNAL_REGISTRY_CA_CERT_PATH}

      imgpkg copy -b ${TAP_TANZU_NETWORK_REGISTRY_HOST}/${TAP_TANZU_NETWORK_PROJECT}/${TAP_TANZU_NETWORK_FULL_DEPS_REPOSITORY_NAME}:${TAP_VERSION} \
         --to-repo ${INSTALL_REGISTRY_HOSTNAME}/${TAP_INTERNAL_REGISTRY_PROJECT}/${TAP_INTERNAL_REGISTRY_FULL_DEPS_PACKAGES_REPOSITORY}
   fi
}

generate_tap_values() {
   ( echo "cat <<EOF >${BASE_DIR}/config/${ENV}-tap-values.yaml";
      cat "${BASE_DIR}/template/tap-values-template.yaml"
      echo "";
      echo "EOF";
   ) >"${BASE_DIR}/config/temp.yml"
   . "${BASE_DIR}/config/temp.yml"

   rm "${BASE_DIR}/config/temp.yml"
   
   ytt -f "${BASE_DIR}/config/${ENV}-tap-values.yaml" --data-values-env TAP \
      --data-value-file harbor.certificate="${TAP_INTERNAL_REGISTRY_CA_CERT_PATH}" > "${BASE_DIR}/config/${ENV}-tap-values-final.yaml"
}

generate_ootb_supply_chain_values() {
   ( echo "cat <<EOF >${BASE_DIR}/config/${ENV}-ootb-supply-chain-testing-scanning.yaml";
      cat "${BASE_DIR}/template/ootb-supply-chain-testing-scanning-template.yaml"
      echo "";
      echo "EOF";
   ) >"${BASE_DIR}/config/temp.yml"
   . "${BASE_DIR}/config/temp.yml"

   rm "${BASE_DIR}/config/temp.yml"

   ytt -f "${BASE_DIR}/config/${ENV}-ootb-supply-chain-testing-scanning.yaml" --data-values-env TAP \
      --data-value-file harbor.certificate="${TAP_INTERNAL_REGISTRY_CA_CERT_PATH}" > "${BASE_DIR}/config/${ENV}-ootb-supply-chain-testing-scanning-final.yaml"
}

logAndExecute() {
   echo "**** Executing ${1} ****"
   $1
   echo "**** Done Executing ${1} ****"
   echo
}