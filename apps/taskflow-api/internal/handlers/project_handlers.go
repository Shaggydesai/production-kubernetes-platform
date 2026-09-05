package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/Shaggydesai/production-kubernetes-platform/apps/taskflow-api/internal/middleware"
	"github.com/Shaggydesai/production-kubernetes-platform/apps/taskflow-api/internal/models"
)

type ProjectHandler struct {
	DB *pgxpool.Pool
}

func userIDFromContext(r *http.Request) string {
	v, _ := r.Context().Value(middleware.UserIDKey).(string)
	return v
}

func (h *ProjectHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "name required"})
		return
	}

	ownerID := userIDFromContext(r)
	var p models.Project
	err := h.DB.QueryRow(r.Context(),
		`INSERT INTO projects (name, owner_id) VALUES ($1, $2) RETURNING id, name, owner_id, created_at`,
		req.Name, ownerID,
	).Scan(&p.ID, &p.Name, &p.OwnerID, &p.CreatedAt)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to create project"})
		return
	}
	writeJSON(w, http.StatusCreated, p)
}

func (h *ProjectHandler) List(w http.ResponseWriter, r *http.Request) {
	ownerID := userIDFromContext(r)
	rows, err := h.DB.Query(r.Context(),
		`SELECT id, name, owner_id, created_at FROM projects WHERE owner_id = $1 ORDER BY created_at DESC`,
		ownerID,
	)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to list projects"})
		return
	}
	defer rows.Close()

	projects := []models.Project{}
	for rows.Next() {
		var p models.Project
		if err := rows.Scan(&p.ID, &p.Name, &p.OwnerID, &p.CreatedAt); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to scan project"})
			return
		}
		projects = append(projects, p)
	}
	writeJSON(w, http.StatusOK, projects)
}

func (h *ProjectHandler) Get(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	ownerID := userIDFromContext(r)

	var p models.Project
	err := h.DB.QueryRow(r.Context(),
		`SELECT id, name, owner_id, created_at FROM projects WHERE id = $1 AND owner_id = $2`,
		id, ownerID,
	).Scan(&p.ID, &p.Name, &p.OwnerID, &p.CreatedAt)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "project not found"})
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (h *ProjectHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	ownerID := userIDFromContext(r)

	tag, err := h.DB.Exec(r.Context(),
		`DELETE FROM projects WHERE id = $1 AND owner_id = $2`, id, ownerID,
	)
	if err != nil || tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "project not found"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
