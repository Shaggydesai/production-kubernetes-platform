// Package migrations embeds the SQL migration files into the binary.
//
// Embedding rather than reading them from disk means the schema and the code
// that queries it are one artifact: an image tag pins both. There is no way to
// run version N of the binary against version N-1 of the schema by accident.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
