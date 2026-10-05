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

variable "environment" {
  type        = string
  default     = "prod"
  description = "Ambiente ('dev' ou 'prod')"
}

variable "domain" {
  type        = string
  default     = "gov.novatlantis.cloud"
  description = "Domínio principal do ambiente (gov.novatlantis.cloud em prod, dev.gov.novatlantis.cloud em dev)"
}

variable "service_names" {
  type        = map(string)
  description = "Mapa (chave -> nome do serviço Cloud Run) para os Serverless NEGs"
}

resource "google_compute_global_address" "lb_ipv4" {
  name         = "novatlantis-${var.environment}-lb-ipv4"
  project      = var.project_id
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  description  = "IP Global Anycast para ${var.domain} (${var.environment})"
}

resource "google_compute_security_policy" "novatlantis_waf" {
  name        = "novatlantis-${var.environment}-owasp-waf-policy"
  project     = var.project_id
  description = "Cloud Armor WAF — Proteção OWASP Top 10 e Rate Limiting Anti-DDoS da República Digital de Novatlantis (${var.environment})"

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
  name    = "novatlantis-${var.environment}-managed-ssl-cert"
  project = var.project_id

  managed {
    domains = [
      var.domain,
      "portal.${var.domain}",
      "cidadao.${var.domain}",
      "backstage.${var.domain}",
      "nid.${var.domain}",
      "311.${var.domain}",
      "911.${var.domain}",
      "health.${var.domain}",
      "edu.${var.domain}",
      "tj.${var.domain}"
    ]
  }
}

resource "google_compute_region_network_endpoint_group" "serverless_negs" {
  for_each              = var.service_names
  name                  = "neg-novatlantis-${var.environment}-${each.key}"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = each.value
  }
}

resource "google_compute_backend_service" "microservices_backends" {
  for_each              = var.service_names
  name                  = "be-novatlantis-${var.environment}-${each.key}"
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

resource "google_compute_url_map" "novatlantis_url_map" {
  name            = "novatlantis-${var.environment}-url-map"
  project         = var.project_id
  default_service = google_compute_backend_service.microservices_backends["landing-portal"].id

  host_rule {
    hosts        = [var.domain]
    path_matcher = "landing-matcher"
  }

  host_rule {
    hosts        = ["portal.${var.domain}", "cidadao.${var.domain}"]
    path_matcher = "citizen-matcher"
  }

  host_rule {
    hosts        = ["backstage.${var.domain}"]
    path_matcher = "backstage-matcher"
  }

  host_rule {
    hosts        = ["tj.${var.domain}"]
    path_matcher = "tj-matcher"
  }

  host_rule {
    hosts        = ["nid.${var.domain}"]
    path_matcher = "nid-matcher"
  }

  host_rule {
    hosts        = ["311.${var.domain}"]
    path_matcher = "s311-matcher"
  }

  host_rule {
    hosts        = ["911.${var.domain}"]
    path_matcher = "s911-matcher"
  }

  host_rule {
    hosts        = ["health.${var.domain}"]
    path_matcher = "health-matcher"
  }

  host_rule {
    hosts        = ["edu.${var.domain}"]
    path_matcher = "edu-matcher"
  }

  path_matcher {
    name            = "landing-matcher"
    default_service = google_compute_backend_service.microservices_backends["landing-portal"].id
  }

  path_matcher {
    name            = "citizen-matcher"
    default_service = google_compute_backend_service.microservices_backends["citizen-portal"].id
  }

  path_matcher {
    name            = "backstage-matcher"
    default_service = google_compute_backend_service.microservices_backends["gov-backstage"].id
  }

  path_matcher {
    name            = "tj-matcher"
    default_service = google_compute_backend_service.microservices_backends["justice-court-tj"].id
  }

  path_matcher {
    name            = "nid-matcher"
    default_service = google_compute_backend_service.microservices_backends["identity-nid"].id
  }

  path_matcher {
    name            = "s311-matcher"
    default_service = google_compute_backend_service.microservices_backends["services-311"].id
  }

  path_matcher {
    name            = "s911-matcher"
    default_service = google_compute_backend_service.microservices_backends["emergency-911"].id
  }

  path_matcher {
    name            = "health-matcher"
    default_service = google_compute_backend_service.microservices_backends["health-telemed"].id
  }

  path_matcher {
    name            = "edu-matcher"
    default_service = google_compute_backend_service.microservices_backends["education-learn"].id
  }
}

resource "google_compute_target_http_proxy" "novatlantis_http_proxy" {
  name    = "novatlantis-${var.environment}-http-proxy"
  project = var.project_id
  url_map = google_compute_url_map.novatlantis_url_map.id
}

resource "google_compute_global_forwarding_rule" "novatlantis_http_forwarding_rule" {
  name                  = "novatlantis-${var.environment}-http-fw-rule"
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.novatlantis_http_proxy.id
  ip_address            = google_compute_global_address.lb_ipv4.id
}

resource "google_compute_target_https_proxy" "novatlantis_https_proxy" {
  name             = "novatlantis-${var.environment}-https-proxy"
  project          = var.project_id
  url_map          = google_compute_url_map.novatlantis_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.novatlantis_tls.id]
}

resource "google_compute_global_forwarding_rule" "novatlantis_https_forwarding_rule" {
  name                  = "novatlantis-${var.environment}-https-fw-rule"
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.novatlantis_https_proxy.id
  ip_address            = google_compute_global_address.lb_ipv4.id
}

output "lb_ip_address" {
  value       = google_compute_global_address.lb_ipv4.address
  description = "IP Público Global Anycast do Load Balancer para apontamento DNS no GoDaddy"
}

output "waf_policy_name" {
  value = google_compute_security_policy.novatlantis_waf.name
}

output "managed_ssl_cert_name" {
  value = google_compute_managed_ssl_certificate.novatlantis_tls.name
}

output "custom_domain_urls" {
  value = {
    home_landing_portal = "https://${var.domain}"
    citizen_portal      = "https://portal.${var.domain}"
    gov_backstage       = "https://backstage.${var.domain}"
  }
}
