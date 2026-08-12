\# Container Registry Internals



\## Overview



A container registry stores OCI-compliant container images.



Examples include Docker Hub, Harbor, Amazon ECR, Azure ACR, Google Artifact Registry, and GitHub Container Registry.



\---



\## Components



\- Repository

\- Tags

\- Manifest

\- Config

\- Blobs



\---



\## Push Workflow



```

docker push



↓



Authenticate



↓



Upload Config



↓



Upload Layers



↓



Upload Manifest



↓



Create Tag

```



\---



\## Pull Workflow



```

docker pull



↓



Download Manifest



↓



Download Missing Layers



↓



Verify Digests



↓



Store Content



↓



Ready

```



\---



\## Harbor Components



\- Registry

\- Core

\- Database

\- Redis

\- Job Service

\- Trivy



\---



\## Security Features



\- Immutable Tags

\- Vulnerability Scanning

\- Image Signing (Cosign)

\- SBOM

\- RBAC

\- Robot Accounts



\---



\## Best Practices



\- Avoid `latest` in production.

\- Enable vulnerability scanning.

\- Sign production images.

\- Use immutable version tags.

\- Run garbage collection regularly.

