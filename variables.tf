variable "location" {
  type        = string
  description = "Location of Azure resources"
  default     = "westus2"
}

variable "tags" {
  type        = any
  description = "Resource tags"
  default = {
    "po-number"          = "zzz"
    "environment"        = "prod"
    "mission"            = "administrative"
    "protection-level"   = "p1"
    "availability-level" = "a1"
  }
}

variable "aadds_sku" {
  type        = string
  description = "Azure AD DS SKU"
  default     = "Enterprise"

  validation {
    condition = can(index([
      "Standard",
      "Enterprise",
      "Premium"
    ], var.aadds_sku) >= 0)
    error_message = "Invalid sku. Can be one of the following: Standard, Enterprise, Premium."
  }
}

variable "aadds_domain_name" {
  type        = string
  description = "Domain name. This should not be conflicting with anything on-premises or Azure AD"
  default     = "aadds.contoso.fun"
}

variable "aadds_vnet_prefixes" {
  type        = list(string)
  description = "Virtual network addresses prefix list"
  default     = ["10.21.0.0/28"]
}

variable "aadds_vnet_custom_dns_servers" {
  type        = list(string)
  description = "Virtual network custom DNS server addresses - first usable IP addresses in the subnet block"
  default     = ["10.21.0.4", "10.21.0.5"]
}

variable "aadds_subnet_prefixes" {
  type        = list(string)
  description = "Subnet address prefix"
  default     = ["10.21.0.0/28"]
}

variable "vnet_hub_fw_private_ip" {
  type    = string
  default = "10.21.1.132"
}

variable "aadds_subnet_routes" {
  type = list(object({
    route_name          = string
    address_prefix      = string
    next_hop_type       = string
    next_hop_ip_address = string
  }))
  description = "List of routes to allow traffic to the AD DS"
}

variable "vnet_peerings" {
  type = list(object({
    peering_name = string
    resource_id  = string
  }))
  description = "List of virtual networks that needs to peer to hub"
}

variable "local_vm_username" {
  type = string
}

variable "local_vm_password" {
  type = string
}

variable "aadds_domain_join_username" {
  type        = string
  description = "(optional) describe your variable"
}

variable "domain_admin_username" {
  type        = string
  description = "(optional) describe your variable"
}

variable "domain_admin_password" {
  type        = string
  description = "(optional) describe your variable"
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "(optional) describe your variable"
}

variable "log_analytics_workspace_key" {
  type        = string
  description = "(optional) describe your variable"
}