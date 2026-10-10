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

  app_hosting_compute_sa_roles = var.app_hosting_compute_sa_roles
  default_compute_sa_roles     = var.default_compute_sa_roles

  default_compute_sa_self_roles = var.default_compute_sa_self_roles
}

# Console で Authentication を開始済み (= Identity Platform にアップグレード済み) の
# project では config が既に存在し、create (initializeAuth) が失敗する。
# authentication.import_existing = true のときは既存 config を state に取り込む。
# import block は root module にしか書けないため、module 側ではなくここに置く。
# state に取り込み済みなら import は no-op なので、flag は true のままでよい。
# blocking_functions.managed_by で取り込み先の resource が変わる (deploy 管理は
# ignore_changes 付きの別 resource)。import の to は条件で変えられないので 2 つ書く。
locals {
  auth_import_existing   = try(tobool(var.authentication.import_existing), false)
  auth_bf_deploy_managed = try(var.authentication.blocking_functions.managed_by, "terraform") == "deploy"
}

import {
  for_each = local.auth_import_existing && !local.auth_bf_deploy_managed ? toset(["existing"]) : toset([])

  to = module.firebase_platform.module.auth[0].google_identity_platform_config.this[0]
  id = "projects/\${var.project_id}/config"
}

import {
  for_each = local.auth_import_existing && local.auth_bf_deploy_managed ? toset(["existing"]) : toset([])

  to = module.firebase_platform.module.auth[0].google_identity_platform_config.deploy_managed[0]
  id = "projects/\${var.project_id}/config"
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

variable "app_hosting_compute_sa_roles" {
  type    = list(string)
  default = []
}

variable "default_compute_sa_roles" {
  type    = list(string)
  default = []
}

variable "default_compute_sa_self_roles" {
  type    = list(string)
  default = []
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
      version = ">= 6.0, < 9.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.0, < 9.0"
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
