terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
    http = {
      source = "hashicorp/http"
    }
  }
  required_version = ">= 0.14"
}