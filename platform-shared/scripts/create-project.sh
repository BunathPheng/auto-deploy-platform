#!/bin/bash

# ─────────────────────────────────────────────────────
# Project Creation Script
# ─────────────────────────────────────────────────────

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$PLATFORM_ROOT/env.sh"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    echo "Usage: $0 <username> <project-name> [image-tag]"
    echo "  username:    The username who owns the project"
    echo "  project-name: The name of the project to create"
    echo "  image-tag:   Optional Docker image tag (default: latest)"
    exit 1
}

validate_inputs() {
    local username="$1"
    local project_name="$2"
    
    # Check if username is provided
    if [[ -z "$username" ]]; then
        log_error "Username is required"
        usage
    fi
    
    # Check if project name is provided
    if [[ -z "$project_name" ]]; then
        log_error "Project name is required"
        usage
    fi
    
    # Check if user exists
    if [[ ! -d "$PLATFORM_ROOT/users/$username" ]]; then
        log_error "User '$username' does not exist. Please run ./onboard-user.sh $username first"
        exit 1
    fi
    
    # Check project name format
    if [[ ! "$project_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
        log_error "Project name must contain only alphanumeric characters and hyphens"
        exit 1
    fi
    
    # Check if project already exists
    if [[ -d "$PLATFORM_ROOT/users/$username/projects/$project_name" ]]; then
        log_error "Project '$project_name' already exists for user '$username'"
        exit 1
    fi
}

create_project_structure() {
    local username="$1"
    local project_name="$2"
    local image_tag="${3:-latest}"
    
    log_info "Creating project structure for '$project_name'..."
    
    # Create project directory
    mkdir -p "$PLATFORM_ROOT/users/$username/projects/$project_name"
    
    # Create project-specific values.yaml
    cat > "$PLATFORM_ROOT/users/$username/projects/$project_name/values.yaml" << EOF
# Project-specific values for $project_name
replicaCount: 1

image:
  repository: $REGISTRY/$username-$project_name
  pullPolicy: IfNotPresent
  tag: "$image_tag"

nameOverride: "$project_name"
fullnameOverride: "$username-$project_name"

serviceAccount:
  create: true
  name: "$username-$project_name-sa"

podAnnotations:
  user: "$username"
  project: "$project_name"
  version: "$image_tag"

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
  hosts:
    - host: $project_name.$username.$ORG.local
      paths:
        - path: /
          pathType: Prefix
  tls: []

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi

env:
  - name: USERNAME
    value: "$username"
  - name: PROJECT_NAME
    value: "$project_name"
  - name: ENVIRONMENT
    value: "development"
  - name: VERSION
    value: "$image_tag"

# Health checks
livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
EOF

    # Create Dockerfile template
    cat > "$PLATFORM_ROOT/users/$username/projects/$project_name/Dockerfile" << EOF
# Dockerfile for $project_name
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY . .

# Create non-root user
RUN addgroup -g 1000 -S nodejs && \\
    adduser -S nodejs -u 1000

# Change ownership
RUN chown -R nodejs:nodejs /app
USER nodejs

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \\
  CMD curl -f http://localhost:8080/health || exit 1

# Start application
CMD ["npm", "start"]
EOF

    # Create package.json template
    cat > "$PLATFORM_ROOT/users/$username/projects/$project_name/package.json" << EOF
{
  "name": "$project_name",
  "version": "1.0.0",
  "description": "Project $project_name for user $username",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "dev": "nodemon index.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.0.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.1",
    "jest": "^29.6.2"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF

    # Create basic Express app
    cat > "$PLATFORM_ROOT/users/$username/projects/$project_name/index.js" << EOF
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');

const app = express();
const PORT = process.env.PORT || 8080;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Health check endpoints
app.get('/health', (req, res) => {
  res.status(200).json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    user: process.env.USERNAME,
    project: process.env.PROJECT_NAME,
    version: process.env.VERSION
  });
});

app.get('/ready', (req, res) => {
  res.status(200).json({ 
    status: 'ready', 
    timestamp: new Date().toISOString()
  });
});

// Main route
app.get('/', (req, res) => {
  res.json({
    message: 'Hello from $project_name!',
    user: process.env.USERNAME,
    project: process.env.PROJECT_NAME,
    version: process.env.VERSION,
    environment: process.env.ENVIRONMENT
  });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(\`Server running on port \${PORT}\`);
  console.log(\`User: \${process.env.USERNAME}\`);
  console.log(\`Project: \${process.env.PROJECT_NAME}\`);
  console.log(\`Version: \${process.env.VERSION}\`);
});
EOF

    # Create .dockerignore
    cat > "$PLATFORM_ROOT/users/$username/projects/$project_name/.dockerignore" << EOF
node_modules
npm-debug.log
.git
.gitignore
README.md
.env
.nyc_output
coverage
.DS_Store
EOF

    # Create .gitignore
    cat > "$PLATFORM_ROOT/users/$username/projects/$project_name/.gitignore" << EOF
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.env
.env.local
.env.development.local
.env.test.local
.env.production.local
.DS_Store
coverage/
.nyc_output/
EOF

    log_success "Project structure created for '$project_name'"
}

create_project_rbac() {
    local username="$1"
    local project_name="$2"
    
    log_info "Creating RBAC for project '$project_name'..."
    
    # Create ServiceAccount
    kubectl create serviceaccount "$username-$project_name-sa" -n "$username" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Role for the project
    cat << EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $username
  name: $username-$project_name-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["extensions", "networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF

    # Create RoleBinding
    cat << EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $username-$project_name-rolebinding
  namespace: $username
subjects:
- kind: ServiceAccount
  name: $username-$project_name-sa
  namespace: $username
roleRef:
  kind: Role
  name: $username-$project_name-role
  apiGroup: rbac.authorization.k8s.io
EOF

    log_success "RBAC created for project '$project_name'"
}

build_and_push_image() {
    local username="$1"
    local project_name="$2"
    local image_tag="$3"
    
    log_info "Building and pushing Docker image..."
    
    local image_name="$REGISTRY/$username-$project_name:$image_tag"
    local project_dir="$PLATFORM_ROOT/users/$username/projects/$project_name"
    
    # Build Docker image
    docker build -t "$image_name" "$project_dir"
    
    # Push to registry
    docker push "$image_name"
    
    log_success "Docker image built and pushed: $image_name"
}

deploy_project() {
    local username="$1"
    local project_name="$2"
    
    log_info "Deploying project '$project_name'..."
    
    # Use Helm to deploy
    helm upgrade --install "$username-$project_name" \
        "$PLATFORM_ROOT/platform-shared/helm/app-chart" \
        --namespace "$username" \
        --values "$PLATFORM_ROOT/users/$username/projects/$project_name/values.yaml" \
        --wait
    
    log_success "Project '$project_name' deployed successfully!"
}

main() {
    local username="$1"
    local project_name="$2"
    local image_tag="${3:-latest}"
    
    log_info "Creating project '$project_name' for user '$username'..."
    
    validate_inputs "$username" "$project_name"
    create_project_structure "$username" "$project_name" "$image_tag"
    create_project_rbac "$username" "$project_name"
    build_and_push_image "$username" "$project_name" "$image_tag"
    deploy_project "$username" "$project_name"
    
    log_success "Project '$project_name' created successfully!"
    log_info "Project details:"
    log_info "  - User: $username"
    log_info "  - Project: $project_name"
    log_info "  - Namespace: $username"
    log_info "  - Image: $REGISTRY/$username-$project_name:$image_tag"
    log_info "  - URL: http://$project_name.$username.$ORG.local"
    log_info "  - Directory: $PLATFORM_ROOT/users/$username/projects/$project_name"
}

# Check arguments
if [[ $# -lt 2 ]]; then
    usage
fi

# Run main function
main "$@"
