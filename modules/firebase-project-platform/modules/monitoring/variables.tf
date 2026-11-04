variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "project_number" {
  description = "GCP project number. Used for the Monitoring notification service agent (service-<number>@gcp-sa-monitoring-notification.iam.gserviceaccount.com). Required only when a pubsub channel is declared."
  type        = string
  default     = ""
}

# 型と validation はルートの var.monitoring (variables.tf) が持つ。ここは既定値を適用済みの値を受け取る。
variable "notification_channels" {
  description = "Notification channels keyed by name ({ type = \"email\" | \"pubsub\", display_name, labels })."
  type = map(object({
    type         = string
    display_name = optional(string)
    labels       = map(string)
  }))
  default = {}
}

variable "log_metrics" {
  description = "Log-based counter metrics keyed by metric name ({ filter, description, label_extractors, labels })."
  type = map(object({
    filter           = string
    description      = optional(string)
    label_extractors = optional(map(string), {})
    labels           = optional(map(string), {})
  }))
  default = {}
}

variable "alert_policies" {
  description = "Alert policies keyed by name. See the root variable monitoring for the shape."
  type = map(object({
    display_name            = string
    channels                = list(string)
    documentation           = optional(string)
    severity                = optional(string)
    combiner                = optional(string, "OR")
    notification_rate_limit = optional(string)
    auto_close              = optional(string)
    conditions = list(object({
      display_name = string
      log_match = optional(object({
        filter           = string
        label_extractors = optional(map(string), {})
      }))
      threshold = optional(object({
        filter               = string
        comparison           = string
        threshold_value      = number
        duration             = string
        alignment_period     = optional(string)
        per_series_aligner   = optional(string)
        cross_series_reducer = optional(string)
        group_by_fields      = optional(list(string), [])
      }))
      absent = optional(object({
        filter               = string
        duration             = string
        alignment_period     = optional(string)
        per_series_aligner   = optional(string)
        cross_series_reducer = optional(string)
        group_by_fields      = optional(list(string), [])
      }))
    }))
  }))
  default = {}
}
