#!/bin/bash

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

   if [[ "${OS}" == "Linux" ]]; then
      pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version="${TANZU_ESSENTIALS_VERSION}" --glob='tanzu-cluster-essentials-linux-amd64-*.tgz'
   elif [[ "${OS}" == "Darwin" ]]; then
      pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version="${TANZU_ESSENTIALS_VERSION}" --glob='tanzu-cluster-essentials-darwin-amd64-*.tgz'
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
      pivnet download-product-files --product-slug='tanzu-application-platform' --release-version="${TAP_VERSION}" --glob='tanzu-framework-linux-amd64-*.tar'
   elif [[ "${OS}" == "Darwin" ]]; then
      pivnet download-product-files --product-slug='tanzu-application-platform' --release-version="${TAP_VERSION}" --glob='tanzu-framework-darwin-amd64-*.tar'
   fi
   mv tanzu-framework-* ${TANZU_DOWNLOADS_DIR}/
   pushd ${TANZU_DOWNLOADS_DIR}
      tar zxvf ${TANZU_DOWNLOADS_DIR}/tanzu-framework-*
   popd

   tanzu_network_logout
}

install_tanzu_plugins() {
   pushd ${TANZU_CLI_DIR}
      TANZU_CLI_PATH=$(find . -name tanzu-core*)
      cp ${TANZU_CLI_PATH} /usr/local/bin/tanzu

      export TANZU_CLI_NO_INIT=true
      tanzu plugin install all -l .
   popd
}

docker_login_to_tanzunet() {
   docker login registry.tanzu.vmware.com -u ${TAP_TANZU_REGISTRY_USERNAME} -p ${TAP_TANZU_REGISTRY_PASSWORD}
}

configure_psp_for_tkgs(){
   set +e
   CRB_EXISTS=$(kubectl get clusterrolebindings.rbac.authorization.k8s.io | grep ${CLUSTER_ROLE_BINDING_NAME})
   set -e

   if [[ -z "${CRB_EXISTS}" ]]; then
      echo "Creating the clusterrolebinding : ${CLUSTER_ROLE_BINDING_NAME}, as it does not exist"
      kubectl create clusterrolebinding ${CLUSTER_ROLE_BINDING_NAME} --clusterrole=psp:vmware-system-privileged --group=system:authenticated
   else
      echo "Skipping creation of the clusterrolebinding : ${CLUSTER_ROLE_BINDING_NAME}, as it already exists"
   fi
}

setup_kapp_controller() {
   echo "**** Executing setup_kapp_controller ****"

   KAPP_CONTROLLER_EXIST=$(kubectl get po -A | grep kapp-controller- | awk '{split($0,a," "); print a[1]}')

   if [[ ! -z "${KAPP_CONTROLLER_EXIST}" ]]; then
      set +e
      SECRET_EXISTS=$(kubectl get secret --namespace "${KAPP_CONTROLLER_EXIST}" | grep "kapp-controller-config")
      set -e

      if [[ -z "${SECRET_EXISTS}" ]]; then
         echo "Creating secret: kapp-controller-config, as it does not exist"

         kubectl create secret generic kapp-controller-config \
            --namespace ${KAPP_CONTROLLER_EXIST} \
            --from-file caCerts=${INTERNAL_REGISTRY_CA_CERT_PATH}
      else
         echo "Skipping create of the secret: kapp-controller-config, as it already exists"
      fi
   else
      echo "*** Provision kapp_controller, as it does not exist in any other namespace ***"
      create_kapp_controller_namespace
      create_kapp_controller_secret
      install_tkg_essentials
   fi

   echo "**** Done executing setup_kapp_controller ****"
}

create_kapp_controller_namespace() {
   echo "**** Executing create_kapp_controller_namespace ****"

   set +e
   NAMESPACE_EXISTS=$(kubectl get namespace | grep "kapp-controller")
   set -e

   if [[ -z "${NAMESPACE_EXISTS}" ]]; then
      echo "Creating namespace: kapp-controller, as it does not exist"
      kubectl create namespace kapp-controller
   else
      echo "Skipping create of the namespace: kapp-controller, as it already exists"
   fi

   echo "**** Done executing create_kapp_controller_namespace ****"
}

create_kapp_controller_secret() {
   echo "**** Executing create_kapp_controller_secret ****"

   set +e
   SECRET_EXISTS=$(kubectl get secret --namespace kapp-controller | grep "kapp-controller-config")
   set -e
   
   if [[ -z "${SECRET_EXISTS}" ]]; then
      echo "Creating secret: kapp-controller-config, as it does not exist"

      kubectl create secret generic kapp-controller-config \
         --namespace kapp-controller \
         --from-file caCerts=${INTERNAL_REGISTRY_CA_CERT_PATH}
   else
      echo "Skipping create of the secret: kapp-controller-config, as it already exists"
   fi

   echo "**** Done executing create_kapp_controller_secret ****"
}

install_tkg_essentials() {
   echo "**** Executing install_tkg_essentials ****"

   pushd ${TANZU_ESSENTIALS_DIR}
      export INSTALL_BUNDLE=${TANZU_ESSENTIALS_BUNDLE}
      export INSTALL_REGISTRY_HOSTNAME=${TAP_TANZU_REGISTRY_HOST}
      export INSTALL_REGISTRY_USERNAME=${TAP_TANZU_REGISTRY_USERNAME}
      export INSTALL_REGISTRY_PASSWORD=${TAP_TANZU_REGISTRY_PASSWORD}

      ./install.sh --yes
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

add_tap_repository() {
   echo "**** Executing add_tap_repository ****"

   export INSTALL_REGISTRY_HOSTNAME=${TAP_INTERNAL_REGISTRY_HOST}
   export INSTALL_REGISTRY_USERNAME=${TAP_INTERNAL_REGISTRY_USERNAME}
   export INSTALL_REGISTRY_PASSWORD=${TAP_INTERNAL_REGISTRY_PASSWORD}
   export TAP_VERSION=${TAP_VERSION}

   set +e
   NAMESPACE_EXISTS=$(kubectl get namespace | grep "${TAP_INSTALL_NAMESPACE}")
   set -e

   if [[ -z "${NAMESPACE_EXISTS}" ]]; then
      echo "Creating namespace: ${TAP_INSTALL_NAMESPACE}, as it does not exist"
      kubectl create namespace ${TAP_INSTALL_NAMESPACE}
   else
      echo "Skipping create of the namespace: ${TAP_INSTALL_NAMESPACE}, as it already exists"
   fi

   tanzu secret registry add tap-registry \
   --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} \
   --server ${INSTALL_REGISTRY_HOSTNAME} \
   --export-to-all-namespaces --yes --namespace ${TAP_INSTALL_NAMESPACE}

   if [[ -z $(tanzu package repository list --namespace ${TAP_INSTALL_NAMESPACE} | grep  ${TAP_REPOSITORY_NAME}) ]]; then
      tanzu package repository add ${TAP_REPOSITORY_NAME} \
         --url ${INSTALL_REGISTRY_HOSTNAME}/${TAP_INTERNAL_PROJECT}/${TAP_INTERNAL_TAP_PACKAGES_REPOSITORY}:${TAP_VERSION} \
         --namespace ${TAP_INSTALL_NAMESPACE}
   else
      tanzu package repository update ${TAP_REPOSITORY_NAME} \
         --url ${INSTALL_REGISTRY_HOSTNAME}/${TAP_INTERNAL_PROJECT}/${TAP_INTERNAL_TAP_PACKAGES_REPOSITORY}:${TAP_VERSION} \
         --namespace ${TAP_INSTALL_NAMESPACE}
   fi

   tanzu package repository get ${TAP_REPOSITORY_NAME} --namespace ${TAP_INSTALL_NAMESPACE}

   tanzu package available list --namespace ${TAP_INSTALL_NAMESPACE}
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

install_tap() {
   tanzu package install tap -p tap.tanzu.vmware.com \
      -v ${TAP_VERSION} --values-file ${BASE_DIR}/config/${ENV}-tap-values-final.yaml \
      -n ${TAP_INSTALL_NAMESPACE}
}

setup_dev_namespace() {
   export INSTALL_REGISTRY_HOSTNAME=${TAP_INTERNAL_REGISTRY_HOST}
   export INSTALL_REGISTRY_USERNAME=${TAP_INTERNAL_REGISTRY_USERNAME}
   export INSTALL_REGISTRY_PASSWORD=${TAP_INTERNAL_REGISTRY_PASSWORD}

   kubectl create ns ${TAP_DEV_NAMESPACE}

   tanzu secret registry add tap-registry \
   --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} \
   --server ${INSTALL_REGISTRY_HOSTNAME} \
   --export-to-all-namespaces --yes --namespace ${TAP_DEV_NAMESPACE}

   tanzu secret registry add registry-credentials \
   --server ${INSTALL_REGISTRY_HOSTNAME} \
   --username ${INSTALL_REGISTRY_USERNAME} \
   --password ${INSTALL_REGISTRY_PASSWORD} \
   --namespace ${TAP_DEV_NAMESPACE}

cat <<EOF | kubectl -n ${TAP_DEV_NAMESPACE} apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: tap-registry
  annotations:
    secretgen.carvel.dev/image-pull-secret: ""
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: e30K
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
secrets:
  - name: registry-credentials
imagePullSecrets:
  - name: registry-credentials
  - name: tap-registry
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default-permit-deliverable
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: deliverable
subjects:
  - kind: ServiceAccount
    name: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default-permit-workload
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: workload
subjects:
  - kind: ServiceAccount
    name: default
EOF

}

function setup_git_secrets() {
   if [[ (! -z ${GIT_USERNAME}) && (! -z ${GIT_PASSWORD}) && (! -z ${GIT_URL} ) ]]; then
      export GIT_PASSWORD=${GIT_PASSWORD}
      kp secret create ${TAP_GITOPS_SSH_SECRET_NAME} --git-url ${GIT_URL} \
      --git-user ${GIT_USERNAME} --service-account ${K8S_SERVICE_ACCOUNT} \
      --namespace ${TAP_DEV_NAMESPACE}
   fi
}

check_for_required_clis
validate_all_arguments
prompt_user_kubernetes_login
install_tanzu_plugins
docker_login_to_tanzunet
configure_psp_for_tkgs
setup_kapp_controller
copy_images_to_registry
add_tap_repository
setup_git_secrets
setup_dev_namespace
generate_tap_values
install_tap