resource "google_project" "default" {
  provider = google-beta
  project_id = "rtdb-project"
  name       = "rtdb-project"
  org_id     = "123456789"
  labels     = {
    "firebase" = "enabled"
  }
}

resource "google_firebase_project" "default" {
  provider = google-beta
  project  = google_project.default.project_id
}

resource "google_project_service" "firebase_database" {
  provider = google-beta
  project  = google_firebase_project.default.project
  service  = "firebasedatabase.googleapis.com"
}

resource "google_firebase_database_instance" "default" {
  provider = google-beta
  project  = google_firebase_project.default.project
  region   = "us-central1"
  instance_id = "rtdb-project-default-rtdb"
  type     = "DEFAULT_DATABASE"
  depends_on = [google_project_service.firebase_database]
}
