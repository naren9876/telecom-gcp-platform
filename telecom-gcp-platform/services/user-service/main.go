package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"cloud.google.com/go/firestore"
	"cloud.google.com/go/spanner"
	"github.com/gorilla/mux"
	"go.opencensus.io/exporter/stackdriver"
	"go.opencensus.io/trace"
	"google.golang.org/api/option"
)

// Config holds application configuration
type Config struct {
	Environment      string
	GCPProjectID     string
	SpannerDatabase  string
	FirestoreDB      string
	Port             string
	LogLevel         string
	EnableTracing    bool
	TraceSampleRate  float64
}

// Service holds application dependencies
type Service struct {
	config            *Config
	spannerClient     *spanner.Client
	firestoreClient   *firestore.Client
	router            *mux.Router
}

// User represents a user entity
type User struct {
	ID            string    `json:"id"`
	Email         string    `json:"email"`
	PhoneNumber   string    `json:"phone_number"`
	FullName      string    `json:"full_name"`
	SubscriptionTier string `json:"subscription_tier"`
	Status        string    `json:"status"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

func main() {
	ctx := context.Background()

	// Load configuration
	config := &Config{
		Environment:     os.Getenv("ENVIRONMENT"),
		GCPProjectID:    os.Getenv("GCP_PROJECT_ID"),
		SpannerDatabase: os.Getenv("SPANNER_DATABASE"),
		FirestoreDB:     os.Getenv("FIRESTORE_DATABASE"),
		Port:            getEnvOrDefault("PORT", "8080"),
		LogLevel:        getEnvOrDefault("LOG_LEVEL", "INFO"),
		EnableTracing:   os.Getenv("ENABLE_TRACING") == "true",
		TraceSampleRate: parseFloat(getEnvOrDefault("TRACE_SAMPLE_RATE", "0.1")),
	}

	// Initialize tracing
	if config.EnableTracing {
		initTracing(ctx, config)
	}

	// Initialize clients
	spannerClient, err := spanner.NewClient(ctx, config.SpannerDatabase)
	if err != nil {
		log.Fatalf("Failed to create Spanner client: %v", err)
	}
	defer spannerClient.Close()

	firestoreClient, err := firestore.NewClient(ctx, config.GCPProjectID)
	if err != nil {
		log.Fatalf("Failed to create Firestore client: %v", err)
	}
	defer firestoreClient.Close()

	// Create service
	service := &Service{
		config:          config,
		spannerClient:   spannerClient,
		firestoreClient: firestoreClient,
		router:          mux.NewRouter(),
	}

	// Setup routes
	service.setupRoutes()

	// Start server
	log.Printf("Starting User Service on port %s", config.Port)
	addr := fmt.Sprintf(":%s", config.Port)

	server := &http.Server{
		Addr:         addr,
		Handler:      service.router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}

// setupRoutes configures all API endpoints
func (s *Service) setupRoutes() {
	// Health check
	s.router.HandleFunc("/health", s.healthCheck).Methods("GET")
	s.router.HandleFunc("/ready", s.readinessCheck).Methods("GET")

	// User management endpoints
	s.router.HandleFunc("/user-service/api/v1/users", s.createUser).Methods("POST")
	s.router.HandleFunc("/user-service/api/v1/users/{id}", s.getUser).Methods("GET")
	s.router.HandleFunc("/user-service/api/v1/users/{id}", s.updateUser).Methods("PUT")
	s.router.HandleFunc("/user-service/api/v1/users/{id}", s.deleteUser).Methods("DELETE")
	s.router.HandleFunc("/user-service/api/v1/users", s.listUsers).Methods("GET")

	// Authentication endpoints
	s.router.HandleFunc("/user-service/api/v1/auth/signin", s.signIn).Methods("POST")
	s.router.HandleFunc("/user-service/api/v1/auth/signout", s.signOut).Methods("POST")
	s.router.HandleFunc("/user-service/api/v1/auth/verify", s.verifyToken).Methods("GET")

	// Subscription management
	s.router.HandleFunc("/user-service/api/v1/users/{id}/subscription", s.getSubscription).Methods("GET")
	s.router.HandleFunc("/user-service/api/v1/users/{id}/subscription", s.updateSubscription).Methods("PUT")

	// Profile management
	s.router.HandleFunc("/user-service/api/v1/users/{id}/profile", s.getProfile).Methods("GET")
	s.router.HandleFunc("/user-service/api/v1/users/{id}/profile", s.updateProfile).Methods("PUT")

	// Middleware
	s.router.Use(loggingMiddleware)
	s.router.Use(authenticationMiddleware)
}

// HTTP Handlers

// healthCheck returns immediate health status
func (s *Service) healthCheck(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	// Quick health check
	health := map[string]string{
		"status": "healthy",
		"service": "user-service",
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	jsonResponse(w, health)
}

// readinessCheck performs detailed readiness check
func (s *Service) readinessCheck(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	ready := true

	// Check Spanner connectivity
	_, err := s.spannerClient.Single().Query(ctx, spanner.NewStatement("SELECT 1"))
	if err != nil {
		log.Printf("Spanner readiness check failed: %v", err)
		ready = false
	}

	// Check Firestore connectivity
	_, err = s.firestoreClient.Collection("health").Doc("check").Get(ctx)
	if err != nil && err.Error() != "rpc error: code = NotFound" {
		log.Printf("Firestore readiness check failed: %v", err)
		ready = false
	}

	status := "ready"
	statusCode := http.StatusOK
	if !ready {
		status = "not_ready"
		statusCode = http.StatusServiceUnavailable
	}

	response := map[string]string{
		"status": status,
		"service": "user-service",
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	jsonResponse(w, response)
}

// createUser creates a new user
func (s *Service) createUser(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	var user User
	if err := jsonRequest(r, &user); err != nil {
		errorResponse(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	// Validate input
	if user.Email == "" || user.FullName == "" {
		errorResponse(w, http.StatusBadRequest, "Email and FullName are required")
		return
	}

	// Generate user ID
	user.ID = generateID()
	user.Status = "active"
	user.SubscriptionTier = "basic"
	user.CreatedAt = time.Now()
	user.UpdatedAt = time.Now()

	// Save to Spanner (transactional)
	_, err := s.spannerClient.Apply(ctx, []*spanner.Mutation{
		spanner.Insert("users",
			[]string{"id", "email", "phone_number", "full_name", "subscription_tier", "status", "created_at", "updated_at"},
			[]interface{}{user.ID, user.Email, user.PhoneNumber, user.FullName, user.SubscriptionTier, user.Status, user.CreatedAt, user.UpdatedAt},
		),
	})

	if err != nil {
		log.Printf("Failed to create user: %v", err)
		errorResponse(w, http.StatusInternalServerError, "Failed to create user")
		return
	}

	// Also save profile to Firestore for flexible schema
	_, err = s.firestoreClient.Collection("user_profiles").Doc(user.ID).Set(ctx, map[string]interface{}{
		"user_id": user.ID,
		"email": user.Email,
		"full_name": user.FullName,
		"preferences": map[string]bool{
			"email_notifications": true,
			"sms_notifications": false,
		},
		"created_at": user.CreatedAt,
	})

	if err != nil {
		log.Printf("Failed to save profile: %v", err)
		// Continue - Spanner write succeeded
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	jsonResponse(w, user)
}

// getUser retrieves a user by ID
func (s *Service) getUser(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	vars := mux.Vars(r)
	userID := vars["id"]

	// Query from Spanner
	row, err := s.spannerClient.Single().ReadRow(ctx, "users",
		spanner.Key{userID},
		[]string{"id", "email", "phone_number", "full_name", "subscription_tier", "status", "created_at", "updated_at"},
	)

	if err != nil {
		log.Printf("Failed to get user: %v", err)
		errorResponse(w, http.StatusNotFound, "User not found")
		return
	}

	var user User
	if err := row.ToStruct(&user); err != nil {
		log.Printf("Failed to parse user: %v", err)
		errorResponse(w, http.StatusInternalServerError, "Failed to parse user data")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	jsonResponse(w, user)
}

// updateUser updates a user
func (s *Service) updateUser(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	vars := mux.Vars(r)
	userID := vars["id"]

	var updateData map[string]interface{}
	if err := jsonRequest(r, &updateData); err != nil {
		errorResponse(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	updateData["updated_at"] = time.Now()

	// Build update mutation
	mutations := []*spanner.Mutation{}
	mutations = append(mutations, spanner.Update("users",
		append([]string{"id"}, mapKeys(updateData)...),
		append([]interface{}{userID}, mapValues(updateData)...),
	))

	_, err := s.spannerClient.Apply(ctx, mutations)
	if err != nil {
		log.Printf("Failed to update user: %v", err)
		errorResponse(w, http.StatusInternalServerError, "Failed to update user")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	jsonResponse(w, map[string]string{"status": "updated"})
}

// deleteUser deletes a user
func (s *Service) deleteUser(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	vars := mux.Vars(r)
	userID := vars["id"]

	_, err := s.spannerClient.Apply(ctx, []*spanner.Mutation{
		spanner.Delete("users", spanner.Key{userID}),
	})

	if err != nil {
		log.Printf("Failed to delete user: %v", err)
		errorResponse(w, http.StatusInternalServerError, "Failed to delete user")
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// listUsers returns a paginated list of users
func (s *Service) listUsers(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		fmt.Sscanf(l, "%d", &limit)
	}

	query := fmt.Sprintf("SELECT id, email, full_name, subscription_tier, status FROM users LIMIT %d", limit)
	stmt := spanner.NewStatement(query)
	iter := s.spannerClient.Single().Query(ctx, stmt)

	var users []User
	if err := iter.Do(func(row *spanner.Row) error {
		var user User
		return row.Columns(&user.ID, &user.Email, &user.FullName, &user.SubscriptionTier, &user.Status)
	}); err != nil {
		log.Printf("Failed to list users: %v", err)
		errorResponse(w, http.StatusInternalServerError, "Failed to list users")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	jsonResponse(w, map[string]interface{}{
		"users": users,
		"count": len(users),
	})
}

// signIn handles user authentication
func (s *Service) signIn(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	var credentials map[string]string
	if err := jsonRequest(r, &credentials); err != nil {
		errorResponse(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	email := credentials["email"]
	// password := credentials["password"]

	// TODO: Implement proper password verification
	// For now, just return a token

	token := generateJWT(email)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	jsonResponse(w, map[string]string{
		"token": token,
		"expires_in": "3600",
	})
}

// signOut handles user logout
func (s *Service) signOut(w http.ResponseWriter, r *http.Request) {
	// TODO: Implement token blacklisting or session invalidation
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	jsonResponse(w, map[string]string{"status": "signed_out"})
}

// verifyToken verifies JWT token
func (s *Service) verifyToken(w http.ResponseWriter, r *http.Request) {
	token := r.Header.Get("Authorization")
	if token == "" {
		errorResponse(w, http.StatusUnauthorized, "Missing authorization header")
		return
	}

	// TODO: Implement JWT verification
	valid := true

	if !valid {
		errorResponse(w, http.StatusUnauthorized, "Invalid token")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	jsonResponse(w, map[string]bool{"valid": true})
}

// getSubscription returns user's subscription details
func (s *Service) getSubscription(w http.ResponseWriter, r *http.Request) {
	// Implementation
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	jsonResponse(w, map[string]string{})
}

// updateSubscription updates user's subscription
func (s *Service) updateSubscription(w http.ResponseWriter, r *http.Request) {
	// Implementation
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	jsonResponse(w, map[string]string{})
}

// getProfile retrieves user profile
func (s *Service) getProfile(w http.ResponseWriter, r *http.Request) {
	// Implementation
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	jsonResponse(w, map[string]string{})
}

// updateProfile updates user profile
func (s *Service) updateProfile(w http.ResponseWriter, r *http.Request) {
	// Implementation
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	jsonResponse(w, map[string]string{})
}

// Middleware

// loggingMiddleware logs all requests
func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s %s %s", r.Method, r.RequestURI, r.RemoteAddr)
		next.ServeHTTP(w, r)
	})
}

// authenticationMiddleware validates JWT tokens
func authenticationMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Skip auth for health checks
		if r.URL.Path == "/health" || r.URL.Path == "/ready" {
			next.ServeHTTP(w, r)
			return
		}

		// Skip auth for sign-in
		if r.URL.Path == "/user-service/api/v1/auth/signin" {
			next.ServeHTTP(w, r)
			return
		}

		// Verify JWT token
		token := r.Header.Get("Authorization")
		if token == "" {
			http.Error(w, "Missing authorization header", http.StatusUnauthorized)
			return
		}

		// TODO: Implement JWT verification
		next.ServeHTTP(w, r)
	})
}

// Helper Functions

func initTracing(ctx context.Context, config *Config) {
	exporter, err := stackdriver.NewExporter(stackdriver.Options{
		ProjectID: config.GCPProjectID,
	})
	if err != nil {
		log.Printf("Failed to create trace exporter: %v", err)
		return
	}

	trace.RegisterExporter(exporter)
	trace.ApplyConfig(trace.Config{
		DefaultSampler: trace.ProbabilitySampler(config.TraceSampleRate),
	})
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func parseFloat(s string) float64 {
	var f float64
	fmt.Sscanf(s, "%f", &f)
	return f
}

func generateID() string {
	return fmt.Sprintf("user_%d", time.Now().UnixNano())
}

func generateJWT(email string) string {
	// TODO: Implement proper JWT generation
	return "jwt_token_placeholder"
}

func jsonRequest(r *http.Request, v interface{}) error {
	defer r.Body.Close()
	return r.Body.(interface{ Decode(interface{}) error }).Decode(v)
}

func jsonResponse(w http.ResponseWriter, v interface{}) {
	// TODO: Use json package to marshal
	w.Write([]byte("{}"))
}

func errorResponse(w http.ResponseWriter, statusCode int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	jsonResponse(w, map[string]string{"error": message})
}

func mapKeys(m map[string]interface{}) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}

func mapValues(m map[string]interface{}) []interface{} {
	values := make([]interface{}, 0, len(m))
	for _, v := range m {
		values = append(values, v)
	}
	return values
}
