## Contents
1. [Before you begin](#pre-reqs)
2. [Install MLFlow via TAP/tanzu cli](#tanzu)
3. [Install MLFlow with vanilla Kubernetes](#k8s)

### Before you begin:<a name="pre-reqs"/>
1. Update `resources/mlflow-deployment.yaml` by updating the **container image**, **Minio endpoint** and **Minio bucket region** as indicated in the file.
2. If using Project Contour, uncomment out the `HttpProxy` section of the `resources/mlflow-deployment.yaml` file and update the referenced **FQDN** accordingly.
3. Create an environment file `.env`; use `.env-sample` as a template.

### Install MLFlow via TAP/tanzu cli<a name="tanzu"/>
To install MLFlow via **tanzu cli** - first deploy Postgres operator (if it does not already exist):
```
resources/scripts/deploy-postgres-operator.sh
```

Deploy Postgres cluster (if it does not already exist):
```
resources/scripts/deploy-postgres-cluster.sh
```

Export Postgres environment variables:
```
export MLFLOW_DB_HOST=$(kubectl get svc pg-mlflow-app-lb-svc -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
export MLFLOW_DB_NAME=pg-mlflow-app
export MLFLOW_DB_USER=$(kubectl get secret pg-mlflow-app-db-secret -o jsonpath='{.data.username}' | base64 --decode)
export MLFLOW_DB_PASSWORD=$(kubectl get secret pg-mlflow-app-db-secret -o jsonpath='{.data.password}' | base64 --decode)
export MLFLOW_DB_URI=postgresql://${MLFLOW_DB_USER}:${MLFLOW_DB_PASSWORD}@${MLFLOW_DB_HOST}:5432/${MLFLOW_DB_NAME}
```

Build and push Docker image:
```
source .env
docker build --build-arg MLFLOW_PORT_NUM=${MLFLOW_PORT} \
 --build-arg ARTIFACT_ROOT_PATH=s3://mlflow \
 --build-arg BACKEND_URI_PATH=${MLFLOW_DB_URI} \
 -t ${MLFLOW_CONTAINER_REPO} . # example: oawofolu/mlflow-server
docker push ${MLFLOW_CONTAINER_REPO}
```

Create the MLFlow package bundle as a pre-requisite:
```
resources/scripts/create-mlflow-package-bundle.sh
```

Install the MLFlow Package Repository:
```
tanzu package repository add mlflow-package-repository \
  --url oawofolu/mlflow-packages-repo:1.0.0 \
  --namespace tap-install
```

Verify that the MLFlow package is available for install:
```
tanzu package available list mlflow.tanzu.vmware.com --namespace tap-install
```

Generate a values.yaml file to use for the install - update as desired:
```
resources/scripts/generate-values-yaml.sh resources/mlflow-values.yaml #replace resources/mlflow-values.yaml with /path/to/your/values/yaml/file
```

Install via **tanzu cli**:
```
tanzu package install mlflow -p mlflow.tanzu.vmware.com -v 1.0.0 --values-file resources/mlflow-values.yaml --namespace tap-install
```

Verify that the install was successful:
```
tanzu package installed get mlflow -n tap-install
```

To uninstall:
```
tanzu package installed delete mlflow --namespace tap-install -y
tanzu package repository delete mlflow-package-repository --namespace tap-install -y
```

Finally, access the Tracker server via the **ingress_fqdn** indicated in resources/mlflow-values.yaml

### Deploy Postgres cluster<a name="pgcluster"/>

Deploy Postgres Operator via helm (if the operator does not exist in the cluster):
```
helm uninstall postgres --namespace default
for i in $(kubectl get clusterrole | grep postgres); do kubectl delete clusterrole ${i} > /dev/null 2>&1; done; 
for i in $(kubectl get clusterrolebinding | grep postgres); do kubectl delete clusterrolebinding ${i} > /dev/null 2>&1; done; 
for i in $(kubectl get certificate -n cert-manager | grep postgres); do kubectl delete certificate -n cert-manager ${i} > /dev/null 2>&1; done; 
for i in $(kubectl get clusterissuer | grep postgres); do kubectl delete clusterissuer ${i} > /dev/null 2>&1; done; 
for i in $(kubectl get mutatingwebhookconfiguration | grep postgres); do kubectl delete mutatingwebhookconfiguration ${i} > /dev/null 2>&1; done; 
for i in $(kubectl get validatingwebhookconfiguration | grep postgres); do kubectl delete validatingwebhookconfiguration ${i} > /dev/null 2>&1; done; 
for i in $(kubectl get crd | grep postgres); do kubectl delete crd ${i} > /dev/null 2>&1; done;
helm install postgres resources/postgres/operator1.6.0 \
-f resources/postgres/overrides.yaml --namespace default --wait
kubectl apply -f resources/postgres/operator1.6.0/crds/
```

Deploy Postgres Cluster:
```
kubectl delete ns mlflow || true
kubectl create ns mlflow
kubectl apply -f resources/postgres/postgres-cluster.yaml -n mlflow --wait
```

Wait for the Postgres cluster to be fully deployed:
```
watch kubectl get all -l app=postgres -n mlflow
```

Export Postgres environment variables:
```
export MLFLOW_DB_HOST=$(kubectl get svc pg-mlflow-lb-svc -n mlflow -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
export MLFLOW_DB_NAME=pg-mlflow
export MLFLOW_DB_USER=pgadmin 
export MLFLOW_DB_PASSWORD=$(kubectl get secret pg-mlflow-db-secret -n mlflow -o jsonpath='{.data.password}' | base64 --decode)
export MLFLOW_DB_URI=postgresql://${MLFLOW_DB_USER}:${MLFLOW_DB_PASSWORD}@${MLFLOW_DB_HOST}:5432/${MLFLOW_DB_NAME}
```

### Install MLFlow via vanilla Kubernetes<a name="k8s"/>

Build and push Docker image:
```
source .env
docker build --build-arg MLFLOW_PORT_NUM=${MLFLOW_PORT} \
 --build-arg ARTIFACT_ROOT_PATH=s3://mlflow \
 -t ${MLFLOW_CONTAINER_REPO} . # example: oawofolu/mlflow-server
docker push ${MLFLOW_CONTAINER_REPO}
```

Test running Docker image locally:
```
export MLFLOW_DB_PASSWORD=$(kubectl get secret pg-mlflow-db-secret -n mlflow -o jsonpath='{.data.password}' | base64 --decode)
#export MLFLOW_DB_URI=postgresql://pg-mlflow:${MLFLOW_DB_PASSWORD}@pg-mlflow.mlflow.svc.cluster.local:5432/pg-mlflow
docker run -it --rm -p 8020:8020 \
-e MLFLOW_PORT=${MLFLOW_PORT} \ # ex. 8020
-e ARTIFACT_ROOT=s3://${MLFLOW_BUCKET}/ \ # ex. mlflow
-e MLFLOW_S3_ENDPOINT_URL=https://minio.tanzudatatap.ml/ \ # your Minio endpoint URL
-e S3_ACCESS_KEY_ID ${S3_ACCESS_KEY_ID} \ # Your Minio username
-e S3_SECRET_KEY_ID ${S3_SECRET_ACCESS_KEY} \ # Your Minio password
-e BACKEND_URI ${MLFLOW_DB_URI} \ # Your Postgres DB URI, constructed above
-e MLFLOW_S3_IGNORE_TLS=true\
--name mlflow-server ${MLFLOW_CONTAINER_REPO}
```

Deploy MLFLOW access creds: (Requires Kubeseal installation: https://github.com/bitnami-labs/sealed-secrets/releases)
```
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.17.4/controller.yaml
source .env # populate the .env file with the appropriate creds - use .env-sample as a template
kubectl create secret generic mlflowcreds --from-literal=S3_ACCESS_KEY_ID=${S3_ACCESS_KEY_ID} --from-literal=S3_SECRET_ACCESS_KEY=${S3_SECRET_ACCESS_KEY} --from-literal=S3_DEFAULT_REGION=${S3_DEFAULT_REGION} --from-literal=MLFLOW_S3_ENDPOINT_URL=${MLFLOW_S3_ENDPOINT_URL} --from-literal=MLFLOW_S3_IGNORE_TLS=${MLFLOW_S3_IGNORE_TLS} --from-literal=MLFLOW_BACKEND_URI=${MLFLOW_DB_URI} --dry-run=client -o yaml > mlflow-creds-secret.yaml
kubeseal --scope cluster-wide -o yaml <mlflow-creds-secret.yaml> resources/mlflow-creds-sealedsecret.yaml
kubectl create secret docker-registry docker-creds --docker-server=index.docker.io --docker-username=${DOCKER_REG_USERNAME} --docker-password=${DOCKER_REG_PASSWORD} --dry-run -o yaml > docker-creds-secret.yaml
echo '---' >>resources/mlflow-creds-sealedsecret.yaml
kubeseal --scope cluster-wide -o yaml <docker-creds-secret.yaml>>resources/mlflow-creds-sealedsecret.yaml
rm mlflow-creds-secret.yaml docker-creds-secret.yaml
kubectl apply -f resources/mlflow-creds-sealedsecret.yaml -n mlflow
```

Deploy MlFlow Tracking Server to Kubernetes: (skip if deploying via TAP)
```
kubectl delete -f resources/mlflow-deployment.yaml -n mlflow || true
source .env # populate the .env file with the appropriate creds - use .env-sample as a template
envsubst < resources/mlflow-deployment.yaml | kubectl apply  -n mlflow -f -
watch kubectl get all -n mlflow
```

Deploy MlFlow Tracking Server via TAP:
```
kubectl create ns mlflow-demo
kubectl create clusterrolebinding mlflow-demo:cluster-admin --clusterrole=cluster-admin --user=system:serviceaccount:mlflow-demo:default
kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "docker-creds"}],"secrets": [{"name": "docker-creds"}]}' -n mlflow-demo
kubectl apply -f resources/mlflow-workload.yaml -n mlflow-demo
tanzu apps workload tail mlflow-tap --since 64h -n mlflow-demo
```

Finally, access MLFlow in your browser via the endpoint indicated in `resources/mlflow-deployment.yaml` (either via FQDN indicated by Contour's HttpProxy, or by the endpoint indicated by the Service if not using HttpProxy)

