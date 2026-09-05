# --- Build stage ---
FROM golang:1-alpine AS builder

WORKDIR /build

# Cache dependency downloads separately from source changes
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Static binary, no CGO, stripped debug symbols for a smaller binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /build/bin/taskflow-api ./cmd/api

# --- Final stage ---
FROM alpine:3.20

RUN apk add --no-cache ca-certificates && \
    addgroup -S taskflow && adduser -S taskflow -G taskflow

WORKDIR /app

COPY --from=builder /build/bin/taskflow-api .
COPY --from=builder /build/migrations ./migrations

USER taskflow

EXPOSE 8080

ENTRYPOINT ["/app/taskflow-api"]
