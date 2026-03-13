# HiHo Worker - GCP Terraform Outputs

output "vm_internal_ip" {
  description = "Internal IP address of the HiHo Worker VM"
  value       = google_compute_instance.hiho_worker.network_interface[0].network_ip
}

output "service_account_email" {
  description = "Service account email (for reference)"
  value       = google_service_account.hiho_worker.email
}

output "service_account_client_id" {
  description = "Service account OAuth2 Client ID (needed for Domain-Wide Delegation)"
  value       = google_service_account.hiho_worker.unique_id
}

output "delegation_scopes" {
  description = "OAuth scopes to configure in Domain-Wide Delegation"
  value       = <<-EOT
    https://www.googleapis.com/auth/gmail.readonly,https://www.googleapis.com/auth/calendar.readonly,https://www.googleapis.com/auth/admin.directory.user.readonly,https://www.googleapis.com/auth/admin.directory.customer.readonly
  EOT
}

output "ssh_command" {
  description = "Command to SSH into the VM via IAP"
  value       = "gcloud compute ssh hiho-worker --zone=${var.zone} --tunnel-through-iap"
}

output "next_steps" {
  description = "Instructions for completing Domain-Wide Delegation setup"
  value       = <<-EOT

    ============================================================
    IMPORTANT: Complete Domain-Wide Delegation Setup
    ============================================================

    The VM is deployed, but you must complete ONE manual step
    in the Google Admin Console to grant API access:

    1. Go to: https://admin.google.com/ac/owl/domainwidedelegation

    2. Click "Add new"

    3. Enter the following:

       Client ID: ${google_service_account.hiho_worker.unique_id}

       OAuth scopes (copy this entire line):
       https://www.googleapis.com/auth/gmail.readonly,https://www.googleapis.com/auth/calendar.readonly,https://www.googleapis.com/auth/admin.directory.user.readonly,https://www.googleapis.com/auth/admin.directory.customer.readonly

    4. Click "Authorize"

    The HiHo Worker will start processing emails and calendar
    events within a few minutes of completing this step.

    To SSH into the VM:
    gcloud compute ssh hiho-worker --zone=${var.zone} --tunnel-through-iap

    ============================================================
  EOT
}
