variable "project" {
  description = "Google Cloud project"
  type        = string
}

variable "custom_roles" {
  default     = []
  description = "A list of custom roles that will be created"
  type        = any

  # TODO: Do this when `optional()` is no longer experimental
  #  type = list(object({
  #    id          = string
  #    project     = optional(string)
  #    title       = string
  #    permissions = list(string)
  #  }))
}

variable "iam_rules" {
  default     = []
  description = "List of rules for IAM membership / bindings"
  type        = any

  # TODO: Do this when `optional()` is no longer experimental
  # type = list(object({
  #   principal   = string
  #   project     = optional(string)  defaults to `var.project`
  #   type        = optional(string)  defaults to "project"
  #   name        = optional(string)  defaults to `var.project`
  #   roles       = optional(list(string))
  #   permissions = optional(list(string))
  # }))
}

variable "repo" {
  description = "Name of GitHub repo that calls this module; helps us see where IAM custom roles are defined as code"
}

locals {
  # Elaborate hacks to ensure each custom role gets a unique name
  principal_short_names = distinct([
    for x in [for rule in var.iam_rules : rule.principal] : regex(":(.+)@", x)[0]
  ])

  custom_roles_from_rules = flatten([
    for principal_short_name in local.principal_short_names : [
      for index, rule in [
        for x in var.iam_rules : x
        if alltrue([principal_short_name == regex(":(.+)@", x.principal)[0], contains(keys(x), "permissions")])
        ] : {
        project     = lookup(rule, "project", var.project)
        id          = replace("${principal_short_name}_${index}", "-", "_")
        title       = "Custom role bound to ${principal_short_name} for ${lookup(rule, "name", var.project)} (${lookup(rule, "type", "project")})"
        description = "Created by Terraform via ${var.repo}"
        permissions = rule.permissions
      }
    ]
  ])

  all_custom_roles = concat(
    local.custom_roles_from_rules,
    [for rule in var.custom_roles : merge(rule, { description = "Created by Terraform via ${var.repo}" })]
  )

  iam_bindings = {
    for y in flatten([
      for principal_short_name in local.principal_short_names : [
        for index, rule in [
          for x in var.iam_rules : x
          if alltrue([principal_short_name == regex(":(.+)@", x.principal)[0], contains(keys(x), "permissions")])
          ] : {
          principal = [rule.principal]
          project   = lookup(rule, "project", var.project)
          type      = lookup(rule, "type", "project")
          name      = lookup(rule, "name", var.project)
          role      = "projects/${lookup(rule, "project", var.project)}/roles/${replace("${principal_short_name}_${index}", "-", "_")}"
        }
      ]
    ]) : join("-", [y.type, y.name, y.role]) => y
  }

  iam_members = {
    for x in flatten([
      for rule in var.iam_rules : [
        for role in rule.roles : {
          principal = rule.principal
          project   = lookup(rule, "project", var.project)
          type      = lookup(rule, "type", "project")
          name      = lookup(rule, "name", var.project)
          role      = role
        }
      ]
      if contains(keys(rule), "roles")
    ]) : join("-", [x.type, x.name, x.principal, x.role]) => x
  }
}


#
## Custom roles
#

resource "google_project_iam_custom_role" "role" {
  for_each = { for x in local.all_custom_roles : x.id => x }

  project     = lookup(each.value, "project", var.project)
  role_id     = each.value.id
  title       = each.value.title
  description = each.value.description
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
  member  = each.value.principal
}

resource "google_storage_bucket_iam_member" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_members : k => v
    if v.type == "bucket"
  }

  bucket = each.value.name
  role   = each.value.role
  member = each.value.principal
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
  member    = each.value.principal
}

resource "google_bigquery_dataset_iam_member" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_members : k => v
    if v.type == "bigquery-dataset"
  }

  dataset_id = each.value.name
  role       = each.value.role
  member     = each.value.principal
}

resource "google_bigquery_table_iam_member" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_members : k => v
    if v.type == "bigquery-table"
  }

  table_id   = each.value.name
  dataset_id = each.value.dataset
  role       = each.value.role
  member     = each.value.principal
}

resource "google_service_account_iam_member" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_members : k => v
    if v.type == "service-account"
  }

  service_account_id = each.value.name
  role               = each.value.role
  member             = each.value.principal
}

resource "google_pubsub_subscription_iam_member" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_members : k => v
    if v.type == "pubsub"
  }

  subscription = each.value.name
  role         = each.value.role
  member       = each.value.principal
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
  members = each.value.principal
}

resource "google_storage_bucket_iam_binding" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_bindings : k => v
    if v.type == "bucket"
  }

  bucket  = each.value.name
  role    = each.value.role
  members = each.value.principal
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
  members   = each.value.principal
}

resource "google_pubsub_subscription_iam_binding" "assignment" {
  depends_on = [google_project_iam_custom_role.role]
  for_each = {
    for k, v in local.iam_bindings : k => v
    if v.type == "pubsub"
  }

  project      = each.value.project
  subscription = each.value.name
  role         = each.value.role
  members      = each.value.principal
}

