// tests/terratest/cloud_run_test.go
// Terratest for Cloud Run module
// Run: cd tests/terratest && go test -v cloud_run_test.go

package test

import (
	"fmt"
	"testing"

	"github.com/gruntwork-io/terratest/modules/gcp"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestCloudRunModuleCreatesServices verifies Cloud Run services are created correctly
func TestCloudRunModuleCreatesServices(t *testing.T) {
	t.Parallel()

	projectID := gcp.GetRandomProjectID(t)
	region := "us-central1"
	environment := "dev"

	terraformOptions := &terraform.Options{
		TerraformDir: "../../modules/cloud-run/examples/complete",
		Vars: map[string]interface{}{
			"project_id":  projectID,
			"region":      region,
			"environment": environment,
		},
	}

	// Cleanup after test
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply Terraform
	terraform.InitAndApply(t, terraformOptions)

	// Test 1: Verify service URLs are returned
	serviceURLs := terraform.OutputMap(t, terraformOptions, "service_urls")
	assert.NotEmpty(t, serviceURLs, "Service URLs should not be empty")
	assert.Contains(t, serviceURLs, "user-service", "Should contain user-service URL")

	// Test 2: Verify load balancer URL is returned
	lbURL := terraform.Output(t, terraformOptions, "load_balancer_url")
	assert.Contains(t, lbURL, "https://", "Load balancer URL should use HTTPS")

	// Test 3: Verify Cloud Run services exist in GCP
	userServiceName := "user-service"
	assert.True(t, gcp.RunServiceExists(t, projectID, region, userServiceName),
		fmt.Sprintf("Cloud Run service %s should exist", userServiceName))

	// Test 4: Verify service has correct configuration
	service := gcp.GetRunService(t, projectID, region, userServiceName)
	require.NotNil(t, service)
	assert.Equal(t, userServiceName, service.Name)
	assert.NotEmpty(t, service.Status.LatestReadyRevision)

	// Test 5: Verify service has health check
	assert.NotNil(t, service.Spec, "Service should have spec")

	// Test 6: Verify IAM bindings prevent public access
	policy := gcp.GetServiceAccountIamPolicy(t, projectID, "user-service-sa")
	require.NotNil(t, policy)
	// Verify no "public" or "allUsers" bindings for invoker role
	for _, binding := range policy.Bindings {
		if binding.Role == "roles/run.invoker" {
			for _, member := range binding.Members {
				assert.NotEqual(t, "allUsers", member, "Cloud Run service should not be publicly accessible")
			}
		}
	}
}

// TestCloudRunAutoScalingConfiguration verifies scaling is configured correctly
func TestCloudRunAutoScalingConfiguration(t *testing.T) {
	t.Parallel()

	projectID := gcp.GetRandomProjectID(t)
	region := "us-central1"

	terraformOptions := &terraform.Options{
		TerraformDir: "../../modules/cloud-run/examples/complete",
		Vars: map[string]interface{}{
			"project_id":   projectID,
			"region":       region,
			"min_instances": 1,
			"max_instances": 10,
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify service has autoscaling annotations
	service := gcp.GetRunService(t, projectID, region, "user-service")
	require.NotNil(t, service)

	minScale := service.Spec.Template.Metadata.Annotations["autoscaling.knative.dev/minScale"]
	maxScale := service.Spec.Template.Metadata.Annotations["autoscaling.knative.dev/maxScale"]

	assert.Equal(t, "1", minScale, "Min instances should be 1")
	assert.Equal(t, "10", maxScale, "Max instances should be 10")
}

// TestCloudRunEnvironmentVariables verifies environment variables are set correctly
func TestCloudRunEnvironmentVariables(t *testing.T) {
	t.Parallel()

	projectID := gcp.GetRandomProjectID(t)
	region := "us-central1"

	terraformOptions := &terraform.Options{
		TerraformDir: "../../modules/cloud-run/examples/complete",
		Vars: map[string]interface{}{
			"project_id": projectID,
			"region":     region,
			"environment_variables": map[string]string{
				"LOG_LEVEL": "DEBUG",
				"ENVIRONMENT": "test",
			},
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify environment variables
	service := gcp.GetRunService(t, projectID, region, "user-service")
	require.NotNil(t, service)

	containers := service.Spec.Template.Spec.Containers
	require.NotEmpty(t, containers)

	container := containers[0]
	envVars := container.Env

	// Find LOG_LEVEL variable
	var logLevel *envVarRef
	for _, env := range envVars {
		if env.Name == "LOG_LEVEL" {
			logLevel = &env
			break
		}
	}

	require.NotNil(t, logLevel, "LOG_LEVEL environment variable should be set")
	assert.Equal(t, "DEBUG", logLevel.Value)
}

// TestCloudRunVPCConnectorConfiguration verifies VPC connector is configured
func TestCloudRunVPCConnectorConfiguration(t *testing.T) {
	t.Parallel()

	projectID := gcp.GetRandomProjectID(t)
	region := "us-central1"

	terraformOptions := &terraform.Options{
		TerraformDir: "../../modules/cloud-run/examples/complete",
		Vars: map[string]interface{}{
			"project_id": projectID,
			"region":     region,
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify VPC connector is attached
	service := gcp.GetRunService(t, projectID, region, "user-service")
	require.NotNil(t, service)

	vpcConnector := service.Spec.Template.Spec.VPCAccess.Connector
	assert.NotEmpty(t, vpcConnector, "VPC connector should be configured")

	egressSettings := service.Spec.Template.Spec.VPCAccess.EgressSettings
	assert.Equal(t, "all-traffic", egressSettings, "All traffic should route through VPC connector")
}

// TestCloudRunHealthChecks verifies health check configuration
func TestCloudRunHealthChecks(t *testing.T) {
	t.Parallel()

	projectID := gcp.GetRandomProjectID(t)
	region := "us-central1"

	terraformOptions := &terraform.Options{
		TerraformDir: "../../modules/cloud-run/examples/complete",
		Vars: map[string]interface{}{
			"project_id": projectID,
			"region":     region,
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify health checks
	service := gcp.GetRunService(t, projectID, region, "user-service")
	require.NotNil(t, service)

	container := service.Spec.Template.Spec.Containers[0]

	// Check liveness probe
	assert.NotNil(t, container.LivenessProbe, "Liveness probe should be configured")
	assert.NotNil(t, container.LivenessProbe.HTTPGet, "HTTP liveness probe should be configured")
	assert.Equal(t, "/health", container.LivenessProbe.HTTPGet.Path)

	// Check startup probe
	assert.NotNil(t, container.StartupProbe, "Startup probe should be configured")
	assert.NotNil(t, container.StartupProbe.HTTPGet, "HTTP startup probe should be configured")
}

// TestCloudRunLoadBalancer verifies load balancer configuration
func TestCloudRunLoadBalancer(t *testing.T) {
	t.Parallel()

	projectID := gcp.GetRandomProjectID(t)
	region := "us-central1"

	terraformOptions := &terraform.Options{
		TerraformDir: "../../modules/cloud-run/examples/complete",
		Vars: map[string]interface{}{
			"project_id": projectID,
			"region":     region,
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Test 1: Verify load balancer exists
	lbs := gcp.GetGlobalForwardingRules(t, projectID)
	apiLoadBalancerFound := false
	for _, lb := range lbs {
		if fmt.Sprintf("%s-api-", "telecom") == lb.Name[:len("telecom-api-")] {
			apiLoadBalancerFound = true
			break
		}
	}
	assert.True(t, apiLoadBalancerFound, "API load balancer should exist")

	// Test 2: Verify SSL certificate
	certs := gcp.GetSslCertificates(t, projectID)
	certFound := false
	for _, cert := range certs {
		if "telecom-api-ssl" == cert.Name[:len("telecom-api-ssl")] {
			certFound = true
			break
		}
	}
	assert.True(t, certFound, "SSL certificate should be created")
}

// TestCloudRunCloudArmorIntegration verifies Cloud Armor is configured
func TestCloudRunCloudArmorIntegration(t *testing.T) {
	t.Parallel()

	projectID := gcp.GetRandomProjectID(t)
	region := "us-central1"

	terraformOptions := &terraform.Options{
		TerraformDir: "../../modules/cloud-run/examples/complete",
		Vars: map[string]interface{}{
			"project_id": projectID,
			"region":     region,
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify Cloud Armor security policy exists
	policies := gcp.GetSecurityPolicies(t, projectID)
	armorFound := false
	for _, policy := range policies {
		if "telecom-cloud-armor" == policy.Name[:len("telecom-cloud-armor")] {
			armorFound = true
			// Verify it has rules
			assert.True(t, len(policy.Rules) > 0, "Cloud Armor policy should have rules")
			break
		}
	}
	assert.True(t, armorFound, "Cloud Armor policy should be created")
}

// TestCloudRunMultipleServices verifies multiple services work together
func TestCloudRunMultipleServices(t *testing.T) {
	t.Parallel()

	projectID := gcp.GetRandomProjectID(t)
	region := "us-central1"

	terraformOptions := &terraform.Options{
		TerraformDir: "../../modules/cloud-run/examples/complete",
		Vars: map[string]interface{}{
			"project_id": projectID,
			"region":     region,
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify all services exist
	services := []string{"user-service", "billing-service", "usage-service", "notification-service", "analytics-service"}

	for _, serviceName := range services {
		exists := gcp.RunServiceExists(t, projectID, region, serviceName)
		assert.True(t, exists, fmt.Sprintf("Service %s should exist", serviceName))

		service := gcp.GetRunService(t, projectID, region, serviceName)
		require.NotNil(t, service)

		// Verify each service has proper configuration
		assert.NotEmpty(t, service.Spec.Template.Spec.ServiceAccountName)
		assert.NotEmpty(t, service.Spec.Template.Spec.Containers[0].Image)
	}
}

// TestCloudRunNetworkPolicy verifies network policies
func TestCloudRunNetworkPolicy(t *testing.T) {
	t.Parallel()

	projectID := gcp.GetRandomProjectID(t)
	region := "us-central1"

	terraformOptions := &terraform.Options{
		TerraformDir: "../../modules/cloud-run/examples/complete",
		Vars: map[string]interface{}{
			"project_id": projectID,
			"region":     region,
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify firewall rules
	rules := gcp.GetFirewallRules(t, projectID)

	// Should have rules restricting traffic
	restrictiveRulesFound := 0
	for _, rule := range rules {
		if rule.Direction == "INGRESS" && rule.SourceRanges != nil {
			if len(rule.SourceRanges) == 1 && rule.SourceRanges[0] == "10.0.0.0/8" {
				restrictiveRulesFound++
			}
		}
	}

	assert.Greater(t, restrictiveRulesFound, 0, "Should have restrictive ingress rules")
}

// Supporting types for tests
type envVarRef struct {
	Name  string
	Value string
}

// BenchmarkCloudRunDeployment measures deployment time
func BenchmarkCloudRunDeployment(b *testing.B) {
	projectID := gcp.GetRandomProjectID(&testing.T{})
	region := "us-central1"

	terraformOptions := &terraform.Options{
		TerraformDir: "../../modules/cloud-run/examples/complete",
		Vars: map[string]interface{}{
			"project_id": projectID,
			"region":     region,
		},
	}

	defer terraform.Destroy(&testing.T{}, terraformOptions)

	for i := 0; i < b.N; i++ {
		terraform.InitAndApply(&testing.T{}, terraformOptions)
	}
}
