Scripts to setup Tanzu Application Platform
---

## Prerequisities

* Ensure you have a TKGm/s cluster deployed
* Download the required cli's
  * [Tanzu cluster essentials](https://network.tanzu.vmware.com/products/tanzu-cluster-essentials/) Choose `amd64` or `darwin`, based on where you are running this from
  * [tanzu-cli](https://network.tanzu.vmware.com/products/tanzu-application-platform/)
  * Harbor is setup and you have downloaded the certificate


## Prep Work

* Update the file `./scripts/env` to point to the right directories those have clis, certificate staged
    ```
        export TANZU_NETWORK_TOKEN=     # Optional - Tanzu network token (Pivnet token)
        export TANZU_DOWNLOADS_DIR=     # Optional - Download directory for the packages

        export TANZU_CLI_DIR=           # Directory where you have unpacked the tanzu cli (https://network.tanzu.vmware.com/products/tanzu-application-platform/)
        export TANZU_ESSENTIALS_DIR=    # Directory where you have unpacked the tanzu cluster essentials (https://network.tanzu.vmware.com/products/tanzu-cluster-essentials/). Choose amd64 or darwin, based on where you are running this from
        export HARBOR_CA_CERT_PATH=     # Directory where you have your harbor certificate downloaded. ex: /Users/john/Downloads/harbor.pem

        export TANZU_ESSENTIALS_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:ab0a3539da241a6ea59c75c0743e9058511d7c56312ea3906178ec0f3491f51d # Update this based on which TAP version you are installing
        export TAP_TANZU_REGISTRY_HOST=registry.tanzu.vmware.com
        export TAP_TANZU_REGISTRY_USERNAME= # TanzuNet username
        export TAP_TANZU_REGISTRY_PASSWORD= # TanzuNet password

        export TAP_HARBOR_REGISTRY_USERNAME=        # Harbor Registry username
        export TAP_HARBOR_REGISTRY_PASSWORD=        # Harbor Registry password
        export TAP_HARBOR_REGISTRY_HOST=            # Harbor Registry host, ex: harbor.example.com
        export TAP_HARBOR_PROJECT=                  # Harbor Registry project to use, ex: tanzu
        export TAP_HARBOR_REPOSITORY=               # Harbor Registry build service repository to use, ex: build-service
        export TAP_HARBOR_TAP_PACKAGES_REPOSITORY=  # Harbor Registry tap repository to use, ex: tap-packages
        export TAP_HARBOR_SUPPLY_CHAIN_PROJECT=     # Harbor Registry project to use, ex: supply-chain

        export TAP_GITOPS_SSH_SECRET_NAME=          # Gitops SSH Secret Name

        export GIT_GITOPS_SSH_SECRET_NAME=${TAP_GITOPS_SSH_SECRET_NAME}
        export GIT_URL=https://github.com
        export GIT_USERNAME=                        # Git Username
        export GIT_PASSWORD=                        # Git user token
        export K8S_SERVICE_ACCOUNT=default          # Set the service account name to which the credentials need to be bound to

        export TAP_TAP_INGRESS_DOMAIN=              # Ingress domain to use for deploying contour

        export TAP_VERSION=1.2.0                    # TAP version
        export TANZU_ESSENTIALS_VERSION=1.2.0       # Tanzu cluster essentials version
        export TAP_PROFILE=                         # light or full
        export TAP_CATALOG_URL=                     # TAP blank catalog git location

        export DEV_NAMESPACE=                       # Namespace to enable for tanzu workloads
    ```

## Install Tanzu Cluster essentials and TAP

Once you have all the prereqs and prep work done, fire off the script `./scripts/tap-install.sh` to begin the installation

## Uninstall TAP and Tanzu Cluster essentials

IF you wish to nuke the setup, then execute `./scripts/tap-uninstall.sh`