#!/bin/bash
#
# HiHo Worker - GCP Deployment Script
#
# This script guides you through deploying the HiHo Worker to Google Cloud.
# Run this in Google Cloud Shell after cloning the repository.
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   HiHo Worker - Google Cloud Deployment   ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check if running in Cloud Shell or has gcloud configured
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI not found. Please run this in Google Cloud Shell.${NC}"
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo -e "${YELLOW}Installing Terraform...${NC}"
    sudo apt-get update && sudo apt-get install -y terraform
fi

echo -e "${GREEN}Please provide the following information:${NC}"
echo ""

# Project ID - list available projects for selection
echo -e "${GREEN}Available GCP Projects:${NC}"
mapfile -t PROJECTS < <(gcloud projects list --format="value(projectId)" 2>/dev/null)

if [ ${#PROJECTS[@]} -eq 0 ]; then
    echo "  No projects found. Please enter your project ID manually."
    read -p "GCP Project ID: " PROJECT_ID
else
    for i in "${!PROJECTS[@]}"; do
        echo "  $((i+1))) ${PROJECTS[$i]}"
    done
    echo ""
    echo "Enter a number to select, or type a project ID manually:"
    read -p "Project: " PROJECT_INPUT

    # Check if input is a number
    if [[ "$PROJECT_INPUT" =~ ^[0-9]+$ ]] && [ "$PROJECT_INPUT" -ge 1 ] && [ "$PROJECT_INPUT" -le ${#PROJECTS[@]} ]; then
        PROJECT_ID="${PROJECTS[$((PROJECT_INPUT-1))]}"
    else
        PROJECT_ID="$PROJECT_INPUT"
    fi
fi

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: Project ID is required${NC}"
    exit 1
fi

echo -e "${GREEN}Selected project: $PROJECT_ID${NC}"
echo ""

# Admin email
read -p "Google Workspace Admin Email (e.g., admin@company.com): " ADMIN_EMAIL

if [ -z "$ADMIN_EMAIL" ]; then
    echo -e "${RED}Error: Admin email is required${NC}"
    exit 1
fi

# API Token
echo ""
read -p "HiHo API Token: " API_TOKEN

if [ -z "$API_TOKEN" ]; then
    echo -e "${RED}Error: API token is required${NC}"
    exit 1
fi

# Region selection
echo ""
echo -e "${GREEN}Select a region:${NC}"
echo "  1) us-central1 (Iowa, USA)"
echo "  2) us-east1 (South Carolina, USA)"
echo "  3) europe-west1 (Belgium)"
echo "  4) asia-east1 (Taiwan)"
echo "  5) northamerica-northeast1 (Montreal, Canada)"
read -p "Choice [1]: " REGION_CHOICE
REGION_CHOICE=${REGION_CHOICE:-1}

case $REGION_CHOICE in
    1) REGION="us-central1" ;;
    2) REGION="us-east1" ;;
    3) REGION="europe-west1" ;;
    4) REGION="asia-east1" ;;
    5) REGION="northamerica-northeast1" ;;
    *) REGION="us-central1" ;;
esac

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}Configuration Summary:${NC}"
echo "  Project ID:   $PROJECT_ID"
echo "  Admin Email:  $ADMIN_EMAIL"
echo "  Region:       $REGION"
echo "  API Token:    ****${API_TOKEN: -4}"
echo -e "${BLUE}============================================${NC}"
echo ""

read -p "Proceed with deployment? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Setting up Terraform...${NC}"

# Export variables for Terraform
export TF_VAR_project_id="$PROJECT_ID"
export TF_VAR_admin_email="$ADMIN_EMAIL"
export TF_VAR_api_token="$API_TOKEN"
export TF_VAR_region="$REGION"
export TF_VAR_zone="${REGION}-a"

# Set gcloud project
gcloud config set project "$PROJECT_ID" 2>/dev/null

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

# Apply
echo ""
echo -e "${YELLOW}Deploying resources (this may take 2-3 minutes)...${NC}"
terraform apply -auto-approve

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Deployment Complete!                    ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: One manual step remaining!${NC}"
echo ""
echo "You must configure Domain-Wide Delegation in the Google Admin Console."
echo "Terraform has output the Client ID and scopes above."
echo ""
echo "Steps:"
echo "  1. Go to: https://admin.google.com/ac/owl/domainwidedelegation"
echo "  2. Click 'Add new'"
echo "  3. Enter the Client ID shown above"
echo "  4. Paste the OAuth scopes shown above"
echo "  5. Click 'Authorize'"
echo ""
echo "The worker will begin processing within a few minutes of completing this step."
echo ""
