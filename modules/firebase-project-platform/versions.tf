terraform {
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
    # API 有効化の伝播待ち (time_sleep) に使用。詳細は main.tf: time_sleep.api_propagation
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
