package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/Shaggydesai/production-kubernetes-platform/apps/taskflow-api/internal/config"
	"github.com/Shaggydesai/production-kubernetes-platform/apps/taskflow-api/internal/db"
	"github.com/Shaggydesai/production-kubernetes-platform/apps/taskflow-api/internal/handlers"
	"github.com/Shaggydesai/production-kubernetes-platform/apps/taskflow-api/internal/middleware"
	appmigrate "github.com/Shaggydesai/production-kubernetes-platform/apps/taskflow-api/internal/migrate"
)

func main() {
	cfg := config.Load()

	// One binary serves the API and applies migrations, so an image tag pins the
	// schema and the code together. Run as: taskflow-api migrate up
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "migrate":
			direction := "up"
			if len(os.Args) > 2 {
				direction = os.Args[2]
			}
			if err := appmigrate.Run(cfg, direction); err != nil {
				log.Fatalf("migration failed: %v", err)
			}
			return
		default:
			log.Fatalf("unknown command %q (want \"migrate\")", os.Args[1])
		}
	}

	ctx := context.Background()
	pool, err := db.NewPool(ctx, cfg)
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	defer pool.Close()

	authHandler := &handlers.AuthHandler{DB: pool, JWTSecret: cfg.JWTSecret}
	projectHandler := &handlers.ProjectHandler{DB: pool}
	taskHandler := &handlers.TaskHandler{DB: pool}

	r := chi.NewRouter()
	r.Use(chimiddleware.Logger)
	r.Use(chimiddleware.Recoverer)
	r.Use(middleware.Metrics)

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	})

	r.Get("/readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		// A ping only proves a connection exists. On 2026-09-25 both replicas
		// reported Ready for eight hours against a database with no tables,
		// because Ping succeeds against an empty schema. Checking the migration
		// state is what distinguishes "connected" from "usable".
		var version int64
		var dirty bool
		err := pool.QueryRow(ctx,
			"select version, dirty from schema_migrations order by version desc limit 1",
		).Scan(&version, &dirty)

		switch {
		case err != nil:
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(map[string]any{"status": "not ready", "error": err.Error()})
			return
		case dirty:
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(map[string]any{"status": "not ready", "reason": "schema dirty", "schemaVersion": version})
			return
		}

		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{"status": "ready", "schemaVersion": version})
	})

	r.Post("/api/register", authHandler.Register)
	r.Post("/api/login", authHandler.Login)

	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth(cfg.JWTSecret))

		r.Route("/api/projects", func(r chi.Router) {
			r.Post("/", projectHandler.Create)
			r.Get("/", projectHandler.List)
			r.Get("/{id}", projectHandler.Get)
			r.Delete("/{id}", projectHandler.Delete)

			r.Route("/{projectID}/tasks", func(r chi.Router) {
				r.Post("/", taskHandler.Create)
				r.Get("/", taskHandler.ListByProject)
			})
		})

		r.Patch("/api/tasks/{id}/status", taskHandler.UpdateStatus)
		r.Delete("/api/tasks/{id}", taskHandler.Delete)
	})

	// Metrics listen on a separate port so the gateway cannot reach them. The
	// HTTPRoute matches PathPrefix / against 8080, which previously exposed
	// /metrics to anything able to reach the LoadBalancer address. The
	// NetworkPolicy for the gateway only permits 8080, so this boundary is now
	// structural rather than a matter of nobody having asked.
	metricsMux := http.NewServeMux()
	metricsMux.Handle("/metrics", promhttp.Handler())
	go func() {
		log.Printf("metrics listening on :%s", cfg.MetricsPort)
		// Not Fatal: losing metrics must not stop serving traffic.
		if err := http.ListenAndServe(":"+cfg.MetricsPort, metricsMux); err != nil {
			log.Printf("metrics server stopped: %v", err)
		}
	}()

	log.Printf("taskflow-api listening on :%s", cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, r); err != nil {
		log.Fatal(err)
	}
}
