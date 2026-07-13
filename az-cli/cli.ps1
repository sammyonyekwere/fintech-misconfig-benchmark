az group create --name rg-tfstate --location westeurope

az storage account create `
    --name sttfstatembf `
    --resource-group rg-tfstate `
    --sku Standard_LRS `
    --encryption-service blob

az storage container create `
    --name tfstate `
    --account-name sttfstatembf