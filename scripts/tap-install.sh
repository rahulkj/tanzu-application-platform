#!/bin/bash

DIR=$(dirname "$(realpath ${0})")
BASE_DIR=$(dirname ${DIR})

source ${DIR}/common.sh

if [[ -z ${ENV} ]]; then
   echo "Please supply the variable ENV and ensure you have the file ${DIR}/ENV-env in this directory. Use the scripts/env template to build your version"
   exit 1
fi

if [[ ! -f "${DIR}/${ENV}-env" ]]; then
   echo "Ensure you have the file ${DIR}/${ENV}-env in this directory. Use the scripts/env template to build your version"
   exit 1
fi

source "${DIR}/${ENV}-env"

configure_psp_for_tkgs() {
   set +e
   CRB_EXISTS=$(kubectl get clusterrolebindings.rbac.authorization.k8s.io | grep "${CLUSTER_ROLE_BINDING_NAME}")
   set -e

   if [[ -z "${CRB_EXISTS}" ]]; then
      echo "Creating the clusterrolebinding : ${CLUSTER_ROLE_BINDING_NAME}, as it does not exist"
      kubectl create clusterrolebinding "${CLUSTER_ROLE_BINDING_NAME}" --clusterrole=psp:vmware-system-privileged --group=system:authenticated
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
            --namespace "${KAPP_CONTROLLER_EXIST}" \
            --from-file caCerts="${INTERNAL_REGISTRY_CA_CERT_PATH}"
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
         --from-file caCerts="${INTERNAL_REGISTRY_CA_CERT_PATH}"
   else
      echo "Skipping create of the secret: kapp-controller-config, as it already exists"
   fi
}

install_tkg_essentials() {
   pushd "${TANZU_ESSENTIALS_DIR}"
      export INSTALL_BUNDLE="${TANZU_ESSENTIALS_BUNDLE}"
      export INSTALL_REGISTRY_HOSTNAME="${TAP_TANZU_REGISTRY_HOST}"
      export INSTALL_REGISTRY_USERNAME="${TAP_TANZU_REGISTRY_USERNAME}"
      export INSTALL_REGISTRY_PASSWORD="${TAP_TANZU_REGISTRY_PASSWORD}"

      ./install.sh --yes
   popd
}

create_tap_installation_namespace() {
   set +e
   NAMESPACE_EXISTS=$(kubectl get namespace | grep "${TAP_INSTALL_NAMESPACE}")
   set -e

   if [[ -z "${NAMESPACE_EXISTS}" ]]; then
      echo "Creating namespace: ${TAP_INSTALL_NAMESPACE}, as it does not exist"
      kubectl create namespace "${TAP_INSTALL_NAMESPACE}"
   else
      echo "Skipping create of the namespace: ${TAP_INSTALL_NAMESPACE}, as it already exists"
   fi
}

create_registry_secrets() {
   export INSTALL_REGISTRY_HOSTNAME="${TAP_INTERNAL_REGISTRY_HOST}"
   export INSTALL_REGISTRY_USERNAME="${TAP_INTERNAL_REGISTRY_USERNAME}"
   export INSTALL_REGISTRY_PASSWORD="${TAP_INTERNAL_REGISTRY_PASSWORD}"
   export TAP_VERSION="${TAP_VERSION}"

   tanzu secret registry add "${TAP_REGISTRY_SECRET_NAME}" \
   --username "${INSTALL_REGISTRY_USERNAME}" --password "${INSTALL_REGISTRY_PASSWORD}" \
   --server "${INSTALL_REGISTRY_HOSTNAME}" \
   --export-to-all-namespaces --yes --namespace "${TAP_INSTALL_NAMESPACE}"
}

add_tap_repository() {
   if [[ -z $(tanzu package repository list --namespace "${TAP_INSTALL_NAMESPACE}" | grep  "${TAP_REPOSITORY_NAME}") ]]; then
      tanzu package repository add "${TAP_REPOSITORY_NAME}" \
      --url "${TAP_INTERNAL_REGISTRY_HOST}/${TAP_INTERNAL_PROJECT}/${TAP_INTERNAL_TAP_PACKAGES_REPOSITORY}:${TAP_VERSION}" \
      --namespace "${TAP_INSTALL_NAMESPACE}"
   else
      if [[ -z $(tanzu package repository list --namespace "${TAP_INSTALL_NAMESPACE}" | grep  "${TAP_REPOSITORY_NAME}") ]]; then
         tanzu package repository update "${TAP_REPOSITORY_NAME}" \
         --url "${TAP_INTERNAL_REGISTRY_HOST}/${TAP_INTERNAL_PROJECT}/${TAP_INTERNAL_TAP_PACKAGES_REPOSITORY}:${TAP_VERSION}" \
         --namespace "${TAP_INSTALL_NAMESPACE}"
      else
         echo "Nothing to update here for ${TAP_REPOSITORY_NAME}"
      fi
   fi

   if [[ -z $(tanzu package repository list --namespace "${TAP_INSTALL_NAMESPACE}" | grep "${TAP_FULL_DEPS_REPOSITORY_NAME}") ]]; then
      tanzu package repository add "${TAP_FULL_DEPS_REPOSITORY_NAME}" \
      --url ${INSTALL_REGISTRY_HOSTNAME}/${TAP_INTERNAL_PROJECT}/${TAP_FULL_DEPS_REPOSITORY_NAME}:${TAP_VERSION} \
      --namespace "${TAP_INSTALL_NAMESPACE}"
   else
      if [[ -z $(tanzu package repository list --namespace "${TAP_INSTALL_NAMESPACE}" | grep "${TAP_FULL_DEPS_REPOSITORY_NAME}") ]]; then
         tanzu package repository update "${TAP_FULL_DEPS_REPOSITORY_NAME}" \
         --url ${INSTALL_REGISTRY_HOSTNAME}/${TAP_INTERNAL_PROJECT}/${TAP_FULL_DEPS_REPOSITORY_NAME}:${TAP_VERSION} \
         --namespace "${TAP_INSTALL_NAMESPACE}"
      else
         echo "Nothing to update here for ${TAP_FULL_DEPS_REPOSITORY_NAME}"
      fi
   fi

   tanzu package repository get "${TAP_REPOSITORY_NAME}" --namespace "${TAP_INSTALL_NAMESPACE}"

   tanzu package available list --namespace "${TAP_INSTALL_NAMESPACE}"
}

install_tap() {
   tanzu package install tap -p tap.tanzu.vmware.com \
      -v "${TAP_VERSION}" --values-file "${BASE_DIR}/config/${ENV}-tap-values-final.yaml" \
      -n "${TAP_INSTALL_NAMESPACE}"
   
   if [[ "${TAP_PROFILE}" == "full" ]]; then
      FULL_DEPS_VERSION=$(tanzu package available list full-deps.buildservice.tanzu.vmware.com \
         --namespace tap-install -o json | jq -r '.[] | select(.name | test("full-deps")?) | .version')

      tanzu package install full-deps -p full-deps.buildservice.tanzu.vmware.com \
         -v "${FULL_DEPS_VERSION}" -n tap-install --values-file "${BASE_DIR}/config/${ENV}-tap-values-final.yaml"
   fi
}

setup_dev_namespace() {
   export INSTALL_REGISTRY_HOSTNAME="${TAP_INTERNAL_REGISTRY_HOST}"
   export INSTALL_REGISTRY_USERNAME="${TAP_INTERNAL_REGISTRY_USERNAME}"
   export INSTALL_REGISTRY_PASSWORD="${TAP_INTERNAL_REGISTRY_PASSWORD}"

   set +e
   NAMESPACE_EXISTS=$(kubectl get namespace | grep "${TAP_DEV_NAMESPACE}")
   set -e

   if [[ -z "${NAMESPACE_EXISTS}" ]]; then
      kubectl create ns "${TAP_DEV_NAMESPACE}"
   fi

   tanzu secret registry add "${TAP_REGISTRY_SECRET_NAME}" \
   --username "${INSTALL_REGISTRY_USERNAME}" \
   --password "${INSTALL_REGISTRY_PASSWORD}" \
   --server "${INSTALL_REGISTRY_HOSTNAME}" \
   --export-to-all-namespaces --yes --namespace "${TAP_DEV_NAMESPACE}"

   tanzu secret registry add "${TAP_DEV_REGISTRY_SECRET_NAME}" \
   --server "${INSTALL_REGISTRY_HOSTNAME}" \
   --username "${INSTALL_REGISTRY_USERNAME}" \
   --password "${INSTALL_REGISTRY_PASSWORD}" \
   --namespace "${TAP_DEV_NAMESPACE}"

cat <<EOF | kubectl -n "${TAP_DEV_NAMESPACE}" apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: "${TAP_REGISTRY_SECRET_NAME}"
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
  - name: "${TAP_DEV_REGISTRY_SECRET_NAME}"
imagePullSecrets:
  - name: "${TAP_DEV_REGISTRY_SECRET_NAME}"
  - name: "${TAP_REGISTRY_SECRET_NAME}"
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
   ( echo "cat <<EOF >${BASE_DIR}/config/${ENV}-git-secrets.yaml";
      cat ${BASE_DIR}/template/secrets-template.yaml
      echo "EOF";
   ) >"${BASE_DIR}/config/temp.yml"
   . "${BASE_DIR}/config/temp.yml"

   rm "${BASE_DIR}/config/temp.yml"
   
   ytt -f "${BASE_DIR}/config/${ENV}-git-secrets.yaml" --data-values-env GIT \
      --data-value-file harbor.certificate="${INTERNAL_REGISTRY_CA_CERT_PATH}" > "${BASE_DIR}/config/${ENV}-git-secrets-final.yaml"

   kubectl apply -f "${BASE_DIR}/config/${ENV}-git-secrets-final.yaml" --namespace "${1}"

}

logAndExecute() {
   echo "**** Executing ${1} ****"
   $1
   echo "**** Done Executing ${1} ****"
   echo
}

# logAndExecute check_for_required_clis
# logAndExecute validate_all_arguments
# logAndExecute install_tanzu_plugins
# logAndExecute prompt_user_kubernetes_login
# logAndExecute docker_login_to_tanzunet
# logAndExecute docker_login_to_internal_registry
# logAndExecute configure_psp_for_tkgs
# logAndExecute setup_kapp_controller
# logAndExecute copy_images_to_registry
# logAndExecute create_tap_installation_namespace
# logAndExecute setup_git_secrets ${TAP_INSTALL_NAMESPACE}
# logAndExecute create_registry_secrets
# logAndExecute add_tap_repository
logAndExecute generate_tap_values
logAndExecute install_tap

if [[ -z "${TAP_DEV_NAMESPACE}" ]]; then
   echo "No dev space to create and update"
else
   logAndExecute setup_dev_namespace
   logAndExecute setup_git_secrets ${TAP_DEV_NAMESPACE}
fi
