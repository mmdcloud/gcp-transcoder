
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Transcoder App on GCP
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

terraform {
  # This module is now only being tested with Terraform 1.0.x. However, to make upgrading easier, we are setting
  # 0.12.26 as the minimum version, as that version added support for required_providers with source URLs, making it
  # forwards compatible with 1.0.x code.
  required_version = ">= 0.12.26"
}

# ------------------------------------------------------------------------------
# Media CDN
# ------------------------------------------------------------------------------

resource "random_id" "unique_suffix" {
  byte_length = 8
}

resource "google_storage_bucket" "default" {
  name                        = "my-bucket-${random_id.unique_suffix.hex}"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true
}

# [START mediacdn_edge_cache_origin]
resource "google_network_services_edge_cache_origin" "default" {
  name           = "cloud-storage-origin"
  origin_address = "gs://my-bucket-${random_id.unique_suffix.hex}"
}
# [END mediacdn_edge_cache_origin]

# [START mediacdn_edge_cache_service]
resource "google_network_services_edge_cache_service" "default" {
  name = "cloud-media-service"
  routing {
    host_rule {
      hosts        = ["googlecloudexample.com"]
      path_matcher = "routes"
    }
    path_matcher {
      name = "routes"
      route_rule {
        description = "a route rule to match against"
        priority    = 1
        match_rule {
          prefix_match = "/"
        }
        origin = google_network_services_edge_cache_origin.default.name
        route_action {
          cdn_policy {
            cache_mode  = "CACHE_ALL_STATIC"
            default_ttl = "3600s"
          }
        }
        header_action {
          response_header_to_add {
            header_name  = "x-cache-status"
            header_value = "{cdn_cache_status}"
          }
        }
      }
    }
  }
}

# ------------------------------------------------------------------------------
# Cloud SQL (MySQL)
# ------------------------------------------------------------------------------

resource "google_sql_database_instance" "main" {
  name             = "main-instance"
  database_version = "MYSQL_8"
  region           = "asia-south1"

  settings {
    # Second-generation instance tiers are based on the machine
    # type. See argument reference below.
    tier = "db-f1-micro"
  }
}

resource "google_sql_database" "database" {
  name     = "my-database"
  instance = google_sql_database_instance.instance.name
}

# See versions at https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database_instance#database_version
resource "google_sql_database_instance" "instance" {
  name             = "my-database-instance"
  region           = "us-central1"
  database_version = "MYSQL_8_0"
  settings {
    tier = "db-f1-micro"
  }

  deletion_protection  = "true"
}

resource "google_sql_user" "users" {
  name     = "me"
  instance = google_sql_database_instance.main.name
  host     = "me.com"
  password = "changeme"
}

# ------------------------------------------------------------------------------
# Eventarc
# ------------------------------------------------------------------------------

resource "google_eventarc_trigger" "primary" {
    name = "name"
    location = "europe-west1"
    matching_criteria {
        attribute = "type"
        value = "google.cloud.pubsub.topic.v1.messagePublished"
    }
    destination {
        cloud_run_service {
            service = google_cloud_run_service.default.name
            region = "europe-west1"
        }
    }
    labels = {
        foo = "bar"
    }
}

# ------------------------------------------------------------------------------
# Cloud Secrets Manager
# ------------------------------------------------------------------------------

resource "google_secret_manager_secret" "secret-basic" {
  secret_id = "secret"

  labels = {
    label = "my-label"
  }

  replication {
    user_managed {
      replicas {
        location = "us-central1"
      }
      replicas {
        location = "us-east1"
      }
    }
  }
}

# ------------------------------------------------------------------------------
# Cloud Run
# ------------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "default" {
  name     = "cloudrun-service"
  location = "us-central1"
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }
}

# ------------------------------------------------------------------------------
# Cloud Pub/Sub
# ------------------------------------------------------------------------------

resource "google_pubsub_topic" "example" {
  name = "example-topic"

  labels = {
    foo = "bar"
  }

  message_retention_duration = "86600s"
}

resource "google_pubsub_topic" "example" {
  name = "example-topic"
}

resource "google_pubsub_subscription" "example" {
  name  = "example-subscription"
  topic = google_pubsub_topic.example.id

  ack_deadline_seconds = 20

  labels = {
    foo = "bar"
  }

  push_config {
    push_endpoint = "https://example.com/push"

    attributes = {
      x-goog-version = "v1"
    }
  }
}

# ------------------------------------------------------------------------------
# Cloud Function
# ------------------------------------------------------------------------------

locals {
  project = "my-project-name" # Google Cloud Platform Project ID
}

resource "google_service_account" "account" {
  account_id = "gcf-sa"
  display_name = "Test Service Account"
}

resource "google_pubsub_topic" "topic" {
  name = "functions2-topic"
}

resource "google_storage_bucket" "bucket" {
  name     = "${local.project}-gcf-source"  # Every bucket name must be globally unique
  location = "US"
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "object" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.bucket.name
  source = "function-source.zip"  # Add path to the zipped function source code
}

resource "google_cloudfunctions2_function" "function" {
  name = "gcf-function"
  location = "us-central1"
  description = "a new function"

  build_config {
    runtime = "nodejs16"
    entry_point = "helloPubSub"  # Set the entry point 
    environment_variables = {
        BUILD_CONFIG_TEST = "build_test"
    }
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = google_storage_bucket_object.object.name
      }
    }
  }

  service_config {
    max_instance_count  = 3
    min_instance_count = 1
    available_memory    = "4Gi"
    timeout_seconds     = 60
    max_instance_request_concurrency = 80
    available_cpu = "4"
    environment_variables = {
        SERVICE_CONFIG_TEST = "config_test"
    }
    ingress_settings = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email = google_service_account.account.email
  }

  event_trigger {
    trigger_region = "us-central1"
    event_type = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic = google_pubsub_topic.topic.id
    retry_policy = "RETRY_POLICY_RETRY"
  }
}

# ------------------------------------------------------------------------------
# External Load Balancer
# ------------------------------------------------------------------------------

resource "google_compute_global_address" "default" {
  project      = var.project
  name         = "${var.name}-address"
  ip_version   = "IPV4"
  address_type = "EXTERNAL"
}

resource "google_compute_target_http_proxy" "http" {
  count   = var.enable_http ? 1 : 0
  project = var.project
  name    = "${var.name}-http-proxy"
  url_map = var.url_map
}

resource "google_compute_global_forwarding_rule" "http" {
  provider   = google-beta
  count      = var.enable_http ? 1 : 0
  project    = var.project
  name       = "${var.name}-http-rule"
  target     = google_compute_target_http_proxy.http[0].self_link
  ip_address = google_compute_global_address.default.address
  port_range = "80"

  depends_on = [google_compute_global_address.default]

  labels = var.custom_labels
}

resource "google_compute_global_forwarding_rule" "https" {
  provider   = google-beta
  project    = var.project
  count      = var.enable_ssl ? 1 : 0
  name       = "${var.name}-https-rule"
  target     = google_compute_target_https_proxy.default[0].self_link
  ip_address = google_compute_global_address.default.address
  port_range = "443"
  depends_on = [google_compute_global_address.default]

  labels = var.custom_labels
}

resource "google_compute_target_https_proxy" "default" {
  project = var.project
  count   = var.enable_ssl ? 1 : 0
  name    = "${var.name}-https-proxy"
  url_map = var.url_map

  ssl_certificates = var.ssl_certificates
}

resource "google_dns_record_set" "dns" {
  project = var.project
  count   = var.create_dns_entries ? length(var.custom_domain_names) : 0

  name = "${element(var.custom_domain_names, count.index)}."
  type = "A"
  ttl  = var.dns_record_ttl

  managed_zone = var.dns_managed_zone_name

  rrdatas = [google_compute_global_address.default.address]
}

