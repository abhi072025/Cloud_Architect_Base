
locals {
  rg_name         = "${var.prefix}-rg"
  vnet_hub_name   = "${var.prefix}-hub-vnet"
  vnet_spoke_name = "${var.prefix}-spoke-vnet"
  aks_name        = "${var.prefix}-aks"
  acr_name        = replace("${var.prefix}acr", "-", "")
  agw_name        = "${var.prefix}-agw"
  kv_name         = "${var.prefix}-kv"
}

resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = var.location
  tags = {
    env  = "dev"
    cost = "archref"
  }
}

# Hub VNet
resource "azurerm_virtual_network" "hub" {
  name                = local.vnet_hub_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Spoke VNet
resource "azurerm_virtual_network" "spoke" {
  name                = local.vnet_spoke_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"]
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_subnet" "agw" {
  name                 = "agw-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.1.2.0/24"]
}

# Peering
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "hub-to-spoke"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id
  allow_forwarded_traffic   = true
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "spoke-to-hub"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_forwarded_traffic   = true
  allow_virtual_network_access = true
}

# Container Registry
resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
}

# Key Vault
resource "azurerm_key_vault" "kv" {
  name                        = local.kv_name
  location                    = var.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = 7
  purge_protection_enabled    = true
  enabled_for_deployment      = true
  enabled_for_template_deployment = true
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

data "azurerm_client_config" "current" {}

# AKS with Managed Identity
resource "azurerm_kubernetes_cluster" "aks" {
  name                = local.aks_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.prefix}-aks"
  kubernetes_version  = "1.29.7"
  default_node_pool {
    name                = "system"
    node_count          = 2
    vm_size             = "Standard_DS3_v2"
    vnet_subnet_id      = azurerm_subnet.aks.id
    type                = "VirtualMachineScaleSets"
    availability_zones  = [1, 2, 3]
    upgrade_settings {
      max_surge = 1
    }
  }
  identity {
    type = "SystemAssigned"
  }
  network_profile {
    network_plugin    = "azure"
    outbound_type     = "userDefinedRouting"
    load_balancer_sku = "standard"
  }
  microsoft_defender {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  }
}

# Log Analytics + Monitor
resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.prefix}-law"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Application Gateway WAF (basic config)
resource "azurerm_public_ip" "agw_pip" {
  name                = "${var.prefix}-agw-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "agw" {
  name                = local.agw_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }
  gateway_ip_configuration {
    name      = "agw-ipcfg"
    subnet_id = azurerm_subnet.agw.id
  }
  frontend_port {
    name = "http"
    port = 80
  }
  frontend_ip_configuration {
    name                 = "pip"
    public_ip_address_id = azurerm_public_ip.agw_pip.id
  }
  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "pip"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }
  request_routing_rule {
    name                       = "rule1"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "aks-pool"
    backend_http_settings_name = "http-settings"
  }
  backend_address_pool {
    name = "aks-pool"
  }
  backend_http_settings {
    name                  = "http-settings"
    port                  = 80
    protocol              = "Http"
    cookie_based_affinity = "Disabled"
    request_timeout       = 30
  }
  waf_configuration {
    enabled                  = true
    firewall_mode            = "Prevention"
    rule_set_version         = "3.2"
  }
}

# SQL Server and DB
resource "random_password" "sql_admin" {
  length  = 20
  special = true
}

resource "azurerm_mssql_server" "sql" {
  name                         = "${var.prefix}-sqlsrv"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = "sqladminuser"
  administrator_login_password = coalesce(var.sql_admin_password, random_password.sql_admin.result)
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_mssql_database" "ordersdb" {
  name                = "ordersdb"
  server_id           = azurerm_mssql_server.sql.id
  sku_name            = "GP_S_Gen5_2"
  zone_redundant      = true
  collation           = "SQL_Latin1_General_CP1_CI_AS"
}

# Cosmos DB (Serverless)
resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "${var.prefix}-cosmos"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  capabilities {
    name = "EnableServerless"
  }
  consistency_policy {
    consistency_level = "Session"
  }
  geo_location {
    location          = var.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "catalogdb" {
  name                = "catalogdb"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
}

resource "azurerm_cosmosdb_sql_container" "products" {
  name                  = "products"
  resource_group_name   = azurerm_resource_group.rg.name
  account_name          = azurerm_cosmosdb_account.cosmos.name
  database_name         = azurerm_cosmosdb_sql_database.catalogdb.name
  partition_key_path    = "/category"
  partition_key_version = 2
}
