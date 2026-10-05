# ==============================================================================
# MÓDULO TERRAFORM: REDE VPC SOBERANA & PRIVATE SERVICES ACCESS (PSA)
# Repositório: LATAM-PS-CE-Team/novatlantis-iac (modules/networking)
# ==============================================================================

variable "project_id" {
  type        = string
  description = "ID do projeto Google Cloud"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Região primária da sub-rede"
}

variable "vpc_name" {
  type        = string
  default     = "novatlantis-vpc"
  description = "Nome da VPC Soberana"
}

variable "subnet_cidr" {
  type        = string
  default     = "10.10.0.0/20"
  description = "Bloco CIDR da sub-rede regional"
}

resource "google_compute_network" "sovereign_vpc" {
  name                    = var.vpc_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Rede VPC Soberana da República Digital de Novatlantis"
}

resource "google_compute_subnetwork" "primary_subnet" {
  name                     = "${var.vpc_name}-${var.region}"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.sovereign_vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

variable "enable_psa" {
  type        = bool
  default     = false
  description = "Habilita Private Services Access (PSA) para AlloyDB"
}

resource "google_compute_global_address" "alloydb_psa_range" {
  count         = var.enable_psa ? 1 : 0
  name          = "novatlantis-alloydb-psa"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.sovereign_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = var.enable_psa ? 1 : 0
  network                 = google_compute_network.sovereign_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.alloydb_psa_range[0].name]
}

output "vpc_id" {
  value       = google_compute_network.sovereign_vpc.id
  description = "ID completo da VPC Soberana"
}

output "vpc_name" {
  value       = google_compute_network.sovereign_vpc.name
  description = "Nome da VPC Soberana"
}

output "subnet_id" {
  value       = google_compute_subnetwork.primary_subnet.id
  description = "ID da sub-rede regional"
}
