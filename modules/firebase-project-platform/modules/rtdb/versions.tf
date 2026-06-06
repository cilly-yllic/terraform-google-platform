terraform {
  required_version = ">= 1.10.0"
  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.0, < 8.0"
    }
  }
}
