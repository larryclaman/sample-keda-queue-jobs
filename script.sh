#!/bin/bash
# Note: these commands are meant to be run via copy-n-paste, not all at once
#
# Customize these variables for your environment:
RG=rg-contoso-video
LOCATION=westus2
CLUSTER_NAME=kedastest
STORAGE_ACCOUNT_NAME=lnckeda1 # must be globally unique
export QUEUE_NAME=keda-queue

az aks create \
 -g $RG \
 -n $CLUSTER_NAME \
 --node-count 1 \
 --node-vm-size Standard_DS3_v2 \
 --generate-ssh-keys \
 --node-osdisk-type Ephemeral \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 10

az aks get-credentials -g $RG -n $CLUSTER_NAME


# install keda
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
kubectl create namespace keda
helm install keda kedacore/keda --version 2.4.0 --namespace keda


az group create -l $LOCATION -n $RG
az storage account create -g $RG -n $STORAGE_ACCOUNT_NAME
export AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string --name $STORAGE_ACCOUNT_NAME --query connectionString -o tsv)
az storage queue create -n $QUEUE_NAME


kubectl create secret generic secrets \
    --from-literal=AzureWebJobsStorage=$AZURE_STORAGE_CONNECTION_STRING
kubectl apply -f azurequeue_scaledobject_jobs.yaml

#############
# Repeat the above, but this time on a cluster that has CA set to deallocate rather than delete
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

export AzureWebJobsStorage=$AZURE_STORAGE_CONNECTION_STRING

# run this repeatedly
python send_messages.py 100

#### Try out scale-down mode
# https://docs.microsoft.com/en-us/azure/aks/scale-down-mode

CLUSTER_NAME="dellocatetest"

az aks create \
 -g $RG \
 -n $CLUSTER_NAME \
 --node-count 1 \
 --node-vm-size Standard_DS3_v2 \
 --generate-ssh-keys \
  --node-osdisk-type Managed \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 10

az aks nodepool update --scale-down-mode Deallocate --name nodepool1  --cluster-name $CLUSTER_NAME --resource-group $RG
  # -> doesn't work for ephemeral node pool

az aks get-credentials -g $RG -n $CLUSTER_NAME

# install keda
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
kubectl create namespace keda
helm install keda kedacore/keda --version 2.4.0 --namespace keda

export QUEUE_NAME=keda-queue
#az group create -l $LOCATION -n $RG
#az storage account create -g $RG -n $STORAGE_ACCOUNT_NAME
export AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string --name $STORAGE_ACCOUNT_NAME --query connectionString -o tsv)
az storage queue create -n $QUEUE_NAME

kubectl create secret generic secrets \
    --from-literal=AzureWebJobsStorage=$AZURE_STORAGE_CONNECTION_STRING
kubectl apply -f azurequeue_scaledobject_jobs.yaml

python send_messages.py 100
