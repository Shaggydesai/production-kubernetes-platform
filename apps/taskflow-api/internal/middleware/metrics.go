package middleware

import (
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	requests = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "taskflow_http_requests_total",
		Help: "HTTP requests by method, chi route pattern and status code.",
	}, []string{"method", "route", "code"})

	duration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "taskflow_http_request_duration_seconds",
		Help:    "HTTP request latency by method and chi route pattern.",
		Buckets: prometheus.DefBuckets,
	}, []string{"method", "route"})
)

type statusRecorder struct {
	http.ResponseWriter
	code int
}

func (s *statusRecorder) WriteHeader(c int) {
	s.code = c
	s.ResponseWriter.WriteHeader(c)
}

// Metrics records request counts and latency.
//
// The "route" label is chi's ROUTE PATTERN, not the request path. /api/projects/
// {id} must stay a single time series; labelling by the raw path would create
// one series per UUID and eventually take Prometheus down - which on a
// Longhorn-backed TSDB would not take long.
func Metrics(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Default 200: a handler that calls Write without WriteHeader never
		// reaches our WriteHeader, but has still served a 200.
		rec := &statusRecorder{ResponseWriter: w, code: http.StatusOK}
		start := time.Now()

		next.ServeHTTP(rec, r)

		// Only valid once the router has matched, i.e. after ServeHTTP.
		route := chi.RouteContext(r.Context()).RoutePattern()
		if route == "" {
			route = "unmatched"
		}
		requests.WithLabelValues(r.Method, route, strconv.Itoa(rec.code)).Inc()
		duration.WithLabelValues(r.Method, route).Observe(time.Since(start).Seconds())
	})
}
