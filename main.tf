variable "custom_roles" {
  default     = []
  description = "A list of custom roles that will be created"
  type        = any

  # TODO: Do this when `optional()` is no longer experimental
  #  type = list(object({
  #    id          = string
  #    project     = optional(string)
  #    title       = optional(string)
  #    description = optional(string)
  #    permissions = list(string)
  #  }))
}

variable "iam_members" {
  default     = []
  description = "A list of non-authorative IAM rules"
  type        = any

  validation {
    condition = alltrue([
      for x in var.iam_members : contains(["project", "secret", "bucket"], x.type)
    ])
    error_message = "The `type` fields of `var.iam_members` must be one of ['project', 'secret', 'bucket']."
  }

  # TODO: Do this when `optional()` is no longer experimental
  # type = list(object({
  #   type    = string
  #   name    = string
  #   member  = string
  #   roles   = list(string)
  #   project = optional(string)
  # })
}

variable "iam_bindings" {
  default     = []
  description = "A list of authorative IAM rules for custom roles"
  type        = any

  validation {
    condition = alltrue([
      for x in var.iam_bindings : contains(["project", "secret", "bucket"], x.type)
    ])
    error_message = "The `type` fields of `var.iam_bindings` must be one of ['project', 'secret', 'bucket']."
  }

  validation {
    condition = alltrue([
      for x in var.iam_bindings : contains(split("/", x.role), "projects")
    ])
    error_message = "Only custom roles are allowed with IAM role bindings. This is to prevent accidents."
  }

  # TODO: Do this when `optional()` is no longer experimental
  # type = list(object({
  #   type    = string
  #   name    = string
  #   members = list(string)
  #   role    = string
  #   project = optional(string)
  # })
}

locals {
  # Convert `var.custom_roles` into a `for_each` compatible map
  custom_roles = {
    for x in var.custom_roles : x.id => x
  }

  # Convert `var.iam_members` into a `for_each` compatible map
  iam_members = {
    for x in flatten([
      for rule in var.iam_members : [
        for role in rule.roles : {
          type    = rule.type
          name    = rule.name
          member  = rule.member
          role    = role
          project = lookup(rule, "project", "")
        }
      ]
    ]) : join("-", [x.type, x.name, x.role]) => x
  }

  # Convert `var.iam_bindings` into a `for_each` compatible map
  iam_bindings = {
    for rule in var.iam_bindings : join("-", [rule.type, rule.name, rule.role]) => {
      type    = rule.type
      name    = rule.name
      members = rule.members
      role    = rule.role
      project = lookup(rule, "project", "")
    }
  }
}


#
## Custom roles
#

resource "google_project_iam_custom_role" "role" {
  for_each = local.custom_roles

  project     = lookup(each.value, "project", "")
  role_id     = each.value.id
  title       = lookup(each.value, "title", "")
  description = lookup(each.value, "description", "")
  permissions = each.value.permissions
}


#
## IAM member
#

resource "google_project_iam_member" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_members : k => v
    if v.type == "project"
  }

  project = each.value.name
  role    = each.value.role
  member  = each.value.member
}

resource "google_storage_bucket_iam_member" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_members : k => v
    if v.type == "bucket"
  }

  bucket = each.value.name
  role   = each.value.role
  member = each.value.member
}

resource "google_secret_manager_secret_iam_member" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_members : k => v
    if v.type == "secret"
  }

  project   = each.value.project
  secret_id = each.value.name
  role      = each.value.role
  member    = each.value.member
}


#
## IAM binding
#

resource "google_project_iam_binding" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_bindings : k => v
    if v.type == "project"
  }

  project = each.value.name
  role    = each.value.role
  members = each.value.members
}

resource "google_storage_bucket_iam_binding" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_bindings : k => v
    if v.type == "bucket"
  }

  bucket  = each.value.name
  role    = each.value.role
  members = each.value.members
}

resource "google_secret_manager_secret_iam_binding" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_bindings : k => v
    if v.type == "secret"
  }

  project   = each.value.project
  secret_id = each.value.name
  role      = each.value.role
  members   = each.value.members
}

