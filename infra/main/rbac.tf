resource "azurerm_role_assignment" "acr_kubernetes_pull" {
  scope                = module.container_registry.acr_id
  role_definition_name = "AcrPull"
  principal_id         = module.azurerm_kubernetes_cluster.k8s_cluster.kubelet_identity[0].object_id
}
