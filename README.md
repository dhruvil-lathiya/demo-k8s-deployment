# Demo K8s Deployment — Kubernetes Deployment Lifecycle

This is a demo of deploying a Python/Flask API on Kubernetes. It covers version updates, testing simulated failures and fixing it. 

## Architecture

GitHub Repo (tags: v1.0, v2.0)
    │
    |- GitHub Actions CI - Build & Push ─> Docker Hub (lathiya97/demo-k8s-api)
    │
    └- GitHub Actions CD - Deploy -> Minikube Cluster
                                            ├── Deployment (3 replicas, RollingUpdate)
                                            ├── Service (NodePort:30007)
                                            └── Health Probes → /health, /ready

## Versioning Strategy

Each Git tag is directly linked to a Docker image tag. This makes it easy to track and check which source code is used in the running container.

| Git Tag    | Docker Image Tag                   | Description           |
|------------|------------------------------------|-----------------------|
| `v1.0`     | `lathiya97/demo-k8s-api:1.0`      | Initial release       |
| `v2.0`     | `lathiya97/demo-k8s-api:2.0`      | Rolling update        |
| —          | `lathiya97/demo-k8s-api:bad`       | Simulated failure     |

The CI pipeline also adds a Git commit SHA tag to every image. This helps to know the exact commit used for that image. The latest tag is used only when a version tag is pushed. For production deployment, we always use a proper version tag, not the latest tag.

## Deployment Workflow

### Prerequisites

- Docker Desktop
- Minikube (`minikube start`)
- kubectl configured for minikube

### Step-by-Step Lifecycle

#### 1. Initial Deployment (v1.0)


# Build and load image into minikube
docker build -t lathiya97/demo-k8s-api:1.0 -f docker/Dockerfile .
minikube image load lathiya97/demo-k8s-api:1.0

# Deploy
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Verify
kubectl get pods -l app=demo-k8s-api
./scripts/validate.sh


#### 2. Rolling Update (v2.0)


# Build v2.0
docker build --build-arg APP_VERSION=2.0 -t lathiya97/demo-k8s-api:2.0 -f docker/Dockerfile .
minikube image load lathiya97/demo-k8s-api:2.0

# Update deployment image
kubectl set image deployment/demo-k8s-api demo-k8s-api=lathiya97/demo-k8s-api:2.0

# Watch rolling update
kubectl rollout status deployment/demo-k8s-api

# Verify
curl $(minikube service demo-k8s-api-svc --url)/version


In rolling update, maxSurge: 1 and maxUnavailable: 0 are used. This means Kubernetes creates one new pod at a time. It removes old pod only after the new pod is ready and passes readiness check.
Because of this, there is no downtime. The application keeps running without stopping.

#### 3. Simulate Failed Release

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


In the "bad" version, SIMULATE_FAILURE=true is set. Because of this, the /health and /ready endpoints return 500 or 503 error. The readiness probe stops traffic from going to this pod. The liveness probe keeps restarting the pod. Due to continuous restarts, the pod goes into CrashLoopBackOff state.

#### 4. Troubleshooting Workflow

When a deployment fails, we check the following:

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


#### 5. Rollback and Recovery


# Rollback to previous healthy revision
kubectl rollout undo deployment/demo-k8s-api

# Confirm rollback completes
kubectl rollout status deployment/demo-k8s-api

# Validate recovery
./scripts/validate.sh
echo $?   # Output: 0


## Rollback Decision Process

Rollback will start if any of these problems happen:

1. **Readiness probe failures** - New pods do not become Ready in expected time.
2. **CrashLoopBackOff** - Containers keep crashing again and again after start.
3. **Validation script returns exit 1** — Automated health check fails
4. **Rollout timeout** — `kubectl rollout status` does not complete within 120 seconds


Deploy new version
    │
Run validate.sh
    │
    ├── Exit 0 -> Healthy — proceed
    │
    └── Exit 1 -> Unhealthy
                    │
              kubectl rollout undo
                    │
              Re-run validate.sh -> Confirm recovery


In the CI/CD pipeline, the CD workflow does this automatically. After deployment, it runs validate.sh. If the validation fails, it automatically starts a rollback.

## Validation Script

`scripts/validate.sh` performs 5 checks:

1. **Rollout status** — Checks if the deployment finished
2. **Replica readiness** — Makes sure desired replicas match ready replicas.
3. **CrashLoopBackOff detection** — Scans for pods stuck in crash loops
4. **Restart count** — Warns if any pod has restarted too many times
5. **Image version** — Shows the running image versions for tracking.

Returns exit code: 0 means healthy, and 1 means unhealthy.


## CI/CD Pipeline (GitHub Actions)

### CI Workflow (`.github/workflows/ci.yaml`)
- **Trigger**: on Push to `main` or version tag (`v*.*`)
- **Steps**: Build Docker image, tag with version and commit SHA, push to Docker Hub
- **PR builds**: Only build (no push) to check Dockerfile

### CD Workflow (`.github/workflows/cd.yaml`)
- **Trigger**: Runs after CI succeeds
- **Steps**: Applies K8s manifests, waits for rollout, runs validation script
- **Auto-rollback**: If `validate.sh` returns exit 1, rollback happens automatically

### Required GitHub Secrets

| Secret            | Description             |
|-------------------|-------------------------|
| `DOCKER_USERNAME` | Docker Hub username      |
| `DOCKER_PASSWORD` | Docker Hub access token  |
| `KUBE_CONFIG`     | Base64 kubeconfig        |

## Git Tag Traceability


git tag              # List all release tags
git show v1.0        # View tag details and linked commit


Each Git tag matches 1:1 to a Docker image tag. The CI pipeline also adds the commit SHA to every image.

## Project Structure

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
