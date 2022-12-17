# https://cert-manager.io/docs/

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

/* resource "helm_release" "cert_manager" {
  name              = "cert-manager"
  repository        = "https://charts.jetstack.io"
  chart             = "cert-manager"
  namespace         = "cert-manager"
  create_namespace  = "true"
  force_update      = "true"
  dependency_update = "true"
  version           = "v1.10.1"

  set {
    name  = "installCRDs"
    value = "true"
  }
} */

## cert-manager

module "cert_manager_irsa" {
  count   = local.cert_manager ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.5.1"

  role_name = "${var.cluster_name}-cert-manager-role"

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "cert-manager:cert-manager",
      ]
    }
  }
  tags = var.tags
}

data "aws_iam_policy_document" "cert_manager" {
  count = local.cert_manager ? 1 : 0
  statement {
    actions = [
      "route53:GetChange"
    ]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
    ]
    resources = ["arn:aws:route53:::hostedzone/${var.cert_manager_route53_zone_id}"]
  }
}

resource "aws_iam_policy" "cert_manager" {
  count       = local.cert_manager ? 1 : 0
  name        = "AmazonEKS_Cert_Manager_Policy-${var.cluster_name}"
  description = "Provides permissions for cert-manager"
  policy      = data.aws_iam_policy_document.cert_manager[0].json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "cert_manager" {
  count      = local.cert_manager ? 1 : 0
  role       = "${var.cluster_name}-cert-manager-role"
  policy_arn = aws_iam_policy.cert_manager[0].arn
  depends_on = [
    module.cert_manager_irsa[0]
  ]
}

# cert-manager's CRDs are installed outside the Helm chart so resources won't
# be removed if the chart is uninstalled.
resource "null_resource" "cert_manager_crds" {
  count = local.cert_manager ? 1 : 0
  provisioner "local-exec" {
    command = "kubectl --context='${var.cluster_name}' apply --filename='https://github.com/cert-manager/cert-manager/releases/download/v${var.cert_manager_version}/cert-manager.crds.yaml'"
  }
  depends_on = [
    null_resource.eks_kubeconfig,
  ]
}

resource "helm_release" "cert_manager" {
  count            = local.cert_manager ? 1 : 0
  name             = "cert-manager"
  chart            = "https://charts.jetstack.io/charts/cert-manager-v${var.cert_manager_version}.tgz"
  create_namespace = true
  namespace        = "cert-manager"

  # Set up values so that service account has correct annotations and that the
  # pod's security context has permissions to read the account token:
  # https://cert-manager.io/docs/configuration/acme/dns01/route53/#service-annotation
  values = [
    yamlencode({
      "securityContext" = {
        "fsGroup" = 1001
      }
      "serviceAccount" = {
        "annotations" = {
          "eks.amazonaws.com/role-arn" = "arn:aws:iam::${local.aws_account_id}:role/${var.cluster_name}-cert-manager-role"
        }
      }
    })
  ]

  depends_on = [
    module.cert_manager_irsa[0],
    null_resource.cert_manager_crds[0],
  ]
}