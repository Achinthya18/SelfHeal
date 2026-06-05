variable "github_org" {
  type        = string
  description = "GitHub organisation or user that owns the repo (e.g. Achinthya18)."
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name (e.g. SelfHeal)."
}

variable "environment" {
  type        = string
  description = "GitHub Actions environment name allowed to assume this role (e.g. dev)."
}
