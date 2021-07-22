terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    http = {
      source = "hashicorp/http"
    }
  }
  required_version = ">= 0.14"
}