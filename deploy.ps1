# deploy.ps1 - Azure High-Availability Load Balancer Infrastructure Setup Script
# Run this script in PowerShell to automate the creation of all resources.

$ErrorActionPreference = "Stop"

# --- Configuration Variables (Optimized for Azure Free Tier) ---
$ResourceGroupName = "rg-azure-loadbalancer"
$Location = "centralus"
$VNetName = "vnet-lb-project"
$SubnetName = "subnet-lb-project"
$AvailabilitySetName = "as-lb-project"
$VM1Name = "vm-server-1"
$VM2Name = "vm-server-2"
$LoadBalancerName = "lb-project"
$PublicIPName = "pip-lb-project"
$OpsGroupName = "ops-team-group"
$AdminUsername = "azureadm"
$VMSize = "Standard_D2s_v3" # Unrestricted standard size (2 vCPUs, 8 GiB RAM)

# -------------------------------------------------------------
# 1. Prerequisite Checks (Azure CLI Login)
# -------------------------------------------------------------
Write-Host "Checking Azure CLI connection..." -ForegroundColor Cyan
try {
    $CurrentAccount = az account show --query "{name:name, id:id}" -o json | ConvertFrom-Json
    Write-Host "Successfully connected to Azure subscription: $($CurrentAccount.name) (ID: $($CurrentAccount.id))" -ForegroundColor Green
} catch {
    Write-Host "Error: You are not logged in to Azure CLI or don't have an active subscription." -ForegroundColor Red
    Write-Host "Please run 'az login' to authenticate, select your subscription, and run this script again." -ForegroundColor Yellow
    exit 1
}

# Prompt user for VM Password securely
Write-Host "`nPlease set an administrator password for the VMs." -ForegroundColor Yellow
Write-Host "The password must be 12-123 characters long and contain 3 of the following: uppercase, lowercase, numbers, special characters." -ForegroundColor Yellow
$PasswordValid = $false
while (-not $PasswordValid) {
    $Password = Read-Host -Prompt "Enter VM Admin Password"
    if ($Password.Length -ge 12 -and $Password.Length -le 123) {
        $PasswordValid = $true
    } else {
        Write-Host "Password does not meet the minimum length requirement (12 characters). Please try again." -ForegroundColor Red
    }
}

# -------------------------------------------------------------
# 2. Resource Group Creation
# -------------------------------------------------------------
Write-Host "`n[1/11] Creating Resource Group: $ResourceGroupName..." -ForegroundColor Cyan
az group create --name $ResourceGroupName --location $Location -o table

# -------------------------------------------------------------
# 3. Availability Set Creation
# -------------------------------------------------------------
Write-Host "`n[2/11] Creating Availability Set: $AvailabilitySetName..." -ForegroundColor Cyan
az vm availability-set create `
    --name $AvailabilitySetName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --platform-fault-domain-count 2 `
    --platform-update-domain-count 2 `
    -o table

# -------------------------------------------------------------
# 4. Virtual Network & Subnet Creation
# -------------------------------------------------------------
Write-Host "`n[3/11] Creating Virtual Network: $VNetName and Subnet: $SubnetName..." -ForegroundColor Cyan
az network vnet create `
    --name $VNetName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --address-prefixes 10.0.0.0/16 `
    --subnet-name $SubnetName `
    --subnet-prefixes 10.0.1.0/24 `
    -o table

# -------------------------------------------------------------
# 5. Network Security Group (NSG) and Rules
# -------------------------------------------------------------
Write-Host "`n[4/11] Creating Network Security Group and rules..." -ForegroundColor Cyan
$NsgName = "nsg-lb-project"
az network nsg create `
    --name $NsgName `
    --resource-group $ResourceGroupName `
    --location $Location `
    -o table

# Allow HTTP Port 80
az network nsg rule create `
    --name Allow-HTTP `
    --nsg-name $NsgName `
    --resource-group $ResourceGroupName `
    --priority 100 `
    --destination-port-ranges 80 `
    --protocol Tcp `
    --access Allow `
    --direction Inbound `
    -o table

# Associate NSG with Subnet
az network vnet subnet update `
    --name $SubnetName `
    --vnet-name $VNetName `
    --resource-group $ResourceGroupName `
    --network-security-group $NsgName `
    -o table

# -------------------------------------------------------------
# 6. Public IP & Load Balancer Provisioning
# -------------------------------------------------------------
Write-Host "`n[5/11] Provisioning Load Balancer Public IP..." -ForegroundColor Cyan
az network public-ip create `
    --name $PublicIPName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --sku Standard `
    --allocation-method Static `
    -o table

Write-Host "`n[6/11] Creating Load Balancer: $LoadBalancerName..." -ForegroundColor Cyan
az network lb create `
    --name $LoadBalancerName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --sku Standard `
    --public-ip-address $PublicIPName `
    --frontend-ip-name front-ip-config `
    --backend-pool-name backend-pool `
    -o table

# Create TCP Health Probe for Port 80
az network lb probe create `
    --name hp-port-80 `
    --lb-name $LoadBalancerName `
    --resource-group $ResourceGroupName `
    --protocol Tcp `
    --port 80 `
    --interval 15 `
    --threshold 2 `
    -o table

# Create Load Balancing Rule for HTTP (Port 80)
az network lb rule create `
    --name lb-rule-http `
    --lb-name $LoadBalancerName `
    --resource-group $ResourceGroupName `
    --protocol Tcp `
    --frontend-port 80 `
    --backend-port 80 `
    --frontend-ip-name front-ip-config `
    --backend-pool-name backend-pool `
    --probe-name hp-port-80 `
    -o table

# -------------------------------------------------------------
# 7. Network Interface Cards (NICs) for VMs (No Public IP)
# -------------------------------------------------------------
Write-Host "`n[7/11] Creating Network Interfaces for VMs (Linked to Load Balancer Pool, No Public IPs)..." -ForegroundColor Cyan
$Nic1Name = "nic-$VM1Name"
$Nic2Name = "nic-$VM2Name"

az network nic create `
    --name $Nic1Name `
    --resource-group $ResourceGroupName `
    --vnet-name $VNetName `
    --subnet $SubnetName `
    --lb-name $LoadBalancerName `
    --lb-address-pools backend-pool `
    -o table

az network nic create `
    --name $Nic2Name `
    --resource-group $ResourceGroupName `
    --vnet-name $VNetName `
    --subnet $SubnetName `
    --lb-name $LoadBalancerName `
    --lb-address-pools backend-pool `
    -o table

# -------------------------------------------------------------
# 8. VM Provisioning in Availability Set (Parallel Launch)
# -------------------------------------------------------------
Write-Host "`n[8/11] Deploying Virtual Machines (Standard_B1s) in Availability Set..." -ForegroundColor Cyan
Write-Host "Starting deployment of $VM1Name (No-Wait)..." -ForegroundColor DarkYellow
az vm create `
    --name $VM1Name `
    --resource-group $ResourceGroupName `
    --location $Location `
    --nics $Nic1Name `
    --image "MicrosoftWindowsServer:WindowsServer:2022-Datacenter-smalldisk:latest" `
    --admin-username $AdminUsername `
    --admin-password $Password `
    --availability-set $AvailabilitySetName `
    --size $VMSize `
    --no-wait

Write-Host "Starting deployment of $VM2Name (No-Wait)..." -ForegroundColor DarkYellow
az vm create `
    --name $VM2Name `
    --resource-group $ResourceGroupName `
    --location $Location `
    --nics $Nic2Name `
    --image "MicrosoftWindowsServer:WindowsServer:2022-Datacenter-smalldisk:latest" `
    --admin-username $AdminUsername `
    --admin-password $Password `
    --availability-set $AvailabilitySetName `
    --size $VMSize `
    --no-wait

Write-Host "`nWaiting for both VMs to finish provisioning (this may take 3-5 minutes)..." -ForegroundColor Cyan
az vm wait --name $VM1Name --resource-group $ResourceGroupName --created
Write-Host "$VM1Name is ready!" -ForegroundColor Green
az vm wait --name $VM2Name --resource-group $ResourceGroupName --created
Write-Host "$VM2Name is ready!" -ForegroundColor Green

# -------------------------------------------------------------
# 9. Configure IIS and HTML Pages via VM Agent
# -------------------------------------------------------------
Write-Host "`n[9/11] Configuring IIS & Custom Web Pages on VM instances..." -ForegroundColor Cyan

# PowerShell script blocks to run inside the VMs (using base64 to avoid HTML character escaping errors)
$IISScriptVM1 = 'Install-WindowsFeature -name Web-Server -IncludeManagementTools; $html = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("PGh0bWw+PGJvZHkgc3R5bGU9ImZvbnQtZmFtaWx5OiBBcmlhbCwgc2Fucy1zZXJpZjsgdGV4dC1hbGlnbjogY2VudGVyOyBtYXJnaW4tdG9wOiAxMCU7IGJhY2tncm91bmQtY29sb3I6ICNmMGY4ZmY7Ij48aDE+V2VsY29tZSB0byBTZXJ2ZXIgMTwvaDE+PHA+U2VydmVkIGZyb20gQmFja2VuZCBWTSAxIChIaWdobHkgQXZhaWxhYmxlKTwvcD48L2JvZHk+PC9odG1sPg==")); Set-Content -Path "C:\inetpub\wwwroot\iisstart.htm" -Value $html'
$IISScriptVM2 = 'Install-WindowsFeature -name Web-Server -IncludeManagementTools; $html = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("PGh0bWw+PGJvZHkgc3R5bGU9ImZvbnQtZmFtaWx5OiBBcmlhbCwgc2Fucy1zZXJpZjsgdGV4dC1hbGlnbjogY2VudGVyOyBtYXJnaW4tdG9wOiAxMCU7IGJhY2tncm91bmQtY29sb3I6ICNmZmU0ZTE7Ij48aDE+V2VsY29tZSB0byBTZXJ2ZXIgMjwvaDE+PHA+U2VydmVkIGZyb20gQmFja2VuZCBWTSAyIChIaWdobHkgQXZhaWxhYmxlKTwvcD48L2JvZHk+PC9odG1sPg==")); Set-Content -Path "C:\inetpub\wwwroot\iisstart.htm" -Value $html'

Write-Host "Installing IIS and web page on $VM1Name..." -ForegroundColor DarkYellow
az vm run-command invoke `
    --name $VM1Name `
    --resource-group $ResourceGroupName `
    --command-id RunPowerShellScript `
    --scripts $IISScriptVM1 `
    -o table

Write-Host "Installing IIS and web page on $VM2Name..." -ForegroundColor DarkYellow
az vm run-command invoke `
    --name $VM2Name `
    --resource-group $ResourceGroupName `
    --command-id RunPowerShellScript `
    --scripts $IISScriptVM2 `
    -o table

# -------------------------------------------------------------
# 10. Operations Group & RBAC Assignment
# -------------------------------------------------------------
Write-Host "`n[10/11] Setting up Operations AD Group & RBAC assignment..." -ForegroundColor Cyan
try {
    # Check if the group already exists
    $GroupExists = az ad group show --group $OpsGroupName --query id -o tsv 2>$null
    if ($GroupExists) {
        Write-Host "Entra ID Group '$OpsGroupName' already exists. ID: $GroupExists" -ForegroundColor Yellow
        $GroupId = $GroupExists
    } else {
        Write-Host "Creating Entra ID Group '$OpsGroupName'..." -ForegroundColor DarkYellow
        $GroupId = az ad group create --display-name $OpsGroupName --mail-nickname "opsteam" --query id -o tsv
        Write-Host "Created Group ID: $GroupId" -ForegroundColor Green
    }

    # Retrieve active Subscription ID
    $SubscriptionId = (az account show --query id -o tsv)
    
    # Assign Contributor role to the group, scoped to the Resource Group
    Write-Host "Assigning 'Contributor' role on resource group '$ResourceGroupName' to group '$OpsGroupName'..." -ForegroundColor DarkYellow
    az role assignment create `
        --assignee-object-id $GroupId `
        --role "Contributor" `
        --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" `
        --assignee-principal-type Group `
        -o table
    Write-Host "RBAC Role Assignment successful!" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not create Entra ID group or assign role. This is common if your user account lacks Tenant Admin permissions." -ForegroundColor Yellow
    Write-Host "You can complete this step manually in the Azure Portal if needed." -ForegroundColor Yellow
}

# -------------------------------------------------------------
# 11. Verification Details
# -------------------------------------------------------------
Write-Host "`n[11/11] Deployment Completed successfully! Retrieve Load Balancer IP..." -ForegroundColor Cyan
$LbPublicIp = az network public-ip show --name $PublicIPName --resource-group $ResourceGroupName --query ipAddress -o tsv

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "Your High-Availability Load Balancer public IP is: $LbPublicIp" -ForegroundColor Green
Write-Host "You can test the application by visiting: http://$LbPublicIp" -ForegroundColor Green
Write-Host "Note: It may take 1-2 minutes for the Load Balancer health probe to detect the instances as healthy." -ForegroundColor Yellow
Write-Host "=======================================================" -ForegroundColor Green
