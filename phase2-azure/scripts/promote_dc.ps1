# Runs inside the VM via an Azure managed run command.
# Installs AD DS, creates a new forest, then restarts the server.
param(
    [string]$DomainName,
    [string]$NetbiosName,
    [string]$SafeModePasswordB64
)
$ErrorActionPreference = 'Stop'

# Already a domain controller? (DomainRole 4 or 5) Then there is nothing to do.
$role = (Get-CimInstance Win32_ComputerSystem).DomainRole
if ($role -ge 4) {
    Write-Output "Already a domain controller for $DomainName. Skipping promotion."
    exit 0
}

Write-Output "Installing AD DS and DNS roles..."
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null

$plain = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($SafeModePasswordB64))
$dsrm  = ConvertTo-SecureString $plain -AsPlainText -Force

Write-Output "Creating forest $DomainName ($NetbiosName)..."
Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetbiosName `
    -InstallDns `
    -SafeModeAdministratorPassword $dsrm `
    -NoRebootOnCompletion `
    -Force | Out-Null

Write-Output "Forest created. Restarting in 30 seconds to finish promotion."
shutdown.exe /r /t 30 /c "Restart after domain controller promotion"
exit 0
