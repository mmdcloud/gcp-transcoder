resource "google_pubsub_topic" "topic" {
  name = "transcoder-topic"

  labels = {
    foo = "bar"
  }
  
  message_retention_duration = "86600s"
}
