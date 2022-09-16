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
      exit 1
   fi

   if [[ ! -d ${TANZU_ESSENTIALS_DIR} ]]; then
      echo "Tanzu Essentials Directory: ${TANZU_ESSENTIALS_DIR} does not exist."
      exit 1
   fi
}

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
   export INSTALL_REGISTRY_HOSTNAME=${TAP_HARBOR_REGISTRY_HOST}
   export INSTALL_REGISTRY_USERNAME=${TAP_HARBOR_REGISTRY_USERNAME}
   export INSTALL_REGISTRY_PASSWORD=${TAP_HARBOR_REGISTRY_PASSWORD}
   export TAP_VERSION=${TAP_VERSION}

   imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:${TAP_VERSION} \
      --to-repo ${INSTALL_REGISTRY_HOSTNAME}/${TAP_HARBOR_PROJECT}/${TAP_HARBOR_TAP_PACKAGES_REPOSITORY} \
      --registry-ca-cert-path ${HARBOR_CA_CERT_PATH}
}

stage_for_tap_install() {
   export INSTALL_REGISTRY_HOSTNAME=${TAP_HARBOR_REGISTRY_HOST}
   export INSTALL_REGISTRY_USERNAME=${TAP_HARBOR_REGISTRY_USERNAME}
   export INSTALL_REGISTRY_PASSWORD=${TAP_HARBOR_REGISTRY_PASSWORD}
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


   ( echo "cat <<EOF >${BASE_DIR}/config/${ENV}-tap-values.yaml";
      cat ${BASE_DIR}/template/tap-values-template.yaml
      echo "EOF";
   ) >${BASE_DIR}/config/temp.yml
   . ${BASE_DIR}/config/temp.yml

   rm ${BASE_DIR}/config/temp.yml
   
   ytt -f ${BASE_DIR}/config/${ENV}-tap-values.yaml --data-values-env TAP \
      --data-value-file harbor.certificate=${HARBOR_CA_CERT_PATH} > ${BASE_DIR}/config/${ENV}-tap-values-final.yaml
}

install_tap() {
   tanzu package install tap -p tap.tanzu.vmware.com \
      -v ${TAP_VERSION} --values-file ${BASE_DIR}/config/${ENV}-tap-values-final.yaml \
      -n tap-install
}

setup_dev_namespace() {
   export INSTALL_REGISTRY_HOSTNAME=${TAP_HARBOR_REGISTRY_HOST}
   export INSTALL_REGISTRY_USERNAME=${TAP_HARBOR_REGISTRY_USERNAME}
   export INSTALL_REGISTRY_PASSWORD=${TAP_HARBOR_REGISTRY_PASSWORD}

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
      ytt -f ${BASE_DIR}/template/secrets-template.yaml --data-values-env GIT > ${BASE_DIR}/config/${ENV}-secrets-final.yaml
      kubectl apply -f ${BASE_DIR}/config/${ENV}-secrets-final.yaml
   fi
}

validate_all_arguments
install_tanzu_plugins
docker_login_to_tanzunet
configure_psp_for_tkgs
install_tkg_essentials
copy_images_to_registry
stage_for_tap_install
install_tap
setup_dev_namespace
setup_git_secrets