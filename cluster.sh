kubectl create namespace traefik
helm install --namespace=traefik traefik traefik/traefik --values=traefik/files/values.yaml
kubectl get svc --all-namespaces -o wide
kubectl apply -f traefik/files/manifests/default-headers.yaml
kubectl apply -f traefik/files/manifests/secret-dashboard.yaml
kubectl get secrets --namespace traefik
kubectl apply -f traefik/files/manifests/middleware.yaml
kubectl get middleware
kubectl create namespace cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.crds.yaml
helm install cert-manager jetstack/cert-manager --namespace cert-manager --values=cert-manager/files/values.yaml --version v1.13.1
kubectl get pods --namespace cert-manager
kubectl apply -f cert-manager/files/manifests/secret-cf-token.yaml
kubectl apply -f cert-manager/files/manifests/letsencrypt-staging-issuer.yaml


kubectl apply -f traefik-dashboard/files/manifests/ingress.yaml

kubectl apply -f cert-manager/files/manifests/traefik-moerman-online-staging.yaml
kubectl get challenges

kubectl apply -f traefik-dashboard/files/manifests/ingress.yaml

^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
