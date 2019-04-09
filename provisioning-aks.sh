RESOURCEGROUP=myResourceGroup
LOCATION=southeastasia
CLUSTERNAME=aksdevops
DNSNAME=pbaksdevops

az group create --name $RESOURCEGROUP --location $LOCATION

az aks create --resource-group $RESOURCEGROUP --name $CLUSTERNAME \
    --node-count 1 --enable-addons monitoring --generate-ssh-keys
#Install kubectl cli
az aks install-cli
#get credentials for created cluster
az aks get-credentials --resource-group $RESOURCEGROUP --name $CLUSTERNAME
#Install helm tiller in the kubernetes cluster
helm init
NODERESOURCEGROUP=$(az aks show --resource-group $RESOURCEGROUP --name $CLUSTERNAME --query nodeResourceGroup -o tsv)

kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'

#Install niginx ingress
helm install stable/nginx-ingress \
    --namespace kube-system \
    --set controller.replicaCount=2 

PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$IP')].[id]" --output tsv)

az network public-ip update --ids $PUBLICIPID --dns-name $DNSNAME

# Install cert manager
kubectl label namespace kube-system certmanager.k8s.io/disable-validation=true
kubectl apply \
    -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.6/deploy/manifests/00-crds.yaml

helm install stable/cert-manager \
    --namespace kube-system \
    --set ingressShim.defaultIssuerName=letsencrypt-staging \
    --set ingressShim.defaultIssuerKind=ClusterIssuer \
    --version v0.6.6

kubectl apply -f cluster-issuer.yaml

kubectl apply -f certificates.yaml \
    --set dnsNames=$DNSNAME \
    --set acme.config.domains=$DNSNAME

# Deploy Jenkins
helm install stable/jenkins \
    -f jenkins.yaml \
    --set ingress.tls.hosts=$DNSNAME