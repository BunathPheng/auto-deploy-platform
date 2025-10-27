#!/bin/bash

# ─────────────────────────────────────────────────────
# User Onboarding Script
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
    echo "Usage: $0 <username> [email]"
    echo "  username: The username for the new user"
    echo "  email:    Optional email address for the user"
    exit 1
}

validate_username() {
    local username="$1"
    
    # Check if username is provided
    if [[ -z "$username" ]]; then
        log_error "Username is required"
        usage
    fi
    
    # Check username format (alphanumeric and hyphens only)
    if [[ ! "$username" =~ ^[a-zA-Z0-9-]+$ ]]; then
        log_error "Username must contain only alphanumeric characters and hyphens"
        exit 1
    fi
    
    # Check if user already exists
    if [[ -d "$PLATFORM_ROOT/users/$username" ]]; then
        log_error "User '$username' already exists"
        exit 1
    fi
}

create_user_directory() {
    local username="$1"
    local email="${2:-}"
    
    log_info "Creating user directory for '$username'..."
    
    # Create user directory
    mkdir -p "$PLATFORM_ROOT/users/$username"
    
    # Copy template configuration
    cp "$PLATFORM_ROOT/users/_template/config.yaml" "$PLATFORM_ROOT/users/$username/config.yaml"
    
    # Create user-specific values.yaml
    cat > "$PLATFORM_ROOT/users/$username/values.yaml" << EOF
# User-specific values for $username
replicaCount: 1

image:
  repository: $REGISTRY/$username-app
  pullPolicy: IfNotPresent
  tag: "latest"

nameOverride: "$username"
fullnameOverride: "$username"

serviceAccount:
  create: true
  name: "$username-sa"

podAnnotations:
  user: "$username"
  email: "$email"

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
    - host: $username.$ORG.local
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
  - name: ENVIRONMENT
    value: "development"
EOF

    log_success "User directory created for '$username'"
}

create_user_namespace() {
    local username="$1"
    
    log_info "Creating Kubernetes namespace for '$username'..."
    
    # Create namespace
    kubectl create namespace "$username" --dry-run=client -o yaml | kubectl apply -f -
    
    # Add labels
    kubectl label namespace "$username" user="$username" --overwrite
    
    log_success "Namespace '$username' created"
}

create_user_rbac() {
    local username="$1"
    
    log_info "Creating RBAC for user '$username'..."
    
    # Create ServiceAccount
    kubectl create serviceaccount "$username-sa" -n "$username" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Role
    cat << EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $username
  name: $username-role
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
  name: $username-rolebinding
  namespace: $username
subjects:
- kind: ServiceAccount
  name: $username-sa
  namespace: $username
roleRef:
  kind: Role
  name: $username-role
  apiGroup: rbac.authorization.k8s.io
EOF

    log_success "RBAC created for user '$username'"
}

create_user_kubeconfig() {
    local username="$1"
    
    log_info "Creating kubeconfig for user '$username'..."
    
    # Get the service account token
    SECRET_NAME=$(kubectl get serviceaccount "$username-sa" -n "$username" -o jsonpath='{.secrets[0].name}')
    TOKEN=$(kubectl get secret "$SECRET_NAME" -n "$username" -o jsonpath='{.data.token}' | base64 -d)
    
    # Get cluster info
    CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
    CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    CLUSTER_CA=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
    
    # Create kubeconfig
    cat > "$PLATFORM_ROOT/users/$username/kubeconfig" << EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CLUSTER_CA
    server: $CLUSTER_SERVER
  name: $CLUSTER_NAME
contexts:
- context:
    cluster: $CLUSTER_NAME
    namespace: $username
    user: $username
  name: $username-context
current-context: $username-context
users:
- name: $username
  user:
    token: $TOKEN
EOF

    log_success "Kubeconfig created for user '$username'"
    log_info "Kubeconfig location: $PLATFORM_ROOT/users/$username/kubeconfig"
}

main() {
    local username="$1"
    local email="${2:-}"
    
    log_info "Onboarding user '$username'..."
    
    validate_username "$username"
    create_user_directory "$username" "$email"
    create_user_namespace "$username"
    create_user_rbac "$username"
    create_user_kubeconfig "$username"
    
    log_success "User '$username' onboarded successfully!"
    log_info "Next steps:"
    log_info "1. User can now deploy applications to namespace '$username'"
    log_info "2. Use kubeconfig: $PLATFORM_ROOT/users/$username/kubeconfig"
    log_info "3. Run ./create-project.sh $username <project-name> to create projects"
}

# Check arguments
if [[ $# -lt 1 ]]; then
    usage
fi

# Run main function
main "$@"
