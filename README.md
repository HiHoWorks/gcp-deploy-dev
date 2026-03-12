# HiHo Worker - Google Cloud Deployment

This Terraform configuration deploys the HiHo sentiment analysis worker to Google Cloud Platform.

## Prerequisites

- A Google Cloud project with billing enabled
- Google Workspace admin access (for Domain-Wide Delegation setup)
- Your HiHo API token

## Quick Start (Cloud Shell)

1. Click this button to open in Cloud Shell:

   [![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/HiHoWorks/gcp-deploy&cloudshell_tutorial=README.md)

2. Run the deployment script:

   ```bash
   ./deploy.sh
   ```

3. Follow the prompts to enter:
   - GCP Project ID
   - Google Workspace admin email
   - HiHo API token
   - Region selection

4. Complete the Domain-Wide Delegation setup (instructions shown after deployment)

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | GCP Project ID | (required) |
| `admin_email` | Workspace admin email | (required) |
| `api_token` | HiHo API token | (required) |
| `region` | GCP region | us-central1 |
| `zone` | GCP zone | us-central1-a |
| `machine_type` | VM machine type | e2-medium |

## What Gets Created

- **Service Account**: `hiho-worker@{project}.iam.gserviceaccount.com`
  - Used for Domain-Wide Delegation to access Gmail and Calendar
- **Compute Engine VM**: `hiho-worker`
  - Runs the HiHo Worker Docker container
  - e2-medium (2 vCPU, 4GB RAM) by default
- **Firewall Rule**: Allows health check access on port 8080

## Domain-Wide Delegation

After Terraform completes, you must configure Domain-Wide Delegation in the Google Admin Console. This grants the service account permission to read emails and calendar events for users in your organization.

The Terraform output will show:
- The Client ID to enter
- The OAuth scopes to authorize

This step cannot be automated and must be done by a Google Workspace admin.

## Estimated Costs

- Compute Engine e2-medium: ~$25/month
- Network egress: Minimal (data stays in GCP)
- Total: ~$25-30/month

## Troubleshooting

**Check VM logs:**
```bash
gcloud compute ssh hiho-worker --zone=us-central1-a --command="sudo docker logs hiho-worker"
```

**Check installation log:**
```bash
gcloud compute ssh hiho-worker --zone=us-central1-a --command="cat /var/log/hiho-install.log"
```

**Health check:**
```bash
curl http://$(terraform output -raw vm_external_ip):8080/health
```

## Cleanup

To remove all resources:

```bash
# If you get Cloud Resource Manager API errors, enable it first:
gcloud services enable cloudresourcemanager.googleapis.com --project=YOUR_PROJECT_ID

# Then destroy
terraform destroy
```

Note: You should also remove the Domain-Wide Delegation entry from the Admin Console.
