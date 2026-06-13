const VERSION_PLACEHOLDER = "##MODULE_VERSION_LINE##";

const MAIN_TF = `module "project_factory" {
  source = "cilly-yllic/platform/google//modules/project-bootstrap"
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
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}
`;

// removed blocks (Terraform 1.7+) are emitted for envs that were dropped from
// settings.environments but are listed in settings.retained_envs — drop them
// from state without destroying the underlying GCP resources.
function buildRemovedBlock(envKey: string): string {
  return `removed {
  from = module.project_factory["${envKey}"]
  lifecycle {
    destroy = false
  }
}
`;
}

export interface TemplateInput {
  moduleVersion?: string;
  stateRemoveKeys?: string[];
}

export function buildTemplateFiles(
  input: TemplateInput = {}
): Record<string, string> {
  const versionLine = input.moduleVersion
    ? `  version = ${JSON.stringify(input.moduleVersion)}`
    : "";
  const removedBlocks = (input.stateRemoveKeys ?? [])
    .map((k) => buildRemovedBlock(k))
    .join("\n");
  const mainTf =
    MAIN_TF.replace(VERSION_PLACEHOLDER, versionLine) +
    (removedBlocks ? `\n${removedBlocks}` : "");
  return {
    "main.tf": mainTf,
    "versions.tf": VERSIONS_TF,
  };
}
