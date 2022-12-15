resource "helm_release" "cert_manager" {
  name              = "cert-manager"
  repository        = "https://charts.jetstack.io"
  chart             = "cert-manager"
  namespace         = "cert-manager"
  create_namespace  = "true"
  force_update      = "true"
  dependency_update = "true"
  version           = "v1.4.0"

  set {
    name  = "webhook.securePort"
    value = "10260"
  }
  set {
    name  = "installCRDs"
    value = "true"
  }
}