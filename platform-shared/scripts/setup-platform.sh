#!/bin/bash

# ─────────────────────────────────────────────────────
# Auto-Deploy Platform Setup Script
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

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed. Please install helm first."
        exit 1
    fi
    
    # Check if argocd CLI is installed
    if ! command -v argocd &> /dev/null; then
        log_warning "ArgoCD CLI is not installed. Installing..."
        curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
        sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
        rm argocd-linux-amd64
    fi
    
    # Check kubectl connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    log_success "All prerequisites are met!"
}

install_argocd() {
    log_info "Installing ArgoCD..."
    
    # Create ArgoCD namespace
    kubectl apply -f "$PLATFORM_ROOT/platform-shared/argocd/install/namespace.yaml"
    
    # Install ArgoCD
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    
    # Get ArgoCD admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    log_success "ArgoCD installed successfully!"
    log_info "ArgoCD admin password: $ARGOCD_PASSWORD"
    log_info "Access ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

install_jenkins() {
    log_info "Installing Jenkins..."
    
    # Create Jenkins namespace and service account
    kubectl apply -f "$PLATFORM_ROOT/platform-shared/jenkins/k8s/namespace.yaml"
    kubectl apply -f "$PLATFORM_ROOT/platform-shared/jenkins/k8s/serviceaccount.yaml"
    
    # Install Jenkins using Helm
    helm repo add jenkins https://charts.jenkins.io
    helm repo update
    
    helm upgrade --install jenkins jenkins/jenkins \
        --namespace jenkins \
        --set controller.serviceAccountName=jenkins \
        --set controller.serviceAccount.create=false \
        --set controller.serviceType=LoadBalancer \
        --set controller.adminUser=admin \
        --set controller.adminPassword=admin123 \
        --wait
    
    log_success "Jenkins installed successfully!"
    log_info "Jenkins admin password: admin123"
}

setup_argocd_applicationset() {
    log_info "Setting up ArgoCD ApplicationSet..."
    
    # Apply the ApplicationSet
    kubectl apply -f "$PLATFORM_ROOT/platform-shared/argocd/applicationset.yaml"
    
    log_success "ArgoCD ApplicationSet configured!"
}

create_helm_repository() {
    log_info "Setting up Helm repository..."
    
    # Package the helm chart
    helm package "$PLATFORM_ROOT/platform-shared/helm/app-chart" -d "$PLATFORM_ROOT/platform-shared/helm/"
    
    log_success "Helm chart packaged!"
}

main() {
    log_info "Starting Auto-Deploy Platform setup..."
    
    check_prerequisites
    install_argocd
    install_jenkins
    setup_argocd_applicationset
    create_helm_repository
    
    log_success "Auto-Deploy Platform setup completed successfully!"
    log_info "Next steps:"
    log_info "1. Access ArgoCD UI and login with admin/$ARGOCD_PASSWORD"
    log_info "2. Access Jenkins UI and login with admin/admin123"
    log_info "3. Run ./onboard-user.sh <username> to onboard new users"
    log_info "4. Run ./create-project.sh <username> <project-name> to create new projects"
}

# Run main function
main "$@"
