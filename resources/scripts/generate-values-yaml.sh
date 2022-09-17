source .env

# Generate Postgres variables
export MLFLOW_DB_HOST=$(kubectl get svc pg-mlflow-app-lb-svc -n default -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
export MLFLOW_DB_NAME=pg-mlflow-app
export MLFLOW_DB_USER=pgadmin
export MLFLOW_DB_PASSWORD=$(kubectl get secret pg-mlflow-app-db-secret -n default -o jsonpath='{.data.password}' | base64 --decode)
export MLFLOW_DB_URI=postgresql://${MLFLOW_DB_USER}:${MLFLOW_DB_PASSWORD}@${MLFLOW_DB_HOST}:5432/${MLFLOW_DB_NAME}

# Generate values.yaml
cat > $1 <<- EOF
region: ${S3_DEFAULT_REGION}
artifact_store: ${MLFLOW_S3_ENDPOINT_URL}
access_key: ${S3_ACCESS_KEY_ID}
secret_key: ${S3_SECRET_ACCESS_KEY}
version: ${MLFLOW_VERSION:-"1.0.0"}
backing_store: ${MLFLOW_DB_URI:-"sqlite:///my.db"}
ingress_fqdn: mlflow-gui.${MLFLOW_INGRESS_DOMAIN}
bucket: ${MLFLOW_BUCKET:-"mlflow"}
ignore_tls: "true"
ingress_domain: ${MLFLOW_INGRESS_DOMAIN}
EOF