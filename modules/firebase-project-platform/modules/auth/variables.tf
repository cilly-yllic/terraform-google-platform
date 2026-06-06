variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "blocking_functions" {
  description = "Blocking functions configuration."
  type = object({
    before_create  = optional(string, "")
    before_sign_in = optional(string, "")
  })
  default = {}
}
