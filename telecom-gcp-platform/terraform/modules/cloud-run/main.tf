# Cloud Run Module - Main Configuration
# Deploys all microservices to Google Cloud Run with load balancing and security

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# Cloud Run Services
resource "google_cloud_run_service" "services" {
  for_each = var.services

  name     = each.value.name
  location = var.region
  project  = var.project_id

  template {
    spec {
      service_account_name = var.service_accounts[each.key]

      containers {
        image = each.value.image

        # Resource allocation
        resources {
          limits = {
            cpu    = var.cpu_limit
            memory = var.memory_limit
          }
          requests = {
            cpu    = each.value.cpu_request
            memory = each.value.memory_request
          }
        }

        # Environment variables for application configuration
        dynamic "env" {
          for_each = merge(var.environment_variables, each.value.env_vars)
          content {
            name  = env.key
            value = env.value
          }
        }

        # Secrets mounted as environment variables
        dynamic "env" {
          for_each = each.value.secret_env_vars
          content {
            name = env.key
            value_from {
              secret_key_ref {
                name = env.value.secret_name
                key  = env.value.secret_version
              }
            }
          }
        }

        # Port configuration
        ports {
          container_port = each.value.container_port
        }

        # Health check configuration
        liveness_probe {
          http_get {
            path   = each.value.health_check_path
            port   = each.value.container_port
            scheme = "HTTP"
          }
          initial_delay_seconds = 10
          period_seconds        = 5
          timeout_seconds       = 3
          failure_threshold     = 3
        }

        startup_probe {
          http_get {
            path   = each.value.health_check_path
            port   = each.value.container_port
            scheme = "HTTP"
          }
          initial_delay_seconds = 30
          period_seconds        = 10
          timeout_seconds       = 5
          failure_threshold     = 5
        }
      }

      # VPC Connector for private network access
      vpc_connector = var.vpc_connector_id
      vpc_connector_egress_settings = "all-traffic"
      timeout_seconds = var.timeout_seconds

      # Service Account for Workload Identity
      service_account = var.service_accounts[each.key]
    }

    # Traffic configuration
    traffic {
      percent         = 100
      latest_revision = true
    }

    # Annotations for Cloud Run
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = tostring(var.min_instances)
        "autoscaling.knative.dev/maxScale" = tostring(var.max_instances)
        "run.googleapis.com/cloudsql-instances" = ""  # Add if using Cloud SQL
        "run.googleapis.com/network-interfaces" = "[{\"network\":\"${var.network_name}\"}]"
      }
    }
  }

  depends_on = [
    google_project_service.required_apis
  ]

  lifecycle {
    ignore_changes = [
      template[0].metadata[0].generation
    ]
  }
}

# Cloud Run IAM - No public access (authenticated only)
resource "google_cloud_run_service_iam_member" "services_authenticated" {
  for_each = var.services

  service       = google_cloud_run_service.services[each.key].name
  location      = var.region
  role          = "roles/run.invoker"
  member        = "serviceAccount:${var.service_accounts[each.key]}"
  depends_on    = [google_cloud_run_service.services]
}

# Network Endpoint Groups for load balancing
resource "google_compute_network_endpoint_group" "services" {
  for_each = var.services

  name                  = "${each.value.name}-neg"
  location              = var.region
  network               = var.network_name
  network_endpoint_type = "SERVERLESS"
  cloud_run_config {
    service = google_cloud_run_service.services[each.key].name
  }

  depends_on = [google_cloud_run_service.services]
}

# Backend Services for load balancing
resource "google_compute_backend_service" "services" {
  for_each = var.services

  name                    = "${each.value.name}-backend"
  project                 = var.project_id
  protocol                = "HTTP2"
  load_balancing_scheme   = "EXTERNAL"
  timeout_sec             = var.timeout_seconds
  enable_cdn              = true
  custom_request_headers  = {
    "X-Client-Region" = "{client_region}"
    "X-Client-Country" = "{client_country}"
  }

  backend {
    group          = google_compute_network_endpoint_group.services[each.key].id
    balancing_mode = "RATE"
    max_rate_per_endpoint = 1000
  }

  # Health check configuration
  health_checks = [google_compute_health_check.services[each.key].id]

  # Circuit breaker configuration
  connection_draining_timeout_sec = 300

  # Session affinity
  session_affinity = "NONE"

  # Logging
  log_config {
    enable      = true
    sample_rate = var.environment == "production" ? 0.1 : 1.0
  }

  depends_on = [
    google_compute_network_endpoint_group.services
  ]
}

# Health Checks
resource "google_compute_health_check" "services" {
  for_each = var.services

  name                = "${each.value.name}-health-check"
  project             = var.project_id
  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    request_path = each.value.health_check_path
    port         = each.value.container_port
    proxy_header = "NONE"
  }

  depends_on = [google_cloud_run_service.services]
}

# SSL Certificate
resource "google_compute_managed_ssl_certificate" "api" {
  name    = "telecom-api-ssl-${var.environment}"
  project = var.project_id

  managed {
    domains = var.api_domains
  }
}

# URL Map for routing
resource "google_compute_url_map" "api" {
  name            = "telecom-api-router-${var.environment}"
  project         = var.project_id
  default_service = google_compute_backend_service.services["user-service"].id

  # Path-based routing for services
  path_rule {
    paths   = ["/user-service/*"]
    service = google_compute_backend_service.services["user-service"].id
  }

  path_rule {
    paths   = ["/billing-service/*"]
    service = google_compute_backend_service.services["billing-service"].id
  }

  path_rule {
    paths   = ["/notification-service/*"]
    service = google_compute_backend_service.services["notification-service"].id
  }

  path_rule {
    paths   = ["/usage-service/*"]
    service = google_compute_backend_service.services["usage-service"].id
  }

  path_rule {
    paths   = ["/analytics-service/*"]
    service = google_compute_backend_service.services["analytics-service"].id
  }

  # Health check redirect
  path_rule {
    paths   = ["/health"]
    service = google_compute_backend_service.services["user-service"].id
  }
}

# HTTPS Proxy
resource "google_compute_target_https_proxy" "api" {
  name            = "telecom-api-proxy-${var.environment}"
  project         = var.project_id
  url_map         = google_compute_url_map.api.id
  ssl_certificates = [google_compute_managed_ssl_certificate.api.id]
  ssl_policy      = google_compute_ssl_policy.modern.id
}

# SSL Policy (strong security)
resource "google_compute_ssl_policy" "modern" {
  name    = "telecom-api-ssl-policy-${var.environment}"
  project = var.project_id

  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

# Global Forwarding Rule
resource "google_compute_global_forwarding_rule" "api" {
  name                  = "telecom-api-forwarding-rule-${var.environment}"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.api.id
  address               = google_compute_global_address.api.id
}

# Static IP Address
resource "google_compute_global_address" "api" {
  name    = "telecom-api-ip-${var.environment}"
  project = var.project_id
}

# Cloud Armor Security Policy
resource "google_compute_security_policy" "cloud_armor" {
  name    = "telecom-cloud-armor-${var.environment}"
  project = var.project_id

  # DDoS protection
  rule {
    action      = "allow"
    priority    = "1"
    description = "Allow all traffic"

    match {
      versioned_expr = "VERSIONED_EXPR_V1"
      expr {
        js_challenge {}
      }
    }
  }

  # Rate limiting (requests per minute)
  rule {
    action      = "rate_based_ban"
    priority    = "100"
    description = "Rate limit rule"

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      rate_limit_threshold {
        count        = 1000
        interval_sec = 60
      }
      ban_duration_sec = 300
    }

    match {
      versioned_expr = "VERSIONED_EXPR_V1"
      expr {
        js_challenge {}
      }
    }
  }

  # Geographic restriction (if needed)
  rule {
    action      = "allow"
    priority    = "2000"
    description = "Default allow"

    match {
      versioned_expr = "VERSIONED_EXPR_V1"
      expr {
        js_challenge {}
      }
    }
  }
}

# Attach Cloud Armor to backend services
resource "google_compute_backend_service_security_policy" "services" {
  for_each = var.services

  name            = "${each.value.name}-security-policy"
  security_policy = google_compute_security_policy.cloud_armor.id
  backend_service = google_compute_backend_service.services[each.key].name

  depends_on = [google_compute_backend_service.services]
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  service            = each.value
  disable_on_destroy = false
}

# Outputs
output "service_urls" {
  description = "Cloud Run service URLs"
  value = {
    for k, v in google_cloud_run_service.services :
    k => v.status[0].url
  }
}

output "load_balancer_url" {
  description = "Load balancer public URL"
  value       = "https://${google_compute_global_address.api.address}"
}

output "backend_services" {
  description = "Backend service IDs for monitoring"
  value = {
    for k, v in google_compute_backend_service.services :
    k => v.id
  }
}
