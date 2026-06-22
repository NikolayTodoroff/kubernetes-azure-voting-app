resource "azurerm_resource_group" "rg_main" {
  name     = "rg-main-${local.prefix}"
  location = var.location
}

module "container_registry" {
  source = "../modules/container-registry"

  prefix              = local.prefix
  resource_group_name = azurerm_resource_group.rg_main.name
  location            = azurerm_resource_group.rg_main.location
  tags                = local.common_tags
}

module "monitoring" {
  source = "../modules/monitoring"

  prefix                       = local.prefix
  location                     = var.location
  resource_group_name          = azurerm_resource_group.rg_main.name
  aks_id                       = module.aks.aks_id
  alert_email                  = var.alert_email
  tags                         = local.common_tags
  log_analytics_sku            = var.log_analytics_sku
  log_analytics_retention_days = var.log_analytics_retention_days
}