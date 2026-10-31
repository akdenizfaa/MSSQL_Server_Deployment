#Requires -Version 5.1
<#
.SYNOPSIS
    WinRM oturumunun kimlik, yetki ve ortam bilgilerini döndürür. SALT OKUMA.
.NOTES
    SupportsShouldProcess: win_powershell bu bildirim olmadan check mode'da
    script'i atlar. Script hiçbir değişiklik yapmadığı için check mode'da da çalışır.
#>
[CmdletBinding(SupportsShouldProcess)]
param ()

$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
$os = Get-CimInstance -ClassName Win32_OperatingSystem

# WinRM listener envanteri (bilgi amaçlı)
$listeners = @()
try {
    foreach ($l in Get-ChildItem -Path WSMan:\localhost\Listener) {
        $transport = ($l.Keys | Where-Object { $_ -like 'Transport=*' }) -replace '^Transport=', ''
        $port = (Get-Item -Path "WSMan:\localhost\Listener\$($l.Name)\Port").Value
        $listeners += "$transport/$port"
    }
}
catch {
    $listeners = @("unavailable: $($_.Exception.Message)")
}

$Ansible.Result = [ordered]@{
    computer_name       = $env:COMPUTERNAME
    dns_host_name       = $cs.DNSHostName
    domain              = $cs.Domain
    part_of_domain      = [bool]$cs.PartOfDomain
    fqdn                = if ($cs.PartOfDomain) { "$($cs.DNSHostName).$($cs.Domain)" } else { $cs.DNSHostName }
    user                = $identity.Name
    authentication_type = $identity.AuthenticationType
    is_admin            = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    ps_version          = $PSVersionTable.PSVersion.ToString()
    os_caption          = $os.Caption
    os_build            = [int]$os.BuildNumber
    winrm_listeners     = $listeners
    utc_now             = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}
