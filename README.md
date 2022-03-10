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

- This article uses a /24 Subnet for Master Nodes and 

  

#### Master Plane

#### Worker Plane



## What are we going to build

- Deploy a simple, light-weight AKS cluster on as the Management cluster
- Create necessary infrastructure for the CAPZ K8s cluster
- Deploy an unmanaged K8s cluster on Azure using CAPZ templates
- Secure the K8s cluster with Ingress Controller as Internal Load Balancer
- Deploy one Frontend application (viz. *RatingsWeb*), one Backend application (viz. *RatinsgAPI*) and a MongoDB instance all in this K8s cluster
- Test the flow end to end



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

```



#### Deploy CAPZ Cluster

#### Post Configuration

#### Connect to the Cluster

#### Deploy Tools & Services

#### Deploy Microservices

### Cleanup

