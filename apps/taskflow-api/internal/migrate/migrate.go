// Package migrate applies the embedded SQL migrations.
package migrate

import (
	"errors"
	"fmt"
	"log"
	"net"
	"net/url"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	"github.com/golang-migrate/migrate/v4/source/iofs"

	"github.com/Shaggydesai/production-kubernetes-platform/apps/taskflow-api/internal/config"
	"github.com/Shaggydesai/production-kubernetes-platform/apps/taskflow-api/migrations"
)

// dsn builds the connection URL golang-migrate requires.
//
// It is assembled with net/url, not fmt.Sprintf: a generated password
// containing /, +, @ or : corrupts a hand-built URL. internal/db sidesteps the
// problem by using discrete fields, but golang-migrate accepts only a string,
// so the escaping has to be explicit here.
func dsn(cfg config.Config) string {
	u := url.URL{
		Scheme: "pgx5",
		User:   url.UserPassword(cfg.DBUser, cfg.DBPassword),
		Host:   net.JoinHostPort(cfg.DBHost, cfg.DBPort),
		Path:   "/" + cfg.DBName,
	}
	q := url.Values{}
	q.Set("sslmode", "prefer")
	q.Set("x-migrations-table", "schema_migrations")
	u.RawQuery = q.Encode()
	return u.String()
}

// Run applies all pending migrations ("up") or rolls back exactly one ("down").
//
// golang-migrate takes a Postgres advisory lock for the duration, so a retried
// Job or a concurrent runner waits rather than corrupting the schema.
func Run(cfg config.Config, direction string) error {
	if cfg.DBPassword == "" {
		return errors.New("DB_PASSWORD is empty: the credentials Secret is absent or not mounted")
	}

	src, err := iofs.New(migrations.FS, ".")
	if err != nil {
		return fmt.Errorf("opening embedded migrations: %w", err)
	}

	m, err := migrate.NewWithSourceInstance("iofs", src, dsn(cfg))
	if err != nil {
		return fmt.Errorf("creating migrator: %w", err)
	}
	defer func() {
		if srcErr, dbErr := m.Close(); srcErr != nil || dbErr != nil {
			log.Printf("closing migrator: source=%v database=%v", srcErr, dbErr)
		}
	}()

	before, dirty, err := m.Version()
	if err != nil && !errors.Is(err, migrate.ErrNilVersion) {
		return fmt.Errorf("reading current schema version: %w", err)
	}
	if dirty {
		return fmt.Errorf("schema is dirty at version %d: a previous migration failed "+
			"part-way and must be resolved by hand before migrating again", before)
	}

	switch direction {
	case "up":
		err = m.Up()
	case "down":
		err = m.Steps(-1)
	default:
		return fmt.Errorf("unknown direction %q (want \"up\" or \"down\")", direction)
	}

	if errors.Is(err, migrate.ErrNoChange) {
		log.Printf("schema already at version %d, nothing to apply", before)
		return nil
	}
	if err != nil {
		return fmt.Errorf("applying migrations: %w", err)
	}

	after, _, err := m.Version()
	if err != nil {
		return fmt.Errorf("reading resulting schema version: %w", err)
	}
	log.Printf("schema migrated %d -> %d", before, after)
	return nil
}
