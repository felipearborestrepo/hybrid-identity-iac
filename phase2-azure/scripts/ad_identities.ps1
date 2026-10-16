# Runs inside the DC via an Azure managed run command.
# Makes Active Directory match identities.yaml:
#   joiners -> created, movers -> updated, leavers -> disabled.
param(
    [string]$UsersB64,
    [string]$UpnSuffix,
    [string]$OuName,
    [string]$PasswordB64
)
$ErrorActionPreference = 'Stop'

# Wait until AD is up after the promotion restart.
$deadline = (Get-Date).AddMinutes(20)
while ($true) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Get-ADDomain -ErrorAction Stop | Out-Null
        break
    } catch {
        if ((Get-Date) -gt $deadline) { throw "Active Directory did not become ready in time." }
        Start-Sleep -Seconds 20
    }
}

$users    = @([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($UsersB64)) | ConvertFrom-Json)
$password = ConvertTo-SecureString ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PasswordB64))) -AsPlainText -Force
$domainDN = (Get-ADDomain).DistinguishedName
$ouDN     = "OU=$OuName,$domainDN"

# Routable UPN suffix so users can sync cleanly to Entra ID (the manual fix from the original lab).
$forest = Get-ADForest
if ($forest.UPNSuffixes -notcontains $UpnSuffix) {
    Set-ADForest -Identity $forest -UPNSuffixes @{ Add = $UpnSuffix }
    Write-Output "Added UPN suffix $UpnSuffix"
}

# OU for the lab users
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$OuName'" -SearchBase $domainDN -SearchScope OneLevel)) {
    New-ADOrganizationalUnit -Name $OuName -Path $domainDN -ProtectedFromAccidentalDeletion $false
    Write-Output "Created OU $OuName"
}

# Department groups
foreach ($g in ($users.group | Sort-Object -Unique)) {
    if (-not (Get-ADGroup -Filter "Name -eq '$g'")) {
        New-ADGroup -Name $g -GroupScope Global -GroupCategory Security -Path $ouDN
        Write-Output "Created group $g"
    }
}

# Joiners and movers
foreach ($u in $users) {
    $attrs = @{
        GivenName   = $u.first_name
        Surname     = $u.last_name
        DisplayName = "$($u.first_name) $($u.last_name)"
        Title       = $u.job_title
        Department  = $u.department
        Company     = $u.company
    }
    $upn = "$($u.username)@$UpnSuffix"
    $existing = Get-ADUser -Filter "SamAccountName -eq '$($u.username)'"

    if (-not $existing) {
        New-ADUser -Name $attrs.DisplayName -SamAccountName $u.username -UserPrincipalName $upn `
            -Path $ouDN -AccountPassword $password -ChangePasswordAtLogon $true -Enabled $true @attrs
        Write-Output "CREATED  $upn"
    } else {
        Set-ADUser -Identity $existing -UserPrincipalName $upn @attrs
        Enable-ADAccount -Identity $existing
        Write-Output "UPDATED  $upn"
    }
    Add-ADGroupMember -Identity $u.group -Members $u.username -ErrorAction SilentlyContinue
}

# Leavers: anyone in the OU who is no longer in the YAML gets disabled (not deleted).
$names = @($users.username)
Get-ADUser -Filter * -SearchBase $ouDN | Where-Object { $names -notcontains $_.SamAccountName -and $_.Enabled } | ForEach-Object {
    Disable-ADAccount -Identity $_
    Write-Output "DISABLED $($_.UserPrincipalName)"
}

Write-Output ""
Get-ADUser -Filter * -SearchBase $ouDN -Properties Title, Department, Company |
    Select-Object SamAccountName, UserPrincipalName, Title, Department, Company, Enabled |
    Format-Table -AutoSize | Out-String -Width 200
