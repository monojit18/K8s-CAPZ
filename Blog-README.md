# Managing the UnManaged K8s - CAPZ for rescue!



## Introduction

Cluster API is a Kubernetes community project started by the [Kubernetes Special Interest Group (SIG)](https://github.com/kubernetes/community/tree/master/sig-cluster-lifecycle#readme)  which brings declarative, Kubernetes-style APIs to cluster creation, configuration and management.

The supporting infrastructure on Azure for K8s cluster - like Virtual Machines, Virtual Networks, Load Balancers etc. as well as the Kubernetes cluster configuration are all defined through an YAML configuration file - thus making the K8s management seamless and easy for Infrastructure Architects across various environments.



## High Level Architecture

![capz-hla](./Assets/capz-hla.png)



### Components

#### Management Cluster

- Works as the deployment plane for the CAPZ cluster
- This can be any K8s cluster and can be a simple, light-weight one - e.g. *Kind*, *MicroK8s* etc. This article uses a 3 Nodes AKS cluster, just as an example
- CAPZ cluster configuration templates are applied on this cluster
- *Kubectl* is used to deploy CAPZ templates which in turn deploys the underlying Azure Infrastructure and the K8s cluster on Azure
- Post creation of CAPZ cluster, this management cluster becomes irrelevant except for the Deletion of the CAPZ cluster
  - Deletion of CAPZ cluster can also be done with a shell script as well

#### Virtual Networks

- CAPZ templates would come up with its own VNET config to be used Or one can have BYOVNET - where a custom *Virtual Network* configuration can be specified as well

- One Subnet each for *Master Nodes* and *Worker Nodes*

- Subnet size for Master Plane depends on the number of Master Nodes and 

- Worker Nodes, Number of Pods and Pod sizes as well.

- This article uses a /24 Subnet for Master Nodes and a /24 Subnet for Worker Nodes

  

#### Master Plane

- Consists of Master Nodes
- This article uses 1 Node Master Plane - **Standard_DS2_V2**

#### Worker Plane

- Consists of Worker Nodes
- This article uses 2 Node Worker Plane - **Standard_DS2_V2**

## What are we going to build

- Deploy a simple, light-weight AKS cluster as the Management cluster

- Create necessary infrastructure for the CAPZ K8s cluster

- Deploy an unmanaged K8s cluster on Azure using CAPZ templates

- Secure the K8s cluster with Ingress Controller as Internal Load Balancer

- Deploy one Frontend application (viz. *RatingsWeb*), one Backend application (viz. *RatinsgAPI*) and a MongoDB instance all in this K8s cluster

- Test the flow end to end

  

![capz-deploy-apis](./Assets/capz-deploy-apis.png)



## Let us Get into some Action

### Local variables

```bash
tenantId=""
subscriptionId=""
masterResourceGroup=""
masterVnetName=""
aksResourceGroup=""
location=""
aksClusterName=""
version="<k8s-version>"
aksVnetName=""
aksVnetPrefix=""
aksVnetId=
aksSubnetName=""
aksSubnetPrefix=""
aksSubnetId=
sysNodeSize="Standard_DS2_v2"
sysNodeCount=3
maxSysPods=30
networkPlugin=azure
networkPolicy=azure
sysNodePoolName=
vmSetType=VirtualMachineScaleSets
```



### Prepare & Configure

```bash
# Login to Azure
az login --tenant $tenantId

# Create Service Principal
az ad sp create-for-rbac --skip-assignment -n https://aks-k8s-sp
{
  "appId": "<appId>",
  "displayName": "https://aks-k8s-sp",
  "password": "<password>",
  "tenant": "<tenantId>"
}

spAppId="<appId>"
spPassword="<password>"

# Virtual Network
az network vnet create -n $aksVnetName -g $aksResourceGroup --address-prefixes $aksVnetPrefix
aksVnetId=$(az network vnet show -n $aksVnetName -g $aksResourceGroup --query="id" -o tsv)
echo $aksVnetId

# Subnet for AKS
az network vnet subnet create -n $aksSubnetName --vnet-name $aksVnetName -g $aksResourceGroup --address-prefixes $aksSubnetPrefix
aksSubnetId=$(az network vnet subnet show -n $aksSubnetName --vnet-name $aksVnetName -g $aksResourceGroup --query="id" -o tsv)
echo $aksSubnetId

# Role Assignments
az role assignment create --assignee $spAppId --role "Network Contributor" --scope $aksVnetId
az role assignment create --assignee $spAppId --role "Contributor" --scope "/subscriptions/$subscriptionId"
```



### Deploy Management Cluster

```bash
az aks create --name $aksClusterName \
--resource-group $aksResourceGroup \
--kubernetes-version $version --location $location \
--vnet-subnet-id "$aksSubnetId" \
--node-vm-size $sysNodeSize \
--node-count $sysNodeCount --max-pods $maxSysPods \
--service-principal $spAppId \
--client-secret $spPassword \
--network-plugin $networkPlugin --network-policy $networkPolicy \
--nodepool-name $sysNodePoolName --vm-set-type $vmSetType \
--generate-ssh-keys

# Connect to the Management cluster
az aks get-credentials -g $aksResourceGroup --name $aksClusterName --admin --overwrite
```



### CAPZ - Worker Cluster

#### Define Variables

```bash
capzResourceGroup=capz-k8s-rg
capzClusterName=capz-k8s-cluster
capzVersion="1.22.4"
capzVnetName=capz-k8s-cluster-vnet
capzVnetPrefix=16.0.0.0/21
capzVnetId=
capzMasterSubnetName=capz-master-subnet
capzMasterSubnetPrefix=16.0.0.0/24
capzMasterSubnetId=
capzWorkerSubnetName=capz-worker-subnet
capzWorkerSubnetPrefix=16.0.1.0/24
capzWorkerSubnetId=
capzIngressSubnetName=capz-ingress-subnet
capzIngressSubnetPrefix=16.0.2.0/24
capzIngressSubnetId=
capzAppgwSubnetName=capz-appgw-subnet
capzAppgwSubnetPrefix=16.0.4.0/27
capzAppgwSubnetId=
capzMasterNSGName="capz-control-plane-nsg"
capzworkerNSGName="$clusterName-node-nsg"
aksCapzPeering="$aksVnetName-$capzVnetName-peering"
capzAksPeering="$capzVnetName-$aksVnetName-peering"
masterCapzPeering="$masterVnetName-$capzVnetName-peering"
capzMasterPeering="$capzVnetName-$masterVnetName-peering"
aksCapzPrivateDNSLink="$aksVnetName-capz-dns-link"
masterCapzPrivateDNSLink="$masterVnetName-capz-dns-link"
capzPrivateDNSLink="$capzVnetName-dns-link"
capzIngControllerName="capz-nginx-ing"
capzIngControllerNSName="capz-nginx-ing-ns"
capzIngControllerFileName="internal-ingress"
capzPrivateDNSZoneName="$capzClusterName.capz.io"
privateDNSZoneName="internal.wkshpdev.com"
capzACRName="<ACR to host docker images>"
capzKeyVaultName="capz-workshop-kv"

# Deployment Folder path
baseFolderPath="<baseFolderName>/K8s-CAPZ/Deployments"

# Test Folder path
testFolderPath="<baseFolderName>/K8s-CAPZ/Tests"
```



#### Prepare & Configure

```bash
# Install clusterctl - CAPZ CLI

version=v0.3.20 # latest is 1.1.2 at the time of wrriting this article

# Linux
curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/$version/clusterctl-linux-amd64 -o clusterctl

# MacOS
curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/$version/clusterctl-darwin-amd64 -o clusterctl

chmod +x ./clusterctl
sudo mv ./clusterctl /usr/local/bin/

# Check version
clusterctl version

# Create Service Principalfor CAPZ cluster
az ad sp create-for-rbac --skip-assignment --name http://k8s-capz-sp
{
  "appId": "",
  "displayName": "k8s-capz-sp",
  "name": "http://k8s-capz-sp",
  "password": "",
  "tenant": ""
}

capzSPAppId="<appId>"
capzSPPassword="<password>"

# Create Network and Role assignment

# Virtual Network
az network vnet create -n $capzVnetName -g $capzResourceGroup --address-prefixes $capzVnetPrefix
capzVnetId=$(az network vnet show -n $capzVnetName -g $capzResourceGroup --query="id" -o tsv)
echo $capzVnetId

# Subnet for Master Nodes
az network vnet subnet create -n $capzMasterSubnetName --vnet-name $capzVnetName -g $capzResourceGroup --address-prefixes $capzMasterSubnetPrefix
capzMasterSubnetId=$(az network vnet subnet show -n $capzMasterSubnetName --vnet-name $capzVnetName -g $capzResourceGroup --query="id" -o tsv)
echo $capzMasterSubnetId

# Subnet for Worker Nodes
az network vnet subnet create -n $capzWorkerSubnetName --vnet-name $capzVnetName -g $capzResourceGroup --address-prefixes $capzWorkerSubnetPrefix
capzWorkerSubnetId=$(az network vnet subnet show -n $capzWorkerSubnetName --vnet-name $capzVnetName -g $capzResourceGroup --query="id" -o tsv)
echo $capzWorkerSubnetId

# Subnet for Ingress Controller
az network vnet subnet create -n $capzIngressSubnetName --vnet-name $capzVnetName -g $capzResourceGroup --address-prefixes $capzIngressSubnetPrefix
capzIngressSubnetId=$(az network vnet subnet show -n $capzIngressSubnetName --vnet-name $capzVnetName -g $capzResourceGroup --query="id" -o tsv)
echo $capzIngressSubnetId

# Subnet for Application Gateway
az network vnet subnet create -n $capzAppgwSubnetName --vnet-name $capzVnetName -g $capzResourceGroup --address-prefixes $capzAppgwSubnetPrefix
capzAppgwSubnetId=$(az network vnet subnet show -n $capzAppgwSubnetName --vnet-name $capzVnetName -g $capzResourceGroup --query="id" -o tsv)
echo $capzAppgwSubnetId

# Role Assignments
az role assignment create --assignee $capzSPAppId --role "Network Contributor" --scope $capzVnetId
az role assignment create --assignee $capzSPAppId --role "Contributor" --scope "/subscriptions/$subscriptionId"

# Vnet peerings

# Management Cluster VNET to CAPZ Clsuter VNET
az network vnet peering create -g $capzResourceGroup --remote-vnet $aksVnetId --vnet-name $capzVnetName -n $capzAksPeering --allow-vnet-access

# CAPZ Clsuter VNET to Management Cluster VNET
az network vnet peering create -g $aksResourceGroup --remote-vnet $capzVnetId --vnet-name $aksVnetName -n $aksCapzPeering --allow-vnet-access

# NSG for controlPlane VNET (Needed for Custom VNet options)
az network nsg create -n $capzMasterNSGName -g $capzResourceGroup
az network nsg rule create -n "allow_ssh" --nsg-name $capzMasterNSGName -g $capzResourceGroup --priority 100 --access "Allow" --direction "InBound" --source-address-prefixes "*" --source-port-ranges "*" --destination-address-prefixes "*" --destination-port-ranges "22" --description "Allow SSH"
az network nsg rule create -n "allow_apiserver" --nsg-name $capzMasterNSGName -g $capzResourceGroup --priority 101 --access "Allow" --direction "InBound" --source-address-prefixes "*" --source-port-ranges "*" --destination-address-prefixes "*" --destination-port-ranges "6443" --description "Allow K8s API Server"
az network nsg rule create -n "allow_coredns"  --nsg-name $capzMasterNSGName -g $capzResourceGroup --access "Allow" --direction "Inbound" --priority 102 --destination-port-ranges 8181 --description "Allow CoreDNS"
az network vnet subnet update -g $capzResourceGroup -n $capzMasterSubnetName --vnet-name $capzVnetName --network-security-group $capzMasterNSGName

az network nsg create -n $capzWorkerNSGName -g $capzResourceGroup
az network vnet subnet update -g $capzResourceGroup -n $capzWorkerSubnetName --vnet-name $capzVnetName --network-security-group $capzWorkerNSGName
```



#### Deploy Azure Container Registry (ACR)

```bash
# Create ACR and Role assignment

az acr create -n $capzACRName -g $capzResourceGroup --sku Standard --admin-enabled false
acrId=$(az acr show -n $capzACRName -g $capzResourceGroup --query="id" -o tsv)
az role assignment create --role=AcrPull --assignee=$capzSPAppId --scope=$acrId

# Import Test images into ACR
az acr import -n $capzACRName --source docker.io/library/nginx:alpine -t nginx:alpine
```



#### Deploy Azure KeyVault

```bash
# This is not used by the example here in this article; but it is good to have it as a Best practice
# All Secrets would be stored in KeyVault

# Create KeyVault and Access Policy

az keyvault create -n $capzKeyVaultName -g $capzResourceGroup --sku Standard
objectId=$(az ad user show --id modatta@microsoft.com --query="objectId" -o tsv)

az keyvault set-policy -n $capzKeyVaultName -g $capzResourceGroup --key-permissions get list update create delete \
--secret-permissions get list set delete --certificate-permissions get list update create delete \
--object-id $objectId

keyvaultId=$(az keyvault show -n $capzKeyVaultName -g $capzResourceGroup --query="id" -o tsv)
```



#### Deploy CAPZ Cluster

```bash
# ENV variables needed by CAPZ installation

export AZURE_SUBSCRIPTION_ID=$subscriptionId
export AZURE_TENANT_ID=$tenantId
export AZURE_CLIENT_ID=$capzSPAppId
export AZURE_CLIENT_SECRET=$capzSPPassword
export AZURE_ENVIRONMENT="AzurePublicCloud"
export AZURE_CONTROL_PLANE_MACHINE_TYPE="Standard_D2s_v3"
export AZURE_NODE_MACHINE_TYPE="Standard_D4s_v3"
export AZURE_LOCATION="eastus"

export AZURE_SUBSCRIPTION_ID_B64="$(echo -n "$AZURE_SUBSCRIPTION_ID" | base64 | tr -d '\n')"
export AZURE_TENANT_ID_B64="$(echo -n "$AZURE_TENANT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_ID_B64="$(echo -n "$AZURE_CLIENT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_SECRET_B64="$(echo -n "$AZURE_CLIENT_SECRET" | base64 | tr -d '\n')"

export AZURE_CLUSTER_IDENTITY_SECRET_NAME="cluster-identity-secret"
export CLUSTER_IDENTITY_NAME="cluster-identity"
export AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE="default"

# Cluster Identity Secret
kubectl create secret generic "${AZURE_CLUSTER_IDENTITY_SECRET_NAME}" --from-literal=clientSecret="${AZURE_CLIENT_SECRET}"

# Role Assignment
az role assignment create --role=Contributor --assignee=$capzSPAppId 
--scope=/subscriptions/$AZURE_SUBSCRIPTION_ID

# Initialize the Azure Provider
clusterctl init --infrastructure azure

# Workload cluster config
# Change valeus as necessary
clusterctl generate cluster $capzClusterName --kubernetes-version $capzVersion --control-plane-machine-count=1 --worker-machine-count=2 > capz-k8s-cluster-public.yaml

# Deploy the CAPZ clsuter
kubectl apply -f ./capz-k8s-cluster-public.yaml

# Check status of Workload cluster creation
kubectl get cluster --all-namespaces
clusterctl describe cluster capz-k8s-cluster

# Wait for this command to return all success
kubectl get azuremachines

apiServer=$(kubectl get azurecluster capz-k8s-cluster -o jsonpath='{.spec.controlPlaneEndpoint.host}')
echo $apiServer
```



![capz-deploy-success](./Assets/capz-deploy-success.png)



#### Post Configuration

```bash
# Get kubeconfig for CAPZ installation
clusterctl get kubeconfig $capzClusterName > capz-k8s-cluster.kubeconfig
alias k-capz="k --kubeconfig=$baseFolderPath/Setup/capz-k8s-cluster.kubeconfig"
alias helm-capz="helm --kubeconfig=$baseFolderPath/Setup/capz-k8s-cluster.kubeconfig"

# Install Calico n/w plugin
k-capz apply -f https://raw.githubusercontent.com/kubernetes-sigs/cluster-api-provider-azure/master/templates/addons/calico.yaml

# Add cluster Admin User, Context and make it the Current one
k-capz config set-context $capzClusterName-admin@$capzClusterName --user $capzClusterName-admin \
--cluster $capzClusterName
k-capz config use-context $capzClusterName-admin@$capzClusterName
```



#### Connect to the Cluster

```bash
k-capz config get-contexts
k-capz get no
k-capz get po

# Label Nodes
k-capz label node/<node-name> agentpool=capzsyspool --overwrite
k-capz label node/<node-name> agentpool=capzsyspool --overwrite

# Create Namespaces
k-capz create ns db
k-capz create ns capz-workshop-dev
k-capz create ns $capzIngControllerNSName
k-capz create ns smoke
```



#### Configure CAPZ Cluster

```bash
# Create Other Users - 1 Cluster Admin, 1 Architect/Manager, 1 Developer
k-capz create sa capz-ca-sa
k-capz create sa capz-manager-sa
k-capz create sa capz-developer-sa
k-capz config get-contexts

k-capz get secrets

# Set Cluster Admin Context
k-capz get secrets/<capz-ca-sa-secret_name> -o yaml
token=$(echo <val> | base64 --decode)
k-capz config set-credentials capz-ca-sa --token=$token
k-capz config set-context capz-ca-sa-context --user capz-ca-sa --cluster $capzClusterName

# Switch to Cluster Admin context
k-capz config use-context capz-ca-sa-context

# Set Manager Context
k-capz get secrets/<capz-manager-sa-secret_name> -o yaml
token2=$(echo <val> | base64 --decode)
k-capz config set-credentials capz-manager-sa --token=$token2
k-capz config set-context capz-manager-sa-context --user capz-manager-sa --cluster $capzClusterName

# Switch to Manager context
k-capz config use-context capz-manager-sa-context

# Set Developer Context
k-capz get secrets/<capz-developer-sa-secret_name> -o yaml
token3=$(echo <val> | base64 --decode)
k-capz config set-credentials capz-developer-sa --token=$token3
k-capz config set-context capz-developer-sa-context --user capz-developer-sa --cluster $capzClusterName

# Switch to Developer context
k-capz config use-context capz-developer-sa-context
```



#### Deploy Tools & Services

##### Storage Class

```bash
# Deploy Storage class
helm create sc-chart
helm-capz install sc-chart -n default $baseFolderPath/Helms/sc-chart/ -f $baseFolderPath/Helms/sc-chart/values.yaml

# Deploy RBAC - DEV
helm-capz install rbac-chart -n capz-workshop-dev $baseFolderPath/Helms/rbac-chart/ -f $baseFolderPath/Helms/rbac-chart/values-dev.yaml

# Deploy RBAC - Smoke
helm-capz install rbac-chart -n smoke $baseFolderPath/Helms/rbac-chart/ -f $baseFolderPath/Helms/rbac-chart/values-smoke.yaml
```



#### Ingress Controller

```bash
# Deploy Ingress - DEV
k-capz create secret tls capz-workshop-tls-secret -n capz-workshop-dev --cert="$baseFolderPath/Certs/<cert-file-name>.pem" --key="$baseFolderPath/Certs/<cert-file-name>.key"

helm-capz install ingress-chart -n capz-workshop-dev $baseFolderPath/Helms/ingress-chart/ -f $baseFolderPath/Helms/ingress-chart/values-dev-tls.yaml

# Deploy Ingress - Smoke
k-capz create secret tls capz-workshop-tls-secret -n smoke --cert="$baseFolderPath/Certs/<cert-file-name>.pem" --key="$baseFolderPath/Certs/<cert-file-name>.key"
helm-capz install ingress-chart -n smoke $baseFolderPath/Helms/ingress-chart/ -f $baseFolderPath/Helms/ingress-chart/values-smoke.yaml
```



![capz-get-svc](./Assets/capz-get-svc.png)



#### Deploy & Configure Application Gateway

- Deploy Application Gateway either from Portal or through ARM/Bicep template

- This article does not provide details of how to configure Application Gateway to work with K8s cluster in the backend

- Please refer these links for a detailed discussion

  - [Secure APIs on Azure with AKS and Application Gateway](https://codemongers.wordpress.com/2021/08/11/secure-apis-on-azure-with-aks-and-application-gateway/)
  - [Secure Microservices in AKS with APIM and Application Gateway](https://codemongers.wordpress.com/2022/01/28/secure-microservices-in-aks-with-apim-and-application-gateway/)

- Backend pool points to Private IP of Ingress Controller

  

![capz-appgw-bkpool](./Assets/capz-appgw-bkpool.png)



#### Deploy Microservices

##### Smoke

```bash
# Create Secrets for ACR - Smoke
k-capz create secret docker-registry capz-acr-secret -n smoke --docker-server=$capzACRName.azurecr.io --docker-username=$capzSPAppId --docker-password=$capzSPPassword

# Install Smoke chart - Smoke Namespace
helm-capz install smoke-chart -n smoke $testFolderPath/Helms/smoke-chart/ -f $testFolderPath/Helms/smoke-chart/values-smoke.yaml
```

##### Ratings

###### Ratings API

```bash
# Clone Source code on local environment
git clone https://github.com/monojit18/mslearn-aks-workshop-ratings-api.git

# Bulid and Push dokcer image to ACR
az acr build -t $capzACRName.azurecr.io/ratings-api:v1.0.0 -r $capzACRName .

# Deploy MongoDB container
helm-capz repo add bitnami https://charts.bitnami.com/bitnami

helm-capz install ratingsdb bitnami/mongodb -n db \
--set auth.username=ratingsuser,auth.password=ratingspwd,auth.database=ratingsdb \
--set controller.nodeSelector.agentpool=capzsyspool \
--set controller.defaultBackend.nodeSelector.agentpool=capzsyspool \
--set persistence.storageClass=managed-premium

# Deploy Ratings Api
k-capz create secret generic capz-workshop-mongo-secret -n capz-workshop-dev \
--from-literal=MONGOCONNECTION="mongodb://ratingsuser:ratingspwd@ratingsdb-mongodb.db:27017/ratingsdb"

helm-capz install ratingsapi-chart -n capz-workshop-dev ./ratingsapi-chart/ -f ./ratingsapi-chart/CAPZ/values-dev.yaml

```

###### Ratings Web

```bash
# Clone Source code on local environment
git clone https://github.com/monojit18/mslearn-aks-workshop-ratings-web.git

# Bulid and Push dokcer image to ACR
az acr build -t $capzACRName.azurecr.io/ratings-web:v1.0.0 -r $capzACRName .

helm-capz install ratingsweb-chart -n capz-workshop-dev ./ratingsweb-chart/ -f ./ratingsweb-chart/CAPZ/values-dev.yaml

```



### Test

```bash
In Browser: http(s)://<application-gateway-public-ip-domain-name>/
```



### Cleanup

```bash
kubectl delete cluster $capzClusterName
```



## References

- [CAPZ Introduction](https://cluster-api.sigs.k8s.io/introduction.html)
- [CAPZ Quick Start](https://cluster-api.sigs.k8s.io/user/quick-start.html)
- [K8s docs](https://kubernetes.io/docs/home/)
- [Secure APIs on Azure with AKS and Application Gateway](https://codemongers.wordpress.com/2021/08/11/secure-apis-on-azure-with-aks-and-application-gateway/)
- [Secure Microservices in AKS with APIM and Application Gateway](https://codemongers.wordpress.com/2022/01/28/secure-microservices-in-aks-with-apim-and-application-gateway/)
