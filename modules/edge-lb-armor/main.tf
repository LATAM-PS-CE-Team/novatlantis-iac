# ==============================================================================
# MÓDULO TERRAFORM: CLOUD ARMOR WAF (OWASP TOP 10), SERVERLESS NEGS & SSL
# Repositório: LATAM-PS-CE-Team/novatlantis-iac (modules/edge-lb-armor)
# ==============================================================================

variable "project_id" {
  type        = string
  description = "ID do projeto Google Cloud"
}

variable "region" {
  type        = string
  default     = "us-central1"
}

variable "domain" {
  type        = string
  default     = "novatlantis.gov.cloud"
}

variable "service_names" {
  type        = map(string)
  description = "Mapa (chave -> nome do serviço Cloud Run de prod) para os Serverless NEGs"
}

resource "google_compute_security_policy" "novatlantis_waf" {
  name        = "novatlantis-owasp-waf-policy"
  project     = var.project_id
  description = "Cloud Armor WAF — Proteção OWASP Top 10 e Rate Limiting Anti-DDoS da República Digital de Novatlantis"

  rule {
    action   = "rate_based_ban"
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 300
        interval_sec = 60
      }
      ban_duration_sec = 600
    }
    description = "Rate Limiting Anti-DDoS (300 rpm por IP)"
  }

  rule {
    action   = "deny(403)"
    priority = 2001
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v33-stable')"
      }
    }
    description = "OWASP A03: Bloqueio de SQL Injection"
  }

  rule {
    action   = "deny(403)"
    priority = 2002
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('xss-v33-stable')"
      }
    }
    description = "OWASP A03: Bloqueio de Cross-Site Scripting (XSS)"
  }

  rule {
    action   = "deny(403)"
    priority = 2003
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('lfi-v33-stable')"
      }
    }
    description = "OWASP A01: Bloqueio de Local File Inclusion (LFI)"
  }

  rule {
    action   = "deny(403)"
    priority = 2004
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('rce-v33-stable')"
      }
    }
    description = "OWASP A03: Bloqueio de Remote Code Execution (RCE)"
  }

  rule {
    action   = "deny(403)"
    priority = 2005
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('scannerdetection-v33-stable')"
      }
    }
    description = "OWASP A05: Bloqueio de Scanners Maliciosos"
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Regra padrão de permissão após inspeção WAF"
  }
}

resource "google_compute_managed_ssl_certificate" "novatlantis_tls" {
  name    = "novatlantis-managed-ssl-cert"
  project = var.project_id

  managed {
    domains = [
      var.domain,
      "portal.${var.domain}",
      "backstage.${var.domain}",
      "nid.${var.domain}",
      "311.${var.domain}",
      "911.${var.domain}",
      "health.${var.domain}",
      "edu.${var.domain}"
    ]
  }
}

resource "google_compute_region_network_endpoint_group" "serverless_negs" {
  for_each              = var.service_names
  name                  = "neg-novatlantis-prod-${each.key}"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = each.value
  }
}

resource "google_compute_backend_service" "microservices_backends" {
  for_each              = var.service_names
  name                  = "be-novatlantis-prod-${each.key}"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"
  security_policy       = google_compute_security_policy.novatlantis_waf.id

  custom_request_headers = [
    "X-Client-Geo-Location:{client_region}"
  ]

  backend {
    group = google_compute_region_network_endpoint_group.serverless_negs[each.key].id
  }
}

output "waf_policy_name" {
  value = google_compute_security_policy.novatlantis_waf.name
}

output "managed_ssl_cert_name" {
  value = google_compute_managed_ssl_certificate.novatlantis_tls.name
}
