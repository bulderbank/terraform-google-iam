# bulderbank/terraform-google-iam

This is a flexible module for handing Google Cloud IAM stuff.
It covers custom role creation, and GCP member/binding assignments for projects, secrets, and storage buckets.
It's designed to work well with our YAML oriented configuration approach to Terraform.

The module can be used to:
- Create a custom roles
- Assign `members` to `roles` in a non-authoritative way
- Assign `members` to `roles` in an authoritative way (we only allow this for custom roles)


### Usage
All the examples below assume that you are using a `config.yaml` file to pass configuration values to Terraform via `locals`:

```
# my-project/locals.tf

locals {
  config = yamldecode(file("${path.root}/config.yaml"))
}
```
```
# my-project/modules.tf

module "iam" {
  source = "github.com/bulderbank/terraform-google-iam?ref=vX.Y.Z"

  custom_roles  = lookup(local.config, "customRoles", [])
  iam_members   = lookup(local.config, "iamMembers", [])
  iam_bindings  = lookup(local.config, "iamBindings", [])
}
```


##### Create custom IAM roles

```
# my-project/config.yaml

customRoles:
  - id: customRole1
    project: my-project                 # optional, defaults to provider config 
    title: Custom Role number 1         # optional 
    description: This is a custom role  # optional
    permissions:
      - secretmanager.versions.access
      - pubsub.topics.get
  - id: customRole2
    permissions:
      - pubsub.topics.get
```


##### Non-authoritative role assignment

We can use the GCP IAM Member to assign some role to some user, without affecting other IAM assignments:

```
# my-project/config.yaml

iamMembers:
  - type: project
    name: my-project
    member: user:my-username@example.com
    roles:
      - roles/dns.admin
      - projects/my-project/roles/customRole1
  - type: secret
    name: my-secret
    member: user:my-username@example.com
    roles:
      - roles/secretmanager.viewer
      - roles/secretmanager.secretAccessor
  - type: bucket
    name: my-bucket
    member: user:my-username@example.com
    roles:
      - roles/storage.admin
```

##### Authoritative role assignment

We can use the GCP IAM Binding to assign some role to some list of users; this will ensure that no other users are assigned to the role.
We only allow this for custom roles through this module because accidents can potentially cause outages, or lock developers out of our GCP projects.
Use with caution.

```
# my-project/config.yaml

iamBindings:
  - type: project
    name: my-project
    role: projects/my-project/roles/customRole1
    members:
      - user:my-username@example.com
      - group:g_my-group@example.com
  - type: secret
    name: my-secret
    role: projects/bulder-test/roles/customRole2
    members:
      - user:my-username@example.com
      - group:g_my-group@example.com
```

#### The `project` parameter
The `custom_roles`, `iam_members`, and `iam_bindings` variables all allow an optional `project` field within the objects in their input lists.
When it is not defined, Terraform and the Google Provider will default to the GCP project defined within the root module's provider block.

For custom roles, and IAM assignenments for GCP secrets, you may want to work toward a different project:

```
customRoles:
  - id: customRole2
    project: my-other-project
    permissions:
      - pubsub.topics.get

iamMembers:
  - type: secret
    name: my-secret
    project: my-other-project
    member: user:my-username@example.com
    roles:
      - roles/secretmanager.viewer
      - roles/secretmanager.secretAccessor
```
