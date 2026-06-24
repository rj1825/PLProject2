# Highly Available Load-Balanced Web Infrastructure on Azure

This project automates the deployment of a highly available, secure, and load-balanced web server architecture in Microsoft Azure using the Azure CLI. 

The architecture features a Public Load Balancer distributing traffic to two Windows Server 2022 backend Virtual Machines. For security, the Virtual Machines do not have public IP addresses and are only accessible through the Load Balancer.

---

## 🏗️ Architecture Design

* **Resource Group**: `rg-azure-loadbalancer`
* **Region**: `centralus` (Adjustable)
* **Availability Set**: `as-lb-project` (Prevents single point of hardware failure)
* **Virtual Network (VNet)**: `vnet-lb-project` (Address space: `10.0.0.0/16`)
* **Subnet**: `subnet-lb-project` (Address space: `10.0.1.0/24`)
* **Network Security Group (NSG)**: `nsg-lb-project` (Secures subnet, allows inbound port 80 HTTP)
* **Virtual Machines**: 2 x `Standard_D2s_v3` (Windows Server 2022 Datacenter Small Disk)
* **Azure Load Balancer**: Standard Public Load Balancer with:
  * Public Frontend IP (Dynamic Allocation)
  * TCP Port 80 Health Probe
  * Inbound HTTP Load Balancing Rule
* **Access Control (RBAC)**: Entra ID user group `ops-team-group` granted **Contributor** role access on the Resource Group level.

---

## 🛠️ How to Deploy (Activate) the Project

Follow these steps in your PowerShell terminal to deploy the infrastructure:

### 1. Prerequisites
Ensure you have the following installed on your machine:
* [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
* PowerShell 5.1+ or PowerShell Core

### 2. Login to Azure
Authenticate your Azure CLI session:
```powershell
az login
```
*If you have a multi-factor authentication (MFA) or guest tenant setup, specify the tenant explicitly:*
```powershell
az login --tenant <Your-Tenant-ID>
```

### 3. Select your Subscription
Verify and set your active subscription:
```powershell
# List subscriptions
az account list --output table

# Set active subscription
az account set --subscription "Azure subscription 1"
```

### 4. Execute the Script
Run the automated deployment script:
```powershell
.\deploy.ps1
```
* **Password Prompt**: The script will securely prompt you for a VM administrator password. Ensure it has at least 12 characters and meets Azure's complexity requirements (uppercase, lowercase, numbers, special characters).
* **Execution Time**: The script takes about 4–6 minutes to complete (most of this time is waiting for the VMs to provision and installing IIS).

### 5. Verify the Web App
Once completed, the script will output the Load Balancer Public IP (e.g., `http://<Load-Balancer-IP>`). 
* Copy the URL into your web browser.
* Refresh the page multiple times. You will see the traffic balancing between:
  * **Server 1** (Light Blue background)
  * **Server 2** (Light Pink background)

---

## 🗑️ How to Deactivate (Clean Up / Destroy) the Project

To avoid incurring any charges on your Azure account, you should clean up all resource allocations when you are finished testing. 

Since all resources are contained within a single Resource Group, deactivation is simple and can be done with a single command:

```powershell
az group delete --name rg-azure-loadbalancer --yes
```

This command will delete the Resource Group and all resources inside it (VMs, Load Balancer, Public IP, VNets, Subnets, NICs, and Security Groups).

---

## 📂 Project Repository Structure

* `deploy.ps1`: Automated PowerShell deployment script using Azure CLI.
* `README.md`: This guide on how to activate and deactivate the project.
* `interview_preparation_learning.txt`: Conceptual guide on High Availability, Load Balancers, and Interview preparation.
