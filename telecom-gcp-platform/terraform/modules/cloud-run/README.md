# Cloud Run Module

Manages Google Cloud Run services for the Telecom Microservices Platform with production-grade configurations including auto-scaling, health checks, load balancing, and security.

## Features

- **Serverless Compute**: Deploy containerized microservices without infrastructure management
- **Auto-Scaling**: CPU/memory-based scaling from 1 to N instances
- **Network Security**: VPC connector for private database access, Cloud Armor integration
- **Load Balancing**: Global HTTP(S) load balancer with health checks and path-based routing
- **SSL/TLS**: Managed SSL certificates with automatic renewal
- **Secrets Integration**: Access secrets from Secret Manager as environment variables
- **Monitoring**: Integrated Cloud Logging, Trace, and Monitoring
- **High Availability**: Multi-region failover capabilities
- **Security**: Cloud Armor DDoS/WAF protection, service account per service

## Usage

### Basic Example

```hcl
module "cloud_run" {
  source = "./modules/cloud-run"

  project_id       = "my-project"
  region          = "us-central1"
  environment     = "production"
  network_name    = "telecom-vpc"
  vpc_connector_id = module.networking.vpc_connector_id

  services = {
    "user-service" = {
      name                = "user-service"
      image               = "gcr.io/my-project/user-service:v1.0.0"
      container_port      = 8080
      health_check_path   = "/health"
      cpu_request         = "100m"
      memory_request      = "128Mi"
      env_vars            = {}
      secret_env_vars = {
        "DB_PASSWORD" = { secret_name = "db-password", secret_version = "latest" }
      }
    }
  }

  min_instances = 1
  max_instances = 100
  memory_limit  = "512Mi"
  cpu_limit     = "1"

  service_accounts = {
    "user-service" = "user-service-sa@my-project.iam.gserviceaccount.com"
  }

  api_domains = ["api.example.com"]
}
```

### Advanced Example with Multiple Services

```hcl
module "cloud_run" {
  source = "./modules/cloud-run"

  project_id       = "telecom-app-production"
  region          = "us-central1"
  environment     = "production"
  network_name    = "telecom-vpc"
  vpc_connector_id = module.networking.vpc_connector_id

  services = {
    "user-service" = {
      name                = "user-service"
      image               = "gcr.io/telecom-app-production/user-service:latest"
      container_port      = 8080
      health_check_path   = "/health"
      cpu_request         = "100m"
      memory_request      = "128Mi"
      env_vars = {
        LOG_LEVEL = "INFO"
        ENABLE_TRACING = "true"
      }
      secret_env_vars = {
        "DB_PASSWORD" = { secret_name = "db-password", secret_version = "latest" }
        "JWT_KEY" = { secret_name = "jwt-signing-key", secret_version = "latest" }
      }
    }
    
    "billing-service" = {
      name                = "billing-service"
      image               = "gcr.io/telecom-app-production/billing-service:latest"
      container_port      = 8080
      health_check_path   = "/ready"
      cpu_request         = "200m"
      memory_request      = "256Mi"
      env_vars = {
        LOG_LEVEL = "INFO"
      }
      secret_env_vars = {
        "DB_PASSWORD" = { secret_name = "db-password", secret_version = "latest" }
        "BILLING_API_KEY" = { secret_name = "billing-provider-key", secret_version = "latest" }
      }
    }
    
    "usage-service" = {
      name                = "usage-service"
      image               = "gcr.io/telecom-app-production/usage-service:latest"
      container_port      = 8080
      health_check_path   = "/health"
      cpu_request         = "500m"
      memory_request      = "512Mi"
      env_vars = {
        ENABLE_PROFILING = "false"
      }
      secret_env_vars = {
        "DB_PASSWORD" = { secret_name = "db-password", secret_version = "latest" }
      }
    }
  }

  min_instances           = 3
  max_instances           = 100
  cpu_threshold           = 70
  memory_limit            = "512Mi"
  cpu_limit               = "1"
  timeout_seconds         = 300

  environment_variables = {
    ENVIRONMENT            = "production"
    GCP_PROJECT_ID         = "telecom-app-production"
    ENABLE_TRACING         = "true"
    TRACE_SAMPLE_RATE      = "0.1"
  }

  service_accounts = {
    "user-service"    = "user-service-sa@telecom-app-production.iam.gserviceaccount.com"
    "billing-service" = "billing-service-sa@telecom-app-production.iam.gserviceaccount.com"
    "usage-service"   = "usage-service-sa@telecom-app-production.iam.gserviceaccount.com"
  }

  api_domains = ["api.telecom-app.com"]
}
```

## Variables

### Required

| Name | Description | Type |
|------|-------------|------|
| `project_id` | GCP Project ID | `string` |
| `region` | GCP Region | `string` |
| `environment` | Environment name (dev/staging/production) | `string` |
| `network_name` | VPC network name for VPC connector | `string` |
| `services` | Map of services to deploy | `map(object)` |
| `service_accounts` | Service account emails per service | `map(string)` |

### Optional

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `min_instances` | Minimum number of instances | `number` | `1` |
| `max_instances` | Maximum number of instances | `number` | `100` |
| `cpu_threshold` | CPU threshold for scaling | `number` | `70` |
| `memory_limit` | Memory limit per instance | `string` | `"512Mi"` |
| `cpu_limit` | CPU limit per instance | `string` | `"1"` |
| `timeout_seconds` | Request timeout in seconds | `number` | `300` |
| `environment_variables` | Global environment variables | `map(string)` | `{}` |
| `api_domains` | Domains for SSL certificate | `list(string)` | `[]` |

## Outputs

| Name | Description |
|------|-------------|
| `service_urls` | URLs of deployed Cloud Run services |
| `load_balancer_url` | Public URL of the load balancer |
| `backend_services` | IDs of backend services |
| `service_accounts` | Service account details |

## Module Architecture

### Components

1. **Cloud Run Services**: Individual microservices with health checks
2. **Network Endpoint Groups (NEG)**: Serverless backend integration
3. **Backend Services**: Load balancing configuration per service
4. **URL Map**: Path-based routing to different services
5. **Load Balancer**: Global HTTPS load balancer
6. **Cloud Armor**: DDoS and WAF protection
7. **SSL Certificate**: Managed SSL with auto-renewal

### Traffic Flow

```
Client Request (HTTPS)
         ↓
   Cloud Armor (DDoS/WAF)
         ↓
Cloud Load Balancer
         ↓
   URL Map (path routing)
         ↓
Backend Service (health checks)
         ↓
Network Endpoint Group (NEG)
         ↓
Cloud Run Service
```

## Security Considerations

### Service-to-Service Authentication

Services authenticate using Workload Identity:

```hcl
# Each service has a Workload Identity binding
resource "google_service_account" "service" {
  for_each = var.services
  
  account_id   = "${each.value.name}-sa"
  display_name = "Service Account for ${each.value.name}"
}

# In Kubernetes: serviceAccountName: workload-identity-sa
# In Cloud Run: automatically provided via metadata server
```

### Secret Management

Secrets are accessed via Secret Manager:

```hcl
env {
  name = "DB_PASSWORD"
  value_from {
    secret_key_ref {
      name = "db-password"
      key  = "latest"
    }
  }
}
```

### Network Security

- Private VPC connection via VPC Connector
- No public IPs for database connections
- Firewall rules restrict traffic to internal services
- Cloud NAT for predictable egress

## Scaling and Performance

### Auto-Scaling Policies

- **CPU-based**: Scale up when CPU > 70%, down when < 50%
- **Memory-based**: Optional memory-based scaling
- **Concurrency-based**: Scale based on concurrent requests

### Performance Characteristics

| Metric | Value |
|--------|-------|
| Startup Time | 1-5 seconds |
| Request Latency | 1-100ms (service dependent) |
| Max Concurrent Requests | 1000 per instance |
| Max Throughput | 10,000 req/sec per service |

## Monitoring and Logging

### Built-in Metrics

- Request count
- Request latency (p50, p90, p99)
- Error rate
- CPU and memory utilization
- Active instances count

### Log Levels

Production: INFO and above
Staging: DEBUG and above
Development: DEBUG (verbose)

### Example Alerts

```hcl
# High error rate
alert when error_rate > 1% for 5 minutes

# High latency
alert when p99_latency > 2000ms for 5 minutes

# Service unavailable
alert when available_instances == 0
```

## Deployment Strategy

### Blue-Green Deployments

This module supports blue-green deployments via traffic splitting:

```hcl
# Deploy new revision
gcloud run deploy user-service --image gcr.io/project/user-service:v2.0.0

# Shift traffic gradually
# 0% -> 10% -> 50% -> 100%
gcloud run services update-traffic user-service --to-revisions previous=90,LATEST=10
```

### Rollback

Instant rollback is available:

```bash
# Get previous revision
PREV=$(gcloud run revisions list --service=user-service --limit=2 --format='value(REVISION)' | tail -1)

# Route all traffic back
gcloud run services update-traffic user-service --to-revisions ${PREV}=100
```

## Maintenance

### Updating Services

1. Build new container image
2. Push to Artifact Registry
3. Update Terraform image reference
4. Run `terraform apply`
5. Cloud Run automatically handles blue-green deployment

### Scaling Adjustments

Modify `min_instances` and `max_instances` in variables, then:

```bash
terragrunt apply
```

### Health Check Tuning

Adjust in service configuration:

```hcl
liveness_probe {
  initial_delay_seconds = 10
  period_seconds        = 5
  timeout_seconds       = 3
  failure_threshold     = 3
}
```

## Troubleshooting

### Service Not Responding

1. Check Cloud Logging for errors
2. Verify health check endpoint is accessible
3. Check service account permissions
4. Verify secret availability

### High Latency

1. Check CPU/memory utilization
2. Review application logs for slowdowns
3. Monitor database query performance
4. Increase instance resources if needed

### Auto-Scaling Issues

1. Verify metrics are being collected
2. Check IAM permissions for Monitoring
3. Review scaling policy thresholds
4. Check for rate limiting upstream

## Cost Optimization

- **Min Instances**: Keep at 1-3 for production, 0-1 for dev
- **Instance Size**: Right-size CPU/memory per service
- **Revision Cleanup**: Regularly delete old revisions
- **Regional Placement**: Place services in regions close to data

## Related Modules

- `networking`: VPC and VPC Connector setup
- `iam`: Service account creation and IAM bindings
- `monitoring`: Logging and alerting setup
- `secrets`: Secret Manager configuration

## Testing

### Unit Tests

```bash
cd tests
terraform test
```

### Integration Tests

```bash
cd tests/integration
./run-integration-tests.sh
```

### Load Testing

```bash
k6 run tests/load-testing/cloud-run.js --vus 100 --duration 5m
```

## Contributing

When modifying this module:

1. Update version in `versions.tf`
2. Run `terraform fmt` to format code
3. Run `terraform validate`
4. Add tests for new functionality
5. Update this README
6. Create pull request with clear description

## License

Internal Use Only
