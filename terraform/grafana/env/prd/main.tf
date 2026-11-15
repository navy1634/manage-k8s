resource "grafana_apps_dashboard_dashboard_v1beta1" "argocd" {
  metadata {
    uid = "argocd-platform"
  }

  spec {
    json = file("${path.module}/dashboards/argocd.json")
  }

  options {
    allow_ui_updates = false
  }
}

resource "grafana_apps_dashboard_dashboard_v1beta1" "cilium" {
  metadata {
    uid = "cilium-platform"
  }

  spec {
    json = file("${path.module}/dashboards/cilium.json")
  }

  options {
    allow_ui_updates = false
  }
}
