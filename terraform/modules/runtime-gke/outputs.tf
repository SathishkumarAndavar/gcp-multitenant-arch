output "cluster_name" { value = google_container_cluster.this.name }
output "cluster_location" { value = google_container_cluster.this.location }
# Feed these to `helm upgrade --install <product> helm/charts/product -f -`
output "helm_values" {
  value = { for p, v in var.products : p => {
    image          = { repository = "${var.registry}/${p}", tag = v.version }
    serviceAccount = { gsa = v.service_account }
    customer       = var.customer
    env            = var.env
    config         = v.config
  } }
}
output "node_sa_member" { value = "serviceAccount:${google_service_account.nodes.email}" }
