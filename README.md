# bulderbank/terraform-google-iam

This is a flexible module for handing Google Cloud IAM stuff.
It covers custom role creation, and GCP member/binding assignments for projects, secrets, and storage buckets.
It's designed to work well with our [YAML oriented configuration approach to Terraform](https://medium.com/@dfinnoy/understandable-terraform-projects-9c1cd9b4b21a).

The module can be used to:
- Create a custom roles
- Assign `members` to `roles` in a non-authoritative way
- Assign a single `member` to a custom role in an authoritative way

At first glance, the code may seem quite complicated.
But this monstrosity actually allows us to keep downstream Terraform root modules very clean and DRY.
It gives us consistent naming conventions for custom roles, and ensures that we don't accidentally break stuff with `binding` and `policy` rules.

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
  source = "github.com/bulderbank/terraform-google-iam?ref=v1.0.0"


  repo         = "bulderbank/my-project"
  project      = "my-project"
  iam_rules    = local.config.iamRules
  custom_roles = lookup(local.config, "customRoles", [])
}
```


##### Create custom IAM roles

```
# my-project/config.yaml

customRoles:
  - id: customRole1
    project: my-project                 # optional, defaults to `var.project` 
    title: Custom Role number 1         
    permissions:
      - secretmanager.versions.access
      - pubsub.topics.get
  - id: customRole2
    permissions:
      - pubsub.topics.get
```


##### Non-authoritative role assignment

We can use the GCP IAM member rules to assign some role to some user, without affecting other IAM assignments:
These non-authorative assignments are speficied with the `roles` key:

```
# my-project/config.yaml

iamRules:
  - type: project
    name: my-project
    principal: user:my-username@example.com
    roles:
      - roles/dns.admin
      - projects/my-project/roles/customRole1
  - type: secret
    name: my-secret
    principal: user:my-username@example.com
    roles:
      - roles/secretmanager.viewer
      - roles/secretmanager.secretAccessor
  - type: bucket
    name: my-bucket
    principal: user:my-username@example.com
    roles:
      - roles/storage.admin

  # Short form example, type and name defaults to `project` and `var.project` respectively
  - principal: user:my-username@example.com
    roles:
      - roles/storage.admin
```

##### Authoritative role assignment

We can use the GCP IAM binding rules to assign some role to some list of users; this will ensure that no other users are assigned to the role.
In this module, we assume that there will be a one-to-one mapping between principals and custom roles.
We do not use binding rules for non-custom roles, nor do we assign more than one principal to a custom role.
This is because careless actions involving binding rules can revoke necessary permissions, and potentially cause outages; accidents happen.


```
# my-project/config.yaml

iamRules:
  - type: project
    name: my-project
    principal: user:my-username@example.com
    permissions:
      - compute.subnetworks.get
      - compute.subnetworks.use 

  - type: secret
    name: my-secret
    principal: user:my-username@example.com   
    permissions:
      - secretmanager.secrets.getIamPolicy

  # Short form example, type and name defaults to `project` and `var.project` respectively
  - principal: user:my-username@example.com
    permissions:
      - compute.subnetworks.get
      - compute.subnetworks.use 
```

##### Non-authoritative custom role assignment

If you need a reusable custom role that will be assigned to multiple principals, do this:

```
# my-project/config.yaml

customRoles:
  - id: my.custom.role
    project: my-project         # optional, defaults to `var.project`
    title: My Super Dank Role
    permissions:
      - compute.subnetworks.get
      - compute.subnetworks.use

iamRules:
  - principal: user:my-username@example.com
    roles:
      - projects/my-project/roles/my.custom.role
  - principal: user:my-other-username@example.com
    roles:
      - projects/my-project/roles/my.custom.role
```


