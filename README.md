# Demo K8s Deployment — Kubernetes Deployment Lifecycle

A complete Kubernetes deployment lifecycle demonstration for a Python/Flask API, including versioned rolling updates, failure simulation, troubleshooting, rollback, and automated deployment validation.

## Architecture

```
GitHub Repo (tags: v1.0, v2.0)
    │
    ├── GitHub Actions CI ─── Build & Push ──► Docker Hub (lathiya97/demo-k8s-api)
    │
    └── GitHub Actions CD ─── Deploy ──► Minikube Cluster
                                            ├── Deployment (3 replicas, RollingUpdate)
                                            ├── Service (NodePort:30007)
                                            └── Health Probes → /health, /ready
```

## Versioning Strategy

The project uses **Semantic Versioning** with Git-to-Docker traceability. Each Git tag maps directly to a Docker image tag, providing full auditability from source code to running container.

| Git Tag    | Docker Image Tag                   | Description           |
|------------|------------------------------------|-----------------------|
| `v1.0`     | `lathiya97/demo-k8s-api:1.0`      | Initial release       |
| `v2.0`     | `lathiya97/demo-k8s-api:2.0`      | Rolling update        |
| —          | `lathiya97/demo-k8s-api:bad`       | Simulated failure     |

The CI pipeline also tags every image with the Git commit SHA for exact commit traceability. The `latest` tag is only applied on version tag pushes — production deployments always reference explicit version tags.

## Deployment Workflow

### Prerequisites

- Docker Desktop
- Minikube (`minikube start`)
- kubectl configured for minikube

### Step-by-Step Lifecycle

#### 1. Initial Deployment (v1.0)

```bash
# Build and load image into minikube
docker build -t lathiya97/demo-k8s-api:1.0 -f docker/Dockerfile .
minikube image load lathiya97/demo-k8s-api:1.0

# Deploy
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Verify
kubectl get pods -l app=demo-k8s-api
./scripts/validate.sh
```

#### 2. Rolling Update (v2.0)

```bash
# Build v2.0
docker build --build-arg APP_VERSION=2.0 -t lathiya97/demo-k8s-api:2.0 -f docker/Dockerfile .
minikube image load lathiya97/demo-k8s-api:2.0

# Update deployment image
kubectl set image deployment/demo-k8s-api demo-k8s-api=lathiya97/demo-k8s-api:2.0

# Watch rolling update
kubectl rollout status deployment/demo-k8s-api

# Verify
curl $(minikube service demo-k8s-api-svc --url)/version
```

The rolling update uses `maxSurge: 1` and `maxUnavailable: 0`, meaning Kubernetes creates one new pod at a time and only removes old pods after the new ones pass readiness checks — ensuring zero downtime.

#### 3. Simulate Failed Release

```bash
# Build the "bad" image
docker build --build-arg APP_VERSION=1.2-bad -t lathiya97/demo-k8s-api:bad -f docker/Dockerfile .
minikube image load lathiya97/demo-k8s-api:bad

# Deploy the broken version
kubectl apply -f k8s/deployment-bad.yaml

# Observe the failure
kubectl get pods -l app=demo-k8s-api
kubectl describe pod <failing-pod-name>
kubectl logs <failing-pod-name>

# Run validation — exits with code 1
./scripts/validate.sh
echo $?   # Output: 1
```

The "bad" version sets `SIMULATE_FAILURE=true`, causing `/health` and `/ready` to return 500/503. The readiness probe blocks traffic routing, and the liveness probe triggers restarts leading to `CrashLoopBackOff`.

#### 4. Troubleshooting Workflow

When a deployment fails, investigation follows this sequence:

```bash
# 1. Check pod status overview
kubectl get pods -l app=demo-k8s-api

# 2. Describe failing pod for events and probe failures
kubectl describe pod <pod-name>

# 3. Check application logs
kubectl logs <pod-name>

# 4. Review rollout history
kubectl rollout history deployment/demo-k8s-api

# 5. Run automated validation
./scripts/validate.sh
```

#### 5. Rollback and Recovery

```bash
# Rollback to previous healthy revision
kubectl rollout undo deployment/demo-k8s-api

# Confirm rollback completes
kubectl rollout status deployment/demo-k8s-api

# Validate recovery
./scripts/validate.sh
echo $?   # Output: 0
```

## Rollback Decision Process

A rollback is triggered when any of these conditions are detected:

1. **Readiness probe failures** — New pods don't become Ready within expected timeframe
2. **CrashLoopBackOff** — Containers crash repeatedly after starting
3. **Validation script returns exit 1** — Automated health check fails
4. **Rollout timeout** — `kubectl rollout status` doesn't complete within 120 seconds

```
Deploy new version
    │
    ▼
Run validate.sh
    │
    ├── Exit 0 → ✅ Healthy — proceed
    │
    └── Exit 1 → ❌ Unhealthy
                    │
                    ▼
              kubectl rollout undo
                    │
                    ▼
              Re-run validate.sh → Confirm recovery
```

In the CI/CD pipeline, the CD workflow automates this: it runs `validate.sh` after deployment and triggers an automatic rollback if validation fails.

## Validation Script

`scripts/validate.sh` performs 5 checks:

1. **Rollout status** — Confirms the deployment rollout completed
2. **Replica readiness** — Verifies desired replicas == ready replicas
3. **CrashLoopBackOff detection** — Scans for pods stuck in crash loops
4. **Restart count** — Warns if any pod has excessive restarts (>3)
5. **Image version** — Displays running image versions for traceability

Returns exit code `0` (healthy) or `1` (unhealthy).

```bash
./scripts/validate.sh                         # Uses defaults (demo-k8s-api, default namespace)
./scripts/validate.sh demo-k8s-api default    # Explicit deployment and namespace
```

## CI/CD Pipeline (GitHub Actions)

### CI Workflow (`.github/workflows/ci.yaml`)
- **Trigger**: Push to `main` or version tag (`v*.*`)
- **Actions**: Builds Docker image, tags with version + commit SHA, pushes to Docker Hub
- **PR builds**: Build-only (no push) to validate Dockerfile

### CD Workflow (`.github/workflows/cd.yaml`)
- **Trigger**: After successful CI run
- **Actions**: Applies K8s manifests, waits for rollout, runs validation script
- **Auto-rollback**: If `validate.sh` returns exit 1, automatically rolls back

### Required GitHub Secrets

| Secret            | Description             |
|-------------------|-------------------------|
| `DOCKER_USERNAME` | Docker Hub username      |
| `DOCKER_PASSWORD` | Docker Hub access token  |
| `KUBE_CONFIG`     | Base64 kubeconfig        |

## Git Tag Traceability

```bash
git tag              # List all release tags
git show v1.0        # View tag details and linked commit
```

Each Git tag maps 1:1 to a Docker image tag. The CI pipeline also stamps every image with the commit SHA, providing two levels of traceability: semantic version for humans, commit hash for exact code reference.

## Project Structure

```
.
├── app/
│   ├── app.py                    # Flask API with health/readiness probes
│   └── requirements.txt          # Python dependencies
├── docker/
│   └── Dockerfile                # Production container (gunicorn, non-root)
├── k8s/
│   ├── deployment.yaml           # Production deployment manifest
│   ├── deployment-bad.yaml       # Simulated failure manifest
│   └── service.yaml              # NodePort service
├── scripts/
│   └── validate.sh               # Deployment health validation
├── screenshots/                  # Evidence of deployment lifecycle
├── .github/workflows/
│   ├── ci.yaml                   # Build & push pipeline
│   └── cd.yaml                   # Deploy & validate pipeline
└── README.md
```

## Assumptions

1. **Local cluster**: Minikube with images loaded via `minikube image load` rather than registry pull
2. **Single namespace**: `default` namespace for simplicity; production would use dedicated namespaces with RBAC
3. **NodePort service**: For local minikube access; production would use Ingress or LoadBalancer
4. **3 replicas**: Demonstrates rolling update behavior; production count depends on traffic and HA requirements
5. **Plain YAML manifests**: No Helm, to demonstrate core Kubernetes concepts directly
6. **No secrets management**: Demo API has no sensitive config; production would use K8s Secrets or Vault

## Production Readiness Improvements

If this were a production system, I would add:

- **Helm charts** for templated deployments across environments (dev/staging/prod)
- **Horizontal Pod Autoscaler (HPA)** for load-based scaling
- **Pod Disruption Budgets (PDB)** to maintain availability during node maintenance
- **Network Policies** to restrict pod-to-pod communication
- **Canary deployments** using Argo Rollouts or Flagger for progressive delivery
- **Image vulnerability scanning** (Trivy/Snyk) in the CI pipeline
- **Prometheus + Grafana** for metrics, alerting, and deployment dashboards
- **GitOps with ArgoCD** for declarative, auditable, drift-detected deployments
- **Namespace isolation with RBAC** for multi-team environments
