package config

import "os"

type Config struct {
	Port        string
	MetricsPort string
	DBHost      string
	DBPort      string
	DBUser      string
	DBPassword  string
	DBName      string
	JWTSecret   string
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func Load() Config {
	return Config{
		Port:        getenv("PORT", "8080"),
		MetricsPort: getenv("METRICS_PORT", "9090"),
		DBHost:      getenv("DB_HOST", "postgresql.taskflow.svc"),
		DBPort:      getenv("DB_PORT", "5432"),
		DBUser:      getenv("DB_USER", "taskflow"),
		DBPassword:  os.Getenv("DB_PASSWORD"), // no fallback — must come from the mounted Secret
		DBName:      getenv("DB_NAME", "taskflow"),
		JWTSecret:   os.Getenv("JWT_SECRET"), // no fallback — must come from Vault too
	}
}
