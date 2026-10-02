# ==============================================================================
# MÓDULO TERRAFORM: 8 MICROSSERVIÇOS CLOUD RUN (AMBIENTES 'dev' E 'prod')
# Repositório: LATAM-PS-CE-Team/novatlantis-iac (modules/cloud-run-services)
# Importante: O bloco lifecycle.ignore_changes ignora a imagem do container para
#             que os deploys automáticos de novatlantis-app via Cloud Build não
#             sejam revertidos quando o Terraform rodar no novatlantis-iac.
# ==============================================================================

variable "project_id" {
  type        = string
  description = "ID do projeto Google Cloud"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Região do Cloud Run"
}

variable "environment" {
  type        = string
  description = "Nome padronizado do ambiente ('dev' ou 'prod')"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "O nome do ambiente deve ser estritamente 'dev' ou 'prod'."
  }
}

variable "service_prefix" {
  type        = string
  description = "Prefixo dos serviços Cloud Run ('novatlantis-dev' ou 'novatlantis-prod')"
}

variable "workload_sa_email" {
  type        = string
  description = "Service Account de execução dos microsserviços"
}

variable "jwt_secret_id" {
  type        = string
  default     = "novatlantis-internal-jwt-authority"
  description = "ID do segredo JWT no Secret Manager"
}

variable "ar_repo_name" {
  type        = string
  default     = "novatlantis-gov-repo"
}

variable "services" {
  type = set(string)
  default = [
    "landing-portal",
    "citizen-portal",
    "gov-backstage",
    "identity-nid",
    "services-311",
    "emergency-911",
    "health-telemed",
    "education-learn",
    "justice-court-tj"
  ]
}

resource "google_cloud_run_v2_service" "microservices" {
  for_each = var.services
  name     = "${var.service_prefix}-${each.value}"
  location = var.region
  project  = var.project_id
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.workload_sa_email

    scaling {
      min_instance_count = 0
      max_instance_count = 20
    }

    containers {
      # Imagem inicial de bootstrap; atualizada continuamente pelo pipeline de CD (novatlantis-app)
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      env {
        name  = "NODE_ENV"
        value = var.environment == "prod" ? "production" : "development"
      }

      env {
        name  = "NOVATLANTIS_ENV"
        value = var.environment
      }

      env {
        name  = "NOVATLANTIS_SERVICE"
        value = each.value
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "SUPPORTED_LOCALES"
        value = "pt-BR|es-419|en-US"
      }

      env {
        name = "NOVATLANTIS_JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = var.jwt_secret_id
            version = "latest"
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].revision,
      client,
      client_version
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  for_each = google_cloud_run_v2_service.microservices
  project  = var.project_id
  location = var.region
  name     = each.value.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "service_urls" {
  value = {
    for k, svc in google_cloud_run_v2_service.microservices : k => svc.uri
  }
  description = "Mapa de URLs dos 8 microsserviços Cloud Run"
}

output "service_names" {
  value = {
    for k, svc in google_cloud_run_v2_service.microservices : k => svc.name
  }
  description = "Mapa de nomes dos 8 microsserviços Cloud Run"
}
