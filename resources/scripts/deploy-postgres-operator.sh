source .env

# login to container registry
echo $DOCKER_REG_PASSWORD | docker login registry-1.docker.io --username=$DOCKER_REG_USERNAME --password-stdin

# install the operator
tanzu package repository add tanzu-postgres-repository --url oawofolu/tds-packages:1.0.0 --namespace default
tanzu package installed delete postgres-operator -ndefault -y
export PG_TANZU_PKG_VERSION=$(tanzu package available list -o json --namespace default | jq '.[] | select(.name=="postgres-operator.sql.tanzu.vmware.com")["latest-version"]' | tr -d '"')
tanzu package install postgres-operator --package-name postgres-operator.sql.tanzu.vmware.com --version $PG_TANZU_PKG_VERSION -f resources/postgres/postgres-values.yaml --namespace default