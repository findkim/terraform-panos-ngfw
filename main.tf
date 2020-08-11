terraform {
  required_providers {
    panos = {
      source  = "terraform-providers/panos"
      version = "~>1.6"
    }
  }
}

resource "panos_administrative_tag" "tag" {
  name    = var.tag_name
  comment = "Tag generated by Consul NIA used for dynamic address group filtering"
  color   = "color38"
  # vsys    = ""
}

resource "panos_application_object" "consul" {
  # https://docs.paloaltonetworks.com/pan-os/8-1/pan-os-web-interface-help/objects/objects-applications/applications-overview

  name        = "consul-services"
  category    = "business-systems"
  subcategory = "general-business"
  technology  = "client-server"
}

resource "panos_address_object" "addrObj" {
  for_each = local.flattented_services

  name        = "consul_service_${each.value.name}"
  value       = each.value.address.address
  description = each.value.description
  tags        = local.address_tags
}

resource "panos_address_group" "addresses" {
  name          = "Consul NIA services"
  description   = "Dynamic address group generated by Consul NIA"
  dynamic_match = panos_administrative_tag.tag.name
  tags          = local.address_group_tags
}

resource "panos_security_rule_group" "rules" {
  # Note `panos_security_policy` destroys  existing, non-managed rules. We use
  # `panos_security_rule_group` instead to leave existing rules untouched.

  position_keyword   = var.position_keyword
  position_reference = var.position_reference

  # https://docs.paloaltonetworks.com/pan-os/9-0/pan-os-admin/policy/security-policy/components-of-a-security-policy-rule.html
  rule {
    name        = var.security_policy_rule_name
    action      = "allow"
    description = var.security_policy_rule_description
    tags        = [panos_administrative_tag.tag.name]

    applications          = [panos_application_object.consul.name]
    source_zones          = ["any"]
    source_addresses      = [panos_address_group.addresses.name]
    source_users          = ["any"]
    hip_profiles          = ["any"]
    destination_zones     = ["any"]
    destination_addresses = ["any"]
    services              = ["application-default"]
    categories            = ["any"]

    # Optional security profiles
    group             = var.profile_group
    virus             = var.profile_virus
    spyware           = var.profile_spyware
    vulnerability     = var.profile_vulnerability
    url_filtering     = var.profile_url_filtering
    file_blocking     = var.profile_file_blocking
    wildfire_analysis = var.profile_wildfire_analysis
    data_filtering    = var.profile_data_filtering
  }
}

locals {
  # Concatenated list of tags to add to address objects
  address_tags       = concat(var.consul_service_tags, [var.tag_name])
  address_group_tags = concat(var.address_group_tags, [var.tag_name])

  # List of services to each of its known IP addresses
  flattented_services = {
    for s in flatten([
      for name, service in var.services : [
        for i in range(length(service.addresses)) : {
          name        = "${service.name}.${i}"
          description = service.description
          address     = service.addresses[i]
        }
      ]
    ]) : s.name => s
  }
}
