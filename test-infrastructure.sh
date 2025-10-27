#!/bin/bash

# ─────────────────────────────────────────────────────
# Auto-Deploy Platform Infrastructure Testing Script
# ─────────────────────────────────────────────────────

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Test functions
test_docker() {
    log_info "Testing Docker installation..."
    
    if command -v docker &> /dev/null; then
        log_success "Docker is installed"
        docker --version
        
        if docker ps &> /dev/null; then
            log_success "Docker daemon is running"
            echo "Running containers:"
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        else
            log_error "Docker daemon is not running"
            return 1
        fi
    else
        log_error "Docker is not installed"
        return 1
    fi
}

test_git() {
    log_info "Testing Git repository..."
    
    if command -v git &> /dev/null; then
        log_success "Git is installed"
        
        if [ -d ".git" ]; then
            log_success "Git repository is initialized"
            
            # Check if remote is configured
            if git remote -v | grep -q "origin"; then
                log_success "Git remote origin is configured"
                git remote -v
            else
                log_warning "Git remote origin is not configured"
                log_info "Run: git remote add origin https://github.com/BunathPheng/auto-deploy-platform.git"
            fi
            
            # Check git status
            log_info "Git status:"
            git status --short
        else
            log_error "Not in a Git repository"
            return 1
        fi
    else
        log_error "Git is not installed"
        return 1
    fi
}

test_helm() {
    log_info "Testing Helm installation..."
    
    if command -v helm &> /dev/null; then
        log_success "Helm is installed"
        helm version
        
        # Test Helm chart
        if [ -f "platform-shared/helm/app-chart/Chart.yaml" ]; then
            log_success "Helm chart found"
            
            # Validate chart
            if helm lint platform-shared/helm/app-chart/ &> /dev/null; then
                log_success "Helm chart validation passed"
            else
                log_warning "Helm chart validation failed"
                helm lint platform-shared/helm/app-chart/
            fi
        else
            log_error "Helm chart not found"
            return 1
        fi
    else
        log_warning "Helm is not installed"
        log_info "Install with: sudo snap install helm"
        return 1
    fi
}

test_kubernetes() {
    log_info "Testing Kubernetes cluster..."
    
    if command -v kubectl &> /dev/null; then
        log_success "kubectl is installed"
        
        if kubectl cluster-info &> /dev/null; then
            log_success "Kubernetes cluster is accessible"
            kubectl get nodes
        else
            log_warning "Kubernetes cluster is not accessible"
            log_info "Set up a cluster with: minikube start or kind create cluster"
            return 1
        fi
    else
        log_warning "kubectl is not installed"
        log_info "Install with: sudo snap install kubectl"
        return 1
    fi
}

test_platform_structure() {
    log_info "Testing platform structure..."
    
    # Check required directories
    required_dirs=(
        "platform-shared"
        "platform-shared/argocd"
        "platform-shared/helm"
        "platform-shared/jenkins"
        "platform-shared/scripts"
        "users"
        "users/_template"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_success "Directory exists: $dir"
        else
            log_error "Missing directory: $dir"
            return 1
        fi
    done
    
    # Check required files
    required_files=(
        "env.sh"
        "check-config.sh"
        "platform-shared/argocd/applicationset.yaml"
        "platform-shared/helm/app-chart/Chart.yaml"
        "platform-shared/helm/app-chart/values.yaml"
        "platform-shared/jenkins/pipelines/Jenkinsfile.template"
        "users/_template/config.yaml"
        "users/_template/values.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            log_success "File exists: $file"
        else
            log_error "Missing file: $file"
            return 1
        fi
    done
}

test_user_creation() {
    log_info "Testing user creation script..."
    
    if [ -f "platform-shared/scripts/onboard-user.sh" ]; then
        log_success "User onboarding script exists"
        
        # Test script syntax
        if bash -n platform-shared/scripts/onboard-user.sh; then
            log_success "User onboarding script syntax is valid"
        else
            log_error "User onboarding script has syntax errors"
            return 1
        fi
    else
        log_error "User onboarding script not found"
        return 1
    fi
}

test_project_creation() {
    log_info "Testing project creation script..."
    
    if [ -f "platform-shared/scripts/create-project.sh" ]; then
        log_success "Project creation script exists"
        
        # Test script syntax
        if bash -n platform-shared/scripts/create-project.sh; then
            log_success "Project creation script syntax is valid"
        else
            log_error "Project creation script has syntax errors"
            return 1
        fi
    else
        log_error "Project creation script not found"
        return 1
    fi
}

test_docker_registry() {
    log_info "Testing Docker registry connectivity..."
    
    registry=$(grep "REGISTRY=" env.sh | cut -d'"' -f2)
    log_info "Registry: $registry"
    
    # Test if we can pull a simple image
    if docker pull hello-world &> /dev/null; then
        log_success "Docker registry connectivity works"
        docker rmi hello-world &> /dev/null || true
    else
        log_warning "Docker registry connectivity issues"
    fi
}

test_jenkins_pipeline() {
    log_info "Testing Jenkins pipeline template..."
    
    if [ -f "platform-shared/jenkins/pipelines/Jenkinsfile.template" ]; then
        log_success "Jenkins pipeline template exists"
        
        # Check if it's a valid Jenkinsfile
        if grep -q "pipeline" platform-shared/jenkins/pipelines/Jenkinsfile.template; then
            log_success "Jenkins pipeline template is valid"
        else
            log_warning "Jenkins pipeline template may have issues"
        fi
    else
        log_error "Jenkins pipeline template not found"
        return 1
    fi
}

# Main testing function
main() {
    echo "🧪 Auto-Deploy Platform Infrastructure Testing"
    echo "=============================================="
    echo ""
    
    # Source environment
    if [ -f "env.sh" ]; then
        source env.sh
        log_success "Environment configuration loaded"
    else
        log_error "env.sh not found"
        exit 1
    fi
    
    echo ""
    log_info "Starting infrastructure tests..."
    echo ""
    
    # Run tests
    test_docker
    echo ""
    
    test_git
    echo ""
    
    test_platform_structure
    echo ""
    
    test_helm
    echo ""
    
    test_kubernetes
    echo ""
    
    test_user_creation
    echo ""
    
    test_project_creation
    echo ""
    
    test_docker_registry
    echo ""
    
    test_jenkins_pipeline
    echo ""
    
    # Summary
    echo "=============================================="
    log_info "Infrastructure Testing Complete!"
    echo ""
    log_info "Next steps:"
    log_info "1. Install missing components (Helm, kubectl)"
    log_info "2. Set up Kubernetes cluster (minikube/kind)"
    log_info "3. Configure Git remote repository"
    log_info "4. Run ./setup-platform.sh to deploy platform"
    log_info "5. Test with: ./onboard-user.sh testuser"
    echo ""
}

# Run main function
main "$@"
