variable "grafana_url" {
  description = "Terraform が接続する Grafana API endpoint"
  type        = string
  default     = "https://grafana.navy1634.com/"
}

variable "grafana_auth" {
  description = "Grafana dashboard の読み書きに使う service account token"
  type        = string
  sensitive   = true
}
