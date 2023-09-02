#!/bin/bash

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

configure_psp_for_tkgs() {
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
}

create_kapp_controller_namespace() {
   set +e
   NAMESPACE_EXISTS=$(kubectl get namespace | grep "kapp-controller")
   set -e

   if [[ -z "${NAMESPACE_EXISTS}" ]]; then
      echo "Creating namespace: kapp-controller, as it does not exist"
      kubectl create namespace kapp-controller
   else
      echo "Skipping create of the namespace: kapp-controller, as it already exists"
   fi
}

create_kapp_controller_secret() {
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
}

install_tkg_essentials() {
   pushd ${TANZU_ESSENTIALS_DIR}
      export INSTALL_BUNDLE=${TANZU_ESSENTIALS_BUNDLE}
      export INSTALL_REGISTRY_HOSTNAME=${TAP_TANZU_REGISTRY_HOST}
      export INSTALL_REGISTRY_USERNAME=${TAP_TANZU_REGISTRY_USERNAME}
      export INSTALL_REGISTRY_PASSWORD=${TAP_TANZU_REGISTRY_PASSWORD}

      ./install.sh --yes
   popd
}

add_tap_repository() {
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

install_tap() {
   tanzu package install tap -p tap.tanzu.vmware.com \
      -v ${TAP_VERSION} --values-file ${BASE_DIR}/config/${ENV}-tap-values-final.yaml \
      -n ${TAP_INSTALL_NAMESPACE}
}

setup_dev_namespace() {
   export INSTALL_REGISTRY_HOSTNAME=${TAP_INTERNAL_REGISTRY_HOST}
   export INSTALL_REGISTRY_USERNAME=${TAP_INTERNAL_REGISTRY_USERNAME}
   export INSTALL_REGISTRY_PASSWORD=${TAP_INTERNAL_REGISTRY_PASSWORD}

   set +e
   NAMESPACE_EXISTS=$(kubectl get namespace | grep "${TAP_DEV_NAMESPACE}")
   set -e

   if [[ -z "${NAMESPACE_EXISTS}" ]]; then
      kubectl create ns ${TAP_DEV_NAMESPACE}
   fi

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

      set +e
      SECRET_EXISTS=$(kubectl get secret --namespace "${TAP_DEV_NAMESPACE}" | grep "${TAP_GITOPS_SSH_SECRET_NAME}")
      set -e

      if [[ -z "${SECRET_EXISTS}" ]]; then
         kp secret create ${TAP_GITOPS_SSH_SECRET_NAME} --git-url ${GIT_URL} \
            --git-user ${GIT_USERNAME} --service-account ${K8S_SERVICE_ACCOUNT} \
            --namespace ${TAP_DEV_NAMESPACE}
      fi
   fi
}

logAndExecute() {
   echo "**** Executing ${1} ****"
   $1
   echo "**** Done Executing ${1} ****"
   echo
}

logAndExecute check_for_required_clis
logAndExecute validate_all_arguments
logAndExecute install_tanzu_plugins
logAndExecute prompt_user_kubernetes_login
logAndExecute docker_login_to_tanzunet
logAndExecute configure_psp_for_tkgs
logAndExecute setup_kapp_controller
logAndExecute copy_images_to_registry
logAndExecute add_tap_repository
logAndExecute generate_tap_values
logAndExecute install_tap
logAndExecute setup_git_secrets
logAndExecute setup_dev_namespace