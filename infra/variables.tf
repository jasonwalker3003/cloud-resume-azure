variable "prefix" {
  description = "Short unique name used in every resource name"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,11}$", var.prefix))
    error_message = "Use 3-11 lowercase letters or digits."
  }
}

variable "swa_location" {
  description = "Static Web Apps only runs in a few regions; content is served globally anyway"
  type        = string
  default     = "eastus2"
}

variable "python_version" {
  type    = string
  default = "3.12"
}

variable "expected_text" {
  description = "Text the uptime check expects to find on the page"
  type        = string
  default     = "Jason Walker"
}

variable "alert_email" {
  description = "Where uptime alerts go"
  type        = string
  sensitive   = true
}
