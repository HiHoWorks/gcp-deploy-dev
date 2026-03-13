# HiHo Worker - GCP Terraform Configuration
#
# This Terraform configuration creates:
# - Dedicated VPC with no inbound internet access
# - Cloud NAT for outbound-only internet access
# - Service account with domain-wide delegation capability
# - Compute Engine VM running the HiHo Worker container (private IP only)
# - IAP SSH access for troubleshooting
#
# After deployment, you must manually configure Domain-Wide Delegation
# in the Google Admin Console. See outputs for instructions.

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "admin.googleapis.com",
    "gmail.googleapis.com",
    "calendar-json.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# Service account for the worker
resource "google_service_account" "hiho_worker" {
  account_id   = "hiho-worker"
  display_name = "HiHo Worker Service Account"
  description  = "Service account for HiHo sentiment analysis worker with domain-wide delegation"

  depends_on = [google_project_service.apis]
}

# Create service account key (stored in VM metadata)
resource "google_service_account_key" "hiho_worker" {
  service_account_id = google_service_account.hiho_worker.name
}

# Dedicated VPC network for HiHo Worker (no default firewall rules)
resource "google_compute_network" "hiho" {
  name                    = "hiho-worker-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

# Subnet for the worker VM
resource "google_compute_subnetwork" "hiho" {
  name          = "hiho-worker-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.hiho.id

  # Enable Private Google Access for API calls without public IP
  private_ip_google_access = true
}

# Cloud Router for NAT
resource "google_compute_router" "hiho" {
  name    = "hiho-worker-router"
  region  = var.region
  network = google_compute_network.hiho.id
}

# Cloud NAT for outbound internet access (no inbound)
resource "google_compute_router_nat" "hiho" {
  name                               = "hiho-worker-nat"
  router                             = google_compute_router.hiho.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Allow outbound traffic (egress is allowed by default, but being explicit)
resource "google_compute_firewall" "hiho_egress" {
  name      = "hiho-worker-allow-egress"
  network   = google_compute_network.hiho.name
  direction = "EGRESS"

  allow {
    protocol = "all"
  }

  destination_ranges = ["0.0.0.0/0"]
}

# Deny all ingress by default (explicit deny-all rule)
resource "google_compute_firewall" "hiho_deny_ingress" {
  name      = "hiho-worker-deny-ingress"
  network   = google_compute_network.hiho.name
  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

# Allow IAP for SSH access (optional, for troubleshooting)
resource "google_compute_firewall" "hiho_iap_ssh" {
  name      = "hiho-worker-allow-iap-ssh"
  network   = google_compute_network.hiho.name
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP's IP range
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["hiho-worker"]
}

# Startup script for VM
locals {
  startup_script = <<-EOF
    #!/bin/bash
    set -e

    LOG_FILE="/var/log/hiho-install.log"
    log() {
      echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1" | tee -a "$LOG_FILE"
    }

    log "Starting HiHo Worker installation..."

    # Install Docker
    log "Installing Docker..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Create directories
    log "Creating directories..."
    mkdir -p /opt/hiho/{models,config,checkpoints,bin,credentials}

    # Write service account key from metadata (double base64 decode - GCP encodes it, then we encode for metadata)
    log "Writing service account credentials..."
    curl -s -H "Metadata-Flavor: Google" \
      "http://metadata.google.internal/computeMetadata/v1/instance/attributes/sa-key" \
      | base64 -d | base64 -d > /opt/hiho/credentials/key.json
    chmod 644 /opt/hiho/credentials/key.json
    chown 1000:1000 /opt/hiho/credentials/key.json

    # Get configuration from metadata
    API_TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
      "http://metadata.google.internal/computeMetadata/v1/instance/attributes/api-token")
    ADMIN_EMAIL=$(curl -s -H "Metadata-Flavor: Google" \
      "http://metadata.google.internal/computeMetadata/v1/instance/attributes/admin-email")
    REGISTRY_URL=$(curl -s -H "Metadata-Flavor: Google" \
      "http://metadata.google.internal/computeMetadata/v1/instance/attributes/registry-url")
    IMAGE_TAG=$(curl -s -H "Metadata-Flavor: Google" \
      "http://metadata.google.internal/computeMetadata/v1/instance/attributes/image-tag")

    # Write environment file
    log "Writing environment configuration..."
    cat > /opt/hiho/.env <<ENVEOF
API_TOKEN=$API_TOKEN
REGISTRY_URL=$REGISTRY_URL
IMAGE_TAG=$IMAGE_TAG
PROVIDER=google
GOOGLE_APPLICATION_CREDENTIALS=/credentials/key.json
GOOGLE_ADMIN_EMAIL=$ADMIN_EMAIL
PROCESS_TEAMS=false
ENVEOF
    chmod 600 /opt/hiho/.env

    # Write docker-compose.yml
    log "Writing docker-compose.yml..."
    cat > /opt/hiho/docker-compose.yml <<'COMPOSEEOF'
services:
  hiho-worker:
    image: $${REGISTRY_URL}:$${IMAGE_TAG:-latest}
    container_name: hiho-worker
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - PROVIDER=google
      - GOOGLE_APPLICATION_CREDENTIALS=/credentials/key.json
      - GOOGLE_ADMIN_EMAIL
    volumes:
      - ./models:/models
      - ./config:/opt/hiho_worker
      - ./checkpoints:/opt/hiho_worker/checkpoints
      - ./bin:/host-bin
      - ./credentials:/credentials:ro
    ports:
      - "8080:8080"
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"
    security_opt:
      - no-new-privileges:true
COMPOSEEOF

    # Set ownership
    chown -R 1000:1000 /opt/hiho/{models,config,checkpoints,bin}

    # Set up updater symlink (updater binary comes from Docker image)
    log "Setting up updater..."
    ln -sf /opt/hiho/bin/hiho-updater /usr/local/bin/hiho-updater

    # Create systemd service for updater
    log "Creating systemd services..."
    cat > /etc/systemd/system/hiho-updater.service <<'SERVICEEOF'
[Unit]
Description=HiHo Worker Updater
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=/opt/hiho
ExecStart=/usr/local/bin/hiho-updater --check-and-update
Environment="INSTALL_DIR=/opt/hiho"

[Install]
WantedBy=multi-user.target
SERVICEEOF

    cat > /etc/systemd/system/hiho-updater.timer <<'TIMEREOF'
[Unit]
Description=HiHo Worker Nightly Update Check

[Timer]
OnCalendar=*-*-* 02:00:00
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

    systemctl daemon-reload
    systemctl enable hiho-updater.timer
    systemctl start hiho-updater.timer

    # Start container
    log "Starting HiHo Worker container..."
    cd /opt/hiho
    docker compose pull
    docker compose up -d

    log "Installation complete!"
    echo "installed" > /opt/hiho/.installed
  EOF
}

# Compute Engine VM
resource "google_compute_instance" "hiho_worker" {
  name         = "hiho-worker"
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["hiho-worker"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    network    = google_compute_network.hiho.name
    subnetwork = google_compute_subnetwork.hiho.name
    # No access_config = no public IP, outbound via Cloud NAT
  }

  metadata = {
    "sa-key"       = base64encode(google_service_account_key.hiho_worker.private_key)
    "api-token"    = var.api_token
    "admin-email"  = var.admin_email
    "registry-url" = var.registry_url
    "image-tag"    = var.image_tag
  }

  metadata_startup_script = local.startup_script

  service_account {
    email  = google_service_account.hiho_worker.email
    scopes = ["cloud-platform"]
  }

  depends_on = [
    google_project_service.apis,
    google_service_account_key.hiho_worker,
    google_compute_router_nat.hiho,
  ]
}
