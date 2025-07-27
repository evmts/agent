variable "environment" {
  description = "Environment name"
  type        = string
}

variable "image_tag_mutability" {
  description = "The tag mutability setting for the repository"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Indicates whether images are scanned after being pushed to the repository"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}