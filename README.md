## Instructions

Before you begin:
1. Update `resources/mlflow-deployment.yaml` by updating the **container image**, **Minio endpoint** and **Minio bucket region** as indicated in the file.
2. If using Project Contour, uncomment out the `HttpProxy` section of the `resources/mlflow-deployment.yaml` file and update the referenced **FQDN** accordingly.

Deploy Postgres Operator (if it does not exist in the cluster):
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
kubectl get postgres -n mlflow
```

Export Postgres environment variables:
```
export MLFLOW_DB_HOST=$(kubectl get svc pg-mlflow-lb-svc -n mlflow -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
export MLFLOW_DB_NAME=pg-mlflow
export MLFLOW_DB_USER=pgadmin 
export MLFLOW_DB_PASSWORD=$(kubectl get secret pg-mlflow-db-secret -n mlflow -o jsonpath='{.data.password}' | base64 --decode)
export MLFLOW_DB_URI=postgresql://${MLFLOW_DB_USER}:${MLFLOW_DB_PASSWORD}@${MLFLOW_DB_HOST}:5432/${MLFLOW_DB_NAME}
```

Build and push Docker image:
```
docker build --build-arg MLFLOW_PORT_NUM=<your port> \
 --build-arg ARTIFACT_ROOT_PATH=s3://mlflow \
 -t <your-container-repo> . # example: oawofolu/mlflow-server
docker push <your-container-repo>
```

Run Docker image locally:
```
export MLFLOW_DB_PASSWORD=$(kubectl get secret pg-mlflow-db-secret -n mlflow -o jsonpath='{.data.password}' | base64 --decode)
#export MLFLOW_DB_URI=postgresql://pg-mlflow:${MLFLOW_DB_PASSWORD}@pg-mlflow.mlflow.svc.cluster.local:5432/pg-mlflow
docker run -it --rm -p 8020:8020 \
-e MLFLOW_PORT=<your port> \ # ex. 8020
-e ARTIFACT_ROOT=s3://<your mlflow S3 bucket>/ \ # ex. mlflow
-e MLFLOW_S3_ENDPOINT_URL=https://minio.tanzudatatap.ml/ \ # your Minio endpoint URL
-e AWS_ACCESS_KEY_ID <your s3/minio access key> \ # Your Minio username
-e AWS_SECRET_KEY_ID <your s3/minio secret key> \ # Your Minio password
-e BACKEND_URI ${MLFLOW_DB_URI} \ # Your Postgres DB URI, constructed above
-e MLFLOW_S3_IGNORE_TLS=true\
--name mlflow-server <your-container-repo>
```

Deploy MLFLOW access creds: (Requires Kubeseal installation: https://github.com/bitnami-labs/sealed-secrets/releases)
```
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.17.4/controller.yaml
source .env # populate the .env file with the appropriate creds - use .env-sample as a template
kubectl create secret generic mlflowcreds \
    --from-literal=AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \ # your Minio username
    --from-literal=AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \ # your Minio password
    --from-literal=AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \ # your AWS region if deploying on AWS
    --from-literal=MLFLOW_S3_ENDPOINT_URL=${MLFLOW_S3_ENDPOINT_URL} \ # your Minio endpoint, configured above
    --from-literal=MLFLOW_S3_IGNORE_TLS=${MLFLOW_S3_IGNORE_TLS} --dry-run=client -o yaml> mlflow-creds-secret.yaml
kubeseal --scope cluster-wide -o yaml <mlflow-creds-secret.yaml> resources/mlflow-creds-sealedsecret.yaml
rm mlflow-creds-secret.yaml
kubectl apply -f resources/mlflow-creds-sealedsecret.yaml -n mlflow
```

Deploy MlFlow Tracking Server to Kubernetes:
```
kubectl delete -f resources/mlflow-deployment.yaml -n mlflow || true
source .env # populate the .env file with the appropriate creds - use .env-sample as a template
envsubst < resources/mlflow-deployment.yaml | kubectl apply  -n mlflow -f -
watch kubectl get all -n mlflow
```

Finally, access MLFlow in your browser via the endpoint indicated in `resources/mlflow-deployment.yaml` (either via FQDN indicated by Contour's HttpProxy, or by the endpoint indicated by the Service if not using HttpProxy)
