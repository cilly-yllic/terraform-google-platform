const VERSION_PLACEHOLDER = "##MODULE_VERSION_LINE##";

const MAIN_TF = `module "firebase_platform" {
  source = "cilly-yllic/firebase-project-platform/google"
${VERSION_PLACEHOLDER}

  project_id = var.project_id
  region     = var.region

  firebase        = var.firebase
  authentication  = var.authentication
  firestore       = var.firestore
  rtdb            = var.rtdb
  storage         = var.storage
  web_app         = var.web_app
  hosting         = var.hosting
  app_hosting     = var.app_hosting
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

variable "web_app" {
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
