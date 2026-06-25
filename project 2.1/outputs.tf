# outputs.tf - Outputs Definition

output "load_balancer_public_ip" {
  description = "The public IP address of the Load Balancer."
  value       = azurerm_public_ip.lb_pip.ip_address
}
