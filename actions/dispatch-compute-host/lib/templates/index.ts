const VERSION_PLACEHOLDER = "##MODULE_VERSION_LINE##";

// 変数は settings.yml の compute_host に書いたキーだけを TFC に同期する（書いていないキーはここの既定値 =
// モジュールの既定値になる。消したキーの TFC 変数は syncVariables が消す）
const MAIN_TF = `module "compute_host" {
  source = "cilly-yllic/platform/google//modules/compute-host-platform"
${VERSION_PLACEHOLDER}

  project_id           = var.project_id
  region               = var.region
  apis                 = var.apis
  api_propagation_wait = var.api_propagation_wait

  network        = var.network
  firewall_rules = var.firewall_rules
  cloud_nat      = var.cloud_nat

  service_accounts    = var.service_accounts
  service_account_iam = var.service_account_iam
  custom_roles        = var.custom_roles
  iam_bindings        = var.iam_bindings
}

output "compute_host" {
  value = {
    network_id       = module.compute_host.network_id
    subnets          = module.compute_host.subnets
    service_accounts = module.compute_host.service_accounts
    custom_roles     = module.compute_host.custom_roles
    cloud_nat        = module.compute_host.cloud_nat
  }
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-northeast1"
}

variable "apis" {
  type    = list(string)
  default = []
}

variable "api_propagation_wait" {
  type    = string
  default = "60s"
}

variable "network" {
  type    = any
  default = null
}

variable "firewall_rules" {
  type    = any
  default = []
}

variable "cloud_nat" {
  type    = any
  default = null
}

variable "service_accounts" {
  type    = any
  default = []
}

variable "service_account_iam" {
  type    = any
  default = []
}

variable "custom_roles" {
  type    = any
  default = []
}

variable "iam_bindings" {
  type    = any
  default = []
}
`;

const VERSIONS_TF = `terraform {
  required_version = ">= 1.10.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 9.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
`;

export function buildTemplateFiles(
  moduleVersion: string | undefined,
): Record<string, string> {
  const versionLine = moduleVersion
    ? `  version = ${JSON.stringify(moduleVersion)}`
    : "";
  return {
    "main.tf": MAIN_TF.replace(VERSION_PLACEHOLDER, versionLine),
    "versions.tf": VERSIONS_TF,
  };
}
