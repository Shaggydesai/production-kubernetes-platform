# Helm

This directory contains Helm charts used by the production Kubernetes platform.

## Purpose

Helm provides the packaging and release mechanism for Kubernetes platform components.

The repository is the source of truth for chart configuration. Charts should be version-controlled and deployed through the platform's GitOps workflow as the project evolves.

## Structure

    helm/
    ├── README.md
    ├── platform/
    │   └── ...
    └── applications/
        └── ...
