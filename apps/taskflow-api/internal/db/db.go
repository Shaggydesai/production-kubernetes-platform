package db

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/Shaggydesai/production-kubernetes-platform/apps/taskflow-api/internal/config"
)

func NewPool(ctx context.Context, cfg config.Config) (*pgxpool.Pool, error) {
	// Built from discrete fields, not a URL string — passwords with special
	// characters (/, +, @, :) would otherwise corrupt a postgres:// URL.
	// (Confirmed with a real generated password during platform testing.)
	connCfg, err := pgxpool.ParseConfig("")
	if err != nil {
		return nil, fmt.Errorf("parsing base pgx config: %w", err)
	}
	connCfg.ConnConfig.Host = cfg.DBHost
	connCfg.ConnConfig.Port = 5432
	connCfg.ConnConfig.User = cfg.DBUser
	connCfg.ConnConfig.Password = cfg.DBPassword
	connCfg.ConnConfig.Database = cfg.DBName
	connCfg.MaxConns = 10
	connCfg.HealthCheckPeriod = 30 * time.Second

	pool, err := pgxpool.NewWithConfig(ctx, connCfg)
	if err != nil {
		return nil, fmt.Errorf("creating pgx pool: %w", err)
	}

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		return nil, fmt.Errorf("pinging database: %w", err)
	}

	return pool, nil
}
