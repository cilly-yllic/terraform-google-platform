const VERSION_PLACEHOLDER = "##MODULE_VERSION_LINE##";

const MAIN_TF = `module "firebase_platform" {
  source = "cilly-yllic/platform/google//modules/firebase-project-platform"
${VERSION_PLACEHOLDER}

  project_id = var.project_id
  region     = var.region

  firebase        = var.firebase
  authentication  = var.authentication
  rtdb            = var.rtdb
  storage         = var.storage
  apps            = var.apps
  hosting         = var.hosting
  app_hosting     = var.app_hosting
  firestore       = var.firestore
  data_connect    = var.data_connect
  fcm             = var.fcm
  remote_config   = var.remote_config
  app_check       = var.app_check
  crashlytics     = var.crashlytics
  performance     = var.performance
  analytics       = var.analytics
  extensions      = var.extensions
  secret_manager  = var.secret_manager
  cloud_tasks     = var.cloud_tasks
  cloud_scheduler = var.cloud_scheduler
  pubsub          = var.pubsub
  eventarc        = var.eventarc
  cloud_run       = var.cloud_run
  cloud_functions = var.cloud_functions

  additional_apis    = var.additional_apis
  users              = var.users
  ci_service_account = var.ci_service_account
  service_accounts   = var.service_accounts
  github_connection  = var.github_connection
  github_oauth_token = var.github_oauth_token

  github_app_installation_id = var.github_app_installation_id
  app_hosting_repo           = var.app_hosting_repo
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-northeast1"
}

variable "firebase" {
  type    = any
  default = null
}

variable "authentication" {
  type    = any
  default = null
}

variable "firestore" {
  type    = any
  default = null
}

variable "rtdb" {
  type    = any
  default = null
}

variable "storage" {
  type    = any
  default = null
}

variable "apps" {
  type    = any
  default = null
}

variable "hosting" {
  type    = any
  default = null
}

variable "app_hosting" {
  type    = any
  default = null
}

variable "data_connect" {
  type    = any
  default = null
}

variable "fcm" {
  type    = any
  default = null
}

variable "remote_config" {
  type    = any
  default = null
}

variable "app_check" {
  type    = any
  default = null
}

variable "crashlytics" {
  type    = any
  default = null
}

variable "performance" {
  type    = any
  default = null
}

variable "analytics" {
  type    = any
  default = null
}

variable "extensions" {
  type    = any
  default = null
}

variable "secret_manager" {
  type    = any
  default = null
}

variable "cloud_tasks" {
  type    = any
  default = null
}

variable "cloud_scheduler" {
  type    = any
  default = null
}

variable "pubsub" {
  type    = any
  default = null
}

variable "eventarc" {
  type    = any
  default = null
}

variable "cloud_run" {
  type    = any
  default = null
}

variable "cloud_functions" {
  type    = any
  default = null
}

variable "additional_apis" {
  type    = list(string)
  default = []
}

variable "users" {
  type    = any
  default = []
}

variable "ci_service_account" {
  type    = any
  default = null
}

variable "service_accounts" {
  type    = any
  default = []
}

variable "github_connection" {
  type    = any
  default = null
}

variable "github_oauth_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "github_app_installation_id" {
  type    = string
  default = ""
}

variable "app_hosting_repo" {
  type    = string
  default = ""
}
`;

const VERSIONS_TF = `terraform {
  required_version = ">= 1.10.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.0, < 8.0"
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
