
### docs/architecture.md

```markdown
# Architecture

## Overview
- Hub-spoke VNet: hub hosts Firewall, VPN/ExpressRoute; spokes host AKS and data.
- Ingress via Application Gateway WAF (private), terminating TLS, forwarding to AKS.
- Data tier split: transactional (Azure SQL) and catalog/aggregate (Cosmos DB).
- Identities via Managed Identity; secrets via Key Vault; no app secrets in code.

## Resilience
- Zonal AKS node pools; PDBs and HPA; SQL zone redundant.
- Health probes and readiness; rolling updates with surge control.

## Observability
- Log Analytics workspace; Azure Monitor metrics/alerts; SLO alerts defined in ops/alerts.

## Security
- Private endpoints for data; NSGs and Azure Firewall; policy assignments for required tags and disallow public IPs.

## Tradeoffs
- AKS vs App Service: chose AKS for multi-service orchestration and DAPR sidecars.
- SQL vs Cosmos: strong consistency needs in orders, eventual in catalog; dual data strategy.
