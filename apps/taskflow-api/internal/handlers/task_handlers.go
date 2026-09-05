package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/Shaggydesai/production-kubernetes-platform/apps/taskflow-api/internal/models"
)

type TaskHandler struct {
	DB *pgxpool.Pool
}

func (h *TaskHandler) Create(w http.ResponseWriter, r *http.Request) {
	projectID := chi.URLParam(r, "projectID")

	var req struct {
		Title      string  `json:"title"`
		AssigneeID *string `json:"assignee_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Title == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "title required"})
		return
	}

	var t models.Task
	err := h.DB.QueryRow(r.Context(),
		`INSERT INTO tasks (project_id, assignee_id, title)
		 VALUES ($1, $2, $3)
		 RETURNING id, project_id, assignee_id, title, status, created_at, updated_at`,
		projectID, req.AssigneeID, req.Title,
	).Scan(&t.ID, &t.ProjectID, &t.AssigneeID, &t.Title, &t.Status, &t.CreatedAt, &t.UpdatedAt)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to create task (check project_id exists)"})
		return
	}
	writeJSON(w, http.StatusCreated, t)
}

func (h *TaskHandler) ListByProject(w http.ResponseWriter, r *http.Request) {
	projectID := chi.URLParam(r, "projectID")

	rows, err := h.DB.Query(r.Context(),
		`SELECT id, project_id, assignee_id, title, status, created_at, updated_at
		 FROM tasks WHERE project_id = $1 ORDER BY created_at DESC`,
		projectID,
	)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to list tasks"})
		return
	}
	defer rows.Close()

	tasks := []models.Task{}
	for rows.Next() {
		var t models.Task
		if err := rows.Scan(&t.ID, &t.ProjectID, &t.AssigneeID, &t.Title, &t.Status, &t.CreatedAt, &t.UpdatedAt); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to scan task"})
			return
		}
		tasks = append(tasks, t)
	}
	writeJSON(w, http.StatusOK, tasks)
}

func (h *TaskHandler) UpdateStatus(w http.ResponseWriter, r *http.Request) {
	taskID := chi.URLParam(r, "id")

	var req struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request"})
		return
	}

	tag, err := h.DB.Exec(r.Context(),
		`UPDATE tasks SET status = $1, updated_at = now() WHERE id = $2`,
		req.Status, taskID,
	)
	if err != nil || tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "task not found or invalid status"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *TaskHandler) Delete(w http.ResponseWriter, r *http.Request) {
	taskID := chi.URLParam(r, "id")

	tag, err := h.DB.Exec(r.Context(), `DELETE FROM tasks WHERE id = $1`, taskID)
	if err != nil || tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "task not found"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
