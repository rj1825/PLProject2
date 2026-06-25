# variables.tf - Input Variables Definition

variable "resource_group_name" {
  description = "The name of the resource group in which to create the resources."
  type        = string
  default     = "rg-azure-lb-terraform"
}

variable "location" {
  description = "The Azure Region in which all resources should be created."
  type        = string
  default     = "centralus" # Region verified to have standardDSv3Family cores capacity
}

variable "vm_size" {
  description = "The size of the Virtual Machines to deploy."
  type        = string
  default     = "Standard_D2s_v3" # Size verified to have quota and capacity
}

variable "admin_username" {
  description = "The username of the local administrator for the Virtual Machines."
  type        = string
  default     = "azureadm"
}

variable "admin_password" {
  description = "The password for the local administrator of the Virtual Machines. Must satisfy password complexity requirements."
  type        = string
  sensitive   = true
}
