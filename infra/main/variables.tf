
variable "app_name" {
  description = "Name of the application"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "admin_username" {
  description = "Admin username for VMSS instances"
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key content for VMSS admin access"
  type        = string
}

variable "local_ip_address" {
  description = "Local IP allowed through the Key Vault network ACL for local terraform runs"
  type        = string
}

variable "pipeline_sp_object_id" {
  description = "Object ID of the pipeline's service principal"
  type        = string
}

variable "aks_id" {
  description = "Resource ID of the AKS cluster"
  type        = string
}

variable "log_analytics_sku" {
  description = "Log Analytics Workspace SKU"
  type        = string
  default     = "PerGB2018"
}

variable "log_analytics_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 30
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
}

