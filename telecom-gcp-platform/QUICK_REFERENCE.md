# Quick Reference Guide

## 📦 What You Have

**Enterprise-Grade Terraform Platform for GCP Telecom Microservices**
- 17 files | 4,500+ lines of code | 50KB+ documentation
- Production-ready Cloud Run module with 5 microservices
- Terragrunt DRY pattern eliminating configuration repetition
- 7-stage GitLab CI/CD pipeline with blue-green deployments
- Comprehensive testing suite (Terratest + pre-commit hooks)

---

## ⚡ 5-Minute Start

```bash
# 1. Extract the archive
unzip telecom-gcp-platform-enterprise.zip
cd telecom-gcp-platform

# 2. Read the overview
cat README.md

# 3. Initialize Terragrunt
terragrunt init

# 4. Preview changes
./scripts/plan.sh dev

# 5. Deploy (with approval)
cd terraform/environments/dev
terragrunt apply
```

---

## 📁 Essential Files

| File | Purpose | Read First? |
|------|---------|------------|
| README.md | Project overview | ✅ YES |
| ARCHITECTURE.md | System design | ✅ YES |
| DEPLOYMENT.md | How to deploy | ✅ YES |
| ENTERPRISE_TERRAFORM_GUIDE.md | Learn Terragrunt patterns | After basics |
| terragrunt.hcl | DRY configuration | Auto-loaded |
| variables/global.tfvars.yaml | Shared settings | Review |
| variables/env.tfvars.yaml | Environment overrides | Customize |
| terraform/environments/dev/main.tf | Infrastructure definition | Reference |
| gitlab-ci.yml | CI/CD pipeline | If using GitLab |

---

## 🎯 Common Tasks

### Plan Changes
```bash
./scripts/plan.sh dev              # All modules
./scripts/plan.sh dev cloud-run    # Specific module
```

### Deploy Infrastructure
```bash
cd terraform/environments/dev
terragrunt init      # First time only
terragrunt plan      # Review changes
terragrunt apply     # Deploy
```

### Deploy to Staging/Production
```bash
# Copy dev environment and customize:
cp -r terraform/environments/dev terraform/environments/staging
# Edit terraform/environments/staging/terragrunt.hcl
# Edit variables/env.tfvars.yaml for staging config
terragrunt apply
```

### Update Services
```bash
# Update docker image in variables/global.tfvars.yaml
# Commit and push to GitLab
# CI/CD pipeline automatically builds and deploys
```

### Scale Services
```bash
# Edit variables/env.tfvars.yaml:
# Change min_instances or max_instances
terragrunt apply
```

### View Logs
```bash
gcloud logging read \
  --limit 50 \
  --format json \
  resource.type=cloud_run_revision \
  resource.labels.service_name=user-service
```

### Troubleshoot Service
```bash
# Check service status
gcloud run services describe user-service --region=us-central1

# View recent revisions
gcloud run revisions list --service=user-service --region=us-central1

# Check resource metrics
gcloud monitoring timeseries list \
  --filter 'resource.type = cloud_run_revision'
```

---

## 🔧 Configuration Hierarchy

Lower = Higher Priority (overrides above)

```
1. CLI Arguments       (highest priority)
2. Environment File    (variables/env.tfvars.yaml)
3. Global Config       (variables/global.tfvars.yaml)
4. Module Defaults     (lowest priority)
```

**Example**: To change dev min instances:
```yaml
# In variables/env.tfvars.yaml
dev_environment:
  min_instances: 2    # Overrides global default of 1
```

---

## 📊 Environment Specifications

### Development
- Instances: 1 min → 10 max
- Database: Spanner 2-node
- Backups: Disabled
- Cost: ~$500/month
- Use: Testing & development

### Staging
- Instances: 2 min → 50 max
- Database: Spanner 3-node
- Backups: Daily
- Cost: ~$2,000/month
- Use: Pre-production validation

### Production
- Instances: 3 min → 100 max
- Database: Spanner multi-region
- Backups: PITR enabled
- Cost: ~$5,000/month
- Features: Cloud Armor, CMEK, VPC Controls
- Use: Live traffic

---

## 🏗️ Architecture at a Glance

```
Users
  ↓
HTTPS (Cloud Armor DDoS/WAF)
  ↓
Global Load Balancer
  ↓
Path Routing (URL Map)
  ↓
5 Cloud Run Services
  ├── user-service
  ├── billing-service
  ├── usage-service
  ├── notification-service
  └── analytics-service
  ↓
VPC Connector (Private)
  ↓
Databases
  ├── Spanner (transactions)
  ├── Firestore (flexible)
  ├── BigTable (timeseries)
  └── BigQuery (analytics)
```

---

## 🔐 Security Features

✅ Cloud Armor (DDoS/WAF protection)
✅ Workload Identity (service-to-service auth)
✅ CMEK encryption (customer-managed keys)
✅ VPC isolation (private database access)
✅ Secret Manager (sensitive keys)
✅ IAM roles (least privilege)
✅ Health checks (liveness + startup probes)

---

## 📈 Performance Specs

| Metric | Value |
|--------|-------|
| Service startup | 1-5 seconds |
| Request latency | 1-100ms |
| Max concurrent/instance | 1000 |
| Max throughput/service | 10,000 req/sec |
| Auto-scale threshold | CPU > 70% |
| Health check interval | 10 seconds |
| Minimum instances | 1-3 (env dependent) |
| Maximum instances | 10-100 (env dependent) |

---

## 🚀 CI/CD Pipeline Stages

1. **Validate** - Code format, syntax, linting
2. **Build** - Docker images for 5 services
3. **Security Scan** - Container scan, SAST, secrets
4. **Test** - Unit tests, integration tests
5. **Deploy Staging** - Automatic to staging
6. **Deploy Production** - Manual approval, blue-green
7. **Rollback Production** - Manual if needed

---

## 🧪 Testing

**Pre-commit Hooks** (automatic before commit)
- Terraform format validation
- Security scanning (tfsec, gitleaks)
- Syntax checking (JSON, YAML)

**Terratest Suite** (integration tests)
- Service creation verification
- Load balancer configuration
- Cloud Armor rules
- Network policies
- Health checks

**Run Tests**:
```bash
cd tests/terratest
go test -v cloud_run_test.go
```

---

## 📚 Module Reference

### Cloud Run Module
```hcl
module "cloud_run" {
  source = "./terraform/modules/cloud-run"
  
  project_id       = "my-project"
  region          = "us-central1"
  environment     = "production"
  
  services = {
    "user-service" = {
      name              = "user-service"
      image             = "gcr.io/my-project/user-service:v1"
      container_port    = 8080
      health_check_path = "/health"
    }
  }
  
  min_instances = 1
  max_instances = 100
}
```

### All 8 Modules (in terraform/environments/dev/main.tf)
1. gcp-project - Project setup
2. networking - VPC, subnets, Cloud NAT
3. secrets - Secret Manager
4. iam - Service accounts, roles
5. databases - Spanner, Firestore, BigTable, BigQuery
6. pubsub - Event topics
7. cloud-run - Microservices (this guide)
8. monitoring - Logging, alerting, SLOs

---

## 🆘 Troubleshooting Quick Links

### Service Not Running
1. Check logs: `gcloud logging read --limit 50`
2. Check health: `gcloud run services describe user-service`
3. Check IAM: Verify service account permissions

### Deployment Failed
1. Review terraform plan: `terragrunt plan`
2. Check state: `terragrunt state list`
3. See full guide: Check DEPLOYMENT.md troubleshooting section

### Performance Issues
1. Check CPU/memory: `gcloud monitoring timeseries list`
2. Review logs for errors
3. Increase instance resources in variables/env.tfvars.yaml

### Cost Too High
1. Check instances: Reduce max_instances in variables
2. Check retention: Lower log retention periods
3. Review DEPLOYMENT.md cost optimization section

---

## 📞 Support Resources

| Topic | File |
|-------|------|
| How to deploy | DEPLOYMENT.md |
| Architecture decisions | ARCHITECTURE.md |
| Enterprise patterns | ENTERPRISE_TERRAFORM_GUIDE.md |
| Module documentation | terraform/modules/cloud-run/README.md |
| Project structure | PROJECT_STRUCTURE.md |
| All deliverables | DELIVERABLES_INDEX.md |

---

## ✅ Pre-Deployment Checklist

- [ ] GCP project created
- [ ] Terraform/Terragrunt installed
- [ ] Service account with IAM permissions created
- [ ] GitLab repository ready
- [ ] Docker registry (Artifact Registry) configured
- [ ] reviewed README.md and DEPLOYMENT.md
- [ ] Customized variables/env.tfvars.yaml for environment
- [ ] Created terraform/environments/{staging,production} if needed
- [ ] Set up GitLab CI/CD variables
- [ ] Terraform state backend (GCS) ready

---

## 🔄 Standard Workflow

1. **Local Development**
   ```bash
   terraform init
   terraform plan
   terraform validate
   ```

2. **Pre-Commit**
   ```bash
   pre-commit run --all-files
   ```

3. **Push to GitLab**
   ```bash
   git add .
   git commit -m "Update infrastructure"
   git push origin main
   ```

4. **Pipeline Runs** (automatic)
   - Validate stage
   - Build stage
   - Security stage
   - Test stage

5. **Deploy Staging** (automatic)

6. **Deploy Production** (manual approval)
   - Blue-green deployment
   - Gradual traffic shifting (0%→10%→50%→100%)
   - Automatic rollback if error rate > 5%

---

## 💡 Pro Tips

1. **Test Changes Locally**: Always run `terragrunt plan` before applying
2. **Use scripts/plan.sh**: Faster than manual terraform plan
3. **Read Logs**: `gcloud logging read` shows real errors
4. **Monitor Metrics**: Check Cloud Console for performance
5. **Version Services**: Use semantic versioning in docker images
6. **Review Costs**: Monitor budget alerts in variables/env.tfvars.yaml
7. **Keep Backups**: Production backups with PITR enabled by default
8. **Test Rollback**: Practice rollback procedures before needed

---

## 📖 Learning Path

**Day 1**: Read README.md, PROJECT_STRUCTURE.md, DELIVERABLES_INDEX.md

**Day 2**: Read ARCHITECTURE.md, understand system design

**Day 3**: Read DEPLOYMENT.md, plan your setup

**Day 4**: Run `terragrunt init` and `terragrunt plan` locally

**Day 5**: Deploy to dev environment and test

**Day 6**: Create staging environment, test CI/CD pipeline

**Day 7**: Deploy to production with monitoring

---

## 🎯 Success Metrics

After deployment, verify:

✅ All 5 services running: `gcloud run services list`
✅ Load balancer working: Test HTTPS endpoint
✅ Health checks passing: See `gcloud run revisions list`
✅ Scaling working: Monitor active instances under load
✅ Logs flowing: Check Cloud Logging dashboard
✅ Metrics visible: Check Cloud Monitoring dashboard
✅ CI/CD pipeline working: Commit a test change
✅ Backup working: Verify Cloud Spanner backups

---

**Next Step**: Extract the archive and read README.md!

**Need Help?** See DEPLOYMENT.md for detailed troubleshooting guide.
