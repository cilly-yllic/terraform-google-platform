const VERSION_PLACEHOLDER = "##MODULE_VERSION_LINE##";

const MAIN_TF = `module "project_factory" {
  source = "cilly-yllic/project-bootstrap/google"
${VERSION_PLACEHOLDER}
  for_each = jsondecode(var.environments)

  project_id                   = each.value.project_id
  project_name                 = lookup(each.value, "project_name", each.value.project_id)
  billing_account_id           = each.value.billing_account_id
  terraform_service_account_id = each.value.terraform_service_account_id
  tfc_workspace_name           = each.value.tfc_workspace_name

  org_id    = try(jsondecode(var.parent).organization_id, null)
  folder_id = try(jsondecode(var.parent).folder_id, null)

  bootstrap_project_id          = var.bootstrap_project_id
  workload_identity_pool_id     = var.workload_identity_pool_id
  workload_identity_provider_id = var.workload_identity_provider_id
}

variable "service" {
  type = string
}

variable "environments" {
  description = "JSON string keyed by environment name. Synced by the dispatch-project-bootstrap Action."
  type        = string
}

variable "parent" {
  description = "JSON string holding organization_id or folder_id."
  type        = string
  default     = "{}"
}

variable "bootstrap_project_id" {
  type = string
}

variable "workload_identity_pool_id" {
  type = string
}

variable "workload_identity_provider_id" {
  type = string
}
`;

const VERSIONS_TF = `terraform {
  required_version = ">= 1.3"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}
`;

export function buildTemplateFiles(
  moduleVersion: string | undefined
): Record<string, string> {
  const versionLine = moduleVersion ? `  version = ${JSON.stringify(moduleVersion)}` : "";
  return {
    "main.tf": MAIN_TF.replace(VERSION_PLACEHOLDER, versionLine),
    "versions.tf": VERSIONS_TF,
  };
}
