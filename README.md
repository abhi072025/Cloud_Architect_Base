# Cloud_Architect_Base

This repo delivers a production-grade Azure architecture using AKS, private Application Gateway, Cosmos DB, Azure SQL, DAPR, Key Vault, Managed Identity, and Azure Monitor. It deploys with Terraform or Bicep and ships CI/CD via Azure DevOps.

## Highlights
- Private networking with hub-spoke, Firewall, and Application Gateway WAF.
- Secure identities: Managed Identity for workloads, Key Vault for secrets.
- Multi-service app with orders (Python) and catalog (Node) behind an NGINX gateway.
- Observability: Log Analytics, Azure Monitor alerts, SLOs, and HPA.
- Two IaC flavors: Terraform (primary) and Bicep (reference).

## Quick start (Terraform)
```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
cd infra/terraform
terraform init
terraform apply -auto-approve -var 'prefix=archref' -var 'location=southindia'
ct_Base
