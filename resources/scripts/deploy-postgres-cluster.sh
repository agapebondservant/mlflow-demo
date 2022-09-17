# deploy Postgres cluster
kubectl wait --for=condition=Ready pod -l app=postgres-operator --timeout=120s
kubectl apply -f resources/postgres/postgres-tap-cluster.yaml --namespace default