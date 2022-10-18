source .env
envsubst < resources/minio/minio-http-proxy.in.yaml > resources/minio/minio-http-proxy.yaml
envsubst < resources/minio/openssl.in.conf > resources/minio/openssl.conf
openssl genrsa -out private.key 2048
openssl req -new -x509 -nodes -days 730 -key private.key -out public.crt -config resources/minio/openssl.conf
helm repo add minio-legacy https://helm.min.io/
kubectl create ns minio-ml
kubectl create secret generic tls-ssl-minio --from-file=private.key --from-file=public.crt --namespace minio-ml
helm install --set resources.requests.memory=1.5Gi,tls.enabled=true,tls.certSecret=tls-ssl-minio --namespace minio-ml minio minio-legacy/minio --wait
kubectl apply -f resources/minio/minio-http-proxy.yaml