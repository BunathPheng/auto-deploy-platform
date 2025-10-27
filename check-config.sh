#!/bin/bash

# ─────────────────────────────────────────────────────
# Configuration Tracking Script
# ─────────────────────────────────────────────────────

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$SCRIPT_DIR"
if [[ -f "$PLATFORM_ROOT/env.sh" ]]; then
    source "$PLATFORM_ROOT/env.sh"
else
    log_error "env.sh not found at $PLATFORM_ROOT/env.sh"
    exit 1
fi

check_env_config() {
    log_info "Checking environment configuration..."
    
    local issues=0
    
    # Check if registry is still default
    if [[ "$REGISTRY" == "docker.io/acme" ]]; then
        log_warning "Container registry is still set to default: $REGISTRY"
        log_warning "  Update in: $PLATFORM_ROOT/env.sh"
        ((issues++))
    else
        log_success "Container registry configured: $REGISTRY"
    fi
    
    # Check if org is still default
    if [[ "$ORG" == "acme" ]]; then
        log_warning "Organization is still set to default: $ORG"
        log_warning "  Update in: $PLATFORM_ROOT/env.sh"
        ((issues++))
    else
        log_success "Organization configured: $ORG"
    fi
    
    # Check if git repo is still default
    if [[ "$GIT_PLATFORM_REPO" == "https://github.com/acme/auto-deploy-platform.git" ]]; then
        log_warning "Git repository is still set to default: $GIT_PLATFORM_REPO"
        log_warning "  Update in: $PLATFORM_ROOT/env.sh"
        ((issues++))
    else
        log_success "Git repository configured: $GIT_PLATFORM_REPO"
    fi
    
    return $issues
}

check_helm_config() {
    log_info "Checking Helm chart configuration..."
    
    local issues=0
    
    # Check values.yaml for default image
    if grep -q "docker.io/acme/app" "$PLATFORM_ROOT/platform-shared/helm/app-chart/values.yaml"; then
        log_warning "Default image repository found in values.yaml"
        log_warning "  Update in: $PLATFORM_ROOT/platform-shared/helm/app-chart/values.yaml"
        ((issues++))
    else
        log_success "Image repository configured in values.yaml"
    fi
    
    # Check Chart.yaml for default URLs
    if grep -q "https://github.com/acme/auto-deploy-platform" "$PLATFORM_ROOT/platform-shared/helm/app-chart/Chart.yaml"; then
        log_warning "Default URLs found in Chart.yaml"
        log_warning "  Update in: $PLATFORM_ROOT/platform-shared/helm/app-chart/Chart.yaml"
        ((issues++))
    else
        log_success "Chart.yaml URLs configured"
    fi
    
    return $issues
}

check_argocd_config() {
    log_info "Checking ArgoCD configuration..."
    
    local issues=0
    
    # Check applicationset.yaml for default repo
    if grep -q "https://github.com/acme/auto-deploy-platform.git" "$PLATFORM_ROOT/platform-shared/argocd/applicationset.yaml"; then
        log_warning "Default repository URL found in applicationset.yaml"
        log_warning "  Update in: $PLATFORM_ROOT/platform-shared/argocd/applicationset.yaml"
        ((issues++))
    else
        log_success "ArgoCD repository URL configured"
    fi
    
    return $issues
}

check_user_template() {
    log_info "Checking user template configuration..."
    
    local issues=0
    
    # Check for default image in user template
    if grep -q "docker.io/acme/my-app" "$PLATFORM_ROOT/users/_template/config.yaml"; then
        log_warning "Default image repository found in user template"
        log_warning "  Update in: $PLATFORM_ROOT/users/_template/config.yaml"
        ((issues++))
    else
        log_success "User template image repository configured"
    fi
    
    # Check for default host in user template
    if grep -q "my-app.example.com" "$PLATFORM_ROOT/users/_template/config.yaml"; then
        log_warning "Default host found in user template"
        log_warning "  Update in: $PLATFORM_ROOT/users/_template/config.yaml"
        ((issues++))
    else
        log_success "User template host configured"
    fi
    
    return $issues
}

check_scripts_config() {
    log_info "Checking scripts configuration..."
    
    local issues=0
    
    # Check if scripts reference correct paths
    if ! grep -q "PLATFORM_ROOT" "$PLATFORM_ROOT/platform-shared/scripts/setup-platform.sh"; then
        log_warning "PLATFORM_ROOT variable not found in setup-platform.sh"
        ((issues++))
    else
        log_success "Scripts properly configured with PLATFORM_ROOT"
    fi
    
    return $issues
}

generate_customization_report() {
    log_info "Generating customization report..."
    
    local total_issues=0
    
    check_env_config
    ((total_issues += $?))
    
    check_helm_config
    ((total_issues += $?))
    
    check_argocd_config
    ((total_issues += $?))
    
    check_user_template
    ((total_issues += $?))
    
    check_scripts_config
    ((total_issues += $?))
    
    echo ""
    log_info "=== CUSTOMIZATION REPORT ==="
    
    if [[ $total_issues -eq 0 ]]; then
        log_success "All configurations are properly customized!"
        log_success "Your platform is ready for deployment."
    else
        log_warning "Found $total_issues configuration issues that need attention."
        log_warning "Please review the warnings above and update the configurations."
        log_info "Refer to CUSTOMIZATION_GUIDE.md for detailed instructions."
    fi
    
    echo ""
    log_info "=== QUICK FIXES ==="
    log_info "To quickly update common configurations:"
    log_info "1. Update env.sh with your registry, org, and repository"
    log_info "2. Update values.yaml with your default image repository"
    log_info "3. Update applicationset.yaml with your repository URL"
    log_info "4. Update user template with your default configurations"
    
    return $total_issues
}

show_current_config() {
    log_info "=== CURRENT CONFIGURATION ==="
    echo "Container Registry: $REGISTRY"
    echo "Organization: $ORG"
    echo "Git Repository: $GIT_PLATFORM_REPO"
    echo "Platform Root: $PLATFORM_ROOT"
    echo ""
}

main() {
    log_info "Auto-Deploy Platform Configuration Tracker"
    echo ""
    
    show_current_config
    generate_customization_report
    
    echo ""
    log_info "=== NEXT STEPS ==="
    log_info "1. Review and fix any configuration issues above"
    log_info "2. Run './setup-platform.sh' to deploy the platform"
    log_info "3. Run './onboard-user.sh <username>' to create users"
    log_info "4. Run './create-project.sh <username> <project>' to create projects"
}

# Run main function
main "$@"
