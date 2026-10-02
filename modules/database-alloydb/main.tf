# ==============================================================================
# MÓDULO TERRAFORM: ALLOYDB FOR POSTGRESQL (CLUSTER SOBERANO + INSTÂNCIA PRIMÁRIA)
# Repositório: LATAM-PS-CE-Team/novatlantis-iac (modules/database-alloydb)
# ==============================================================================

variable "project_id" {
  type        = string
  description = "ID do projeto Google Cloud"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Região do cluster AlloyDB"
}

variable "cluster_id" {
  type        = string
  default     = "novatlantis-sovereign-cluster"
  description = "Identificador do cluster AlloyDB"
}

variable "instance_id" {
  type        = string
  default     = "novatlantis-primary-01"
  description = "Identificador da instância primária AlloyDB"
}

variable "vpc_id" {
  type        = string
  description = "ID da rede VPC com Private Services Access configurado"
}

variable "cpu_count" {
  type        = number
  default     = 2
  description = "Quantidade de vCPUs da instância primária (2, 4, 8, 16...)"
}

resource "google_alloydb_cluster" "sovereign_cluster" {
  cluster_id       = var.cluster_id
  project          = var.project_id
  location         = var.region
  database_version = "POSTGRES_15"

  network_config {
    network = var.vpc_id
  }

  automated_backup_policy {
    location      = var.region
    backup_window = "02:00s"
    enabled       = true

    weekly_schedule {
      days_of_week = ["SUNDAY", "WEDNESDAY"]
      start_times {
        hours   = 2
        minutes = 0
      }
    }

    quantity_based_retention {
      count = 5
    }
  }

  labels = {
    nation     = "novatlantis"
    managed_by = "terraform-gitops"
  }
}

resource "google_alloydb_instance" "primary_instance" {
  cluster       = google_alloydb_cluster.sovereign_cluster.name
  instance_id   = var.instance_id
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = var.cpu_count
  }

  labels = {
    nation     = "novatlantis"
    managed_by = "terraform-gitops"
  }
}

output "cluster_name" {
  value       = google_alloydb_cluster.sovereign_cluster.name
  description = "URI completa do cluster AlloyDB"
}

output "primary_instance_ip" {
  value       = google_alloydb_instance.primary_instance.ip_address
  description = "Endereço IP privado (PSA) da instância primária AlloyDB"
}
