#!/bin/bash
# Note: these commands are meant to be run via copy-n-paste, not all at once
#
# Customize these variables for your environment:
RG=keda-sample
LOCATION=westus2
STORAGE_ACCOUNT_NAME=lnckeda2 # must be globally unique
export QUEUE_NAME=keda-queue

az group create -l $LOCATION -n $RG
az storage account create -g $RG -n $STORAGE_ACCOUNT_NAME
export AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string --name $STORAGE_ACCOUNT_NAME --query connectionString -o tsv)
az storage queue create -n $QUEUE_NAME

CLUSTER_NAME="keda3"

az aks create \
 -g $RG \
 -n $CLUSTER_NAME \
 --kubernetes-version 1.21.2 \
 --node-count 1 \
 --node-vm-size Standard_DS3_v2 \
 --generate-ssh-keys \
  --node-osdisk-type Managed \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 10 \
  --network-plugin azure 

az aks get-credentials -g $RG -n $CLUSTER_NAME

# note that the next line doesn't work for ephemeral node pool; requires managed disk node pool
az aks nodepool update --scale-down-mode Deallocate --name nodepool1  --cluster-name $CLUSTER_NAME --resource-group $RG

# install keda
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
kubectl create namespace keda
helm install keda kedacore/keda --version 2.4.0 --namespace keda

# add windows node pool
az aks nodepool add -g $RG --cluster-name $CLUSTER_NAME -n win1  --os-type Windows \
   --enable-cluster-autoscaler --min-count 0 --max-count 10 --scale-down-mode Deallocate

kubectl create secret generic secrets \
    --from-literal=AzureWebJobsStorage=$AZURE_STORAGE_CONNECTION_STRING

####
# build windows container
#windows 
export ACR=lncacr01  # must be unique
az acr create -n $ACR -g $RG --sku Standard
az aks update -n $CLUSTER_NAME -g $RG  --attach-acr $ACR

az acr build -r $ACR -t $ACR.azurecr.io/queue-consumer-windows:4  --platform windows queue-consumer-windows

# Load the KEDA job


#############
# Now run the python app to load up the queue
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

export AzureWebJobsStorage=$AZURE_STORAGE_CONNECTION_STRING

export WORKTIME=5 # 5 seconds
((DEADLINE=$WORKTIME+300))
export DEADLINE
cat azurequeue_scaledobject_jobs_windows.yaml| envsubst | kubectl apply -f -

# run this repeatedly to load the queue
python send_messages.py 100

#########################
export WORKTIME=1800 # 60 * 30 = 1800 seconds = 30 min
((DEADLINE=$WORKTIME+3600))
export DEADLINE
cat azurequeue_scaledobject_jobs_windows.yaml| envsubst | kubectl apply -f -
python send_messages.py 4


####
#####
# Deployments ####
##########

export ACR=lncacr01  # must be unique
az acr create -n $ACR -g $RG --sku Standard
az aks update -n $CLUSTER_NAME -g $RG  --attach-acr $ACR

export TAG=7

az acr build -r $ACR -t $ACR.azurecr.io/queue-consumer-ongoing:$TAG  queue-consumer-ongoing


export WORKTIME=1800 # 60 * 30 = 1800 seconds = 30 min
((DEADLINE=$WORKTIME+3600))
export DEADLINE
cat azurequeue_scaledobject_deployment.yaml| envsubst | kubectl apply -f -
python send_messages.py 4

kubectl logs -f -l app=dequeuer --all-containers=true --prefix=true