#Requires -Version 5.1
<#
.SYNOPSIS
    SQL Server 2019 / 2022 / 2025 kurulum öncesi kontroller. SALT OKUMA - hedefte değişiklik yapmaz.
    Sürüme özgü gereksinimler (desteklenen OS, .NET, donanım) Ansible'dan policy olarak gelir.
.DESCRIPTION
    Politika (eşikler, sürücüler, desteklenen OS listesi) Ansible'dan JSON olarak gelir.
    Script iki şey döndürür:
      facts  : sonraki fazların kullanacağı keşif verisi (CPU, RAM, diskler, instance'lar)
      checks : her kontrol için id/name/status/expected/actual/message
    Status değerleri: PASS | WARN | FAIL | SKIPPED | INFO
.NOTES
    Her bölüm kendi try/catch'i içinde çalışır; bir probe hatası diğer kontrolleri
    durdurmaz, ilgili kontrol FAIL ("probe error") olarak raporlanır.
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string]$PolicyJson
)

$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false

$policy = $PolicyJson | ConvertFrom-Json
$checks = [System.Collections.Generic.List[object]]::new()
$facts  = [ordered]@{}

function Add-Check {
    param (
        [string]$Id, [string]$Name, [string]$Status,
        [string]$Expected = '-', [string]$Actual = '-', [string]$Message = ''
    )
    $checks.Add([ordered]@{
            id = $Id; name = $Name; status = $Status
            expected = $Expected; actual = $Actual; message = $Message
        })
}

function Invoke-Section {
    param ([string]$Id, [string]$Name, [scriptblock]$Body)
    try { & $Body }
    catch { Add-Check -Id $Id -Name $Name -Status 'FAIL' -Actual 'probe error' -Message $_.Exception.Message }
}

$os = $null
$cs = Get-CimInstance -ClassName Win32_ComputerSystem

# ---------------------------------------------------------------- OS --------
Invoke-Section 'PC-001' 'Supported operating system' {
    $script:os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$os.BuildNumber
    $facts.os = [ordered]@{
        caption           = $os.Caption
        build             = $build
        ubr               = $cv.UBR
        product_type      = [int]$os.ProductType
        installation_type = $cv.InstallationType
        architecture      = $os.OSArchitecture
    }
    $supportedBuilds = @($policy.supported_os_builds | ForEach-Object { [int]$_ })
    $supported = @($supportedBuilds | Where-Object { $_ -eq $build })
    $expected  = ($supportedBuilds | ForEach-Object { $policy.os_catalog."$_" }) -join ' / '
    if ($supported.Count -gt 0 -and $os.Caption -match 'Server') {
        Add-Check 'PC-001' 'Supported operating system' 'PASS' $expected "$($os.Caption) ($build.$($cv.UBR))"
    }
    else {
        Add-Check 'PC-001' 'Supported operating system' 'FAIL' $expected "$($os.Caption) ($build)" `
            "$($policy.product) için desteklenen işletim sistemleri: $expected."
    }

    # PC-002: ProductType 1=Workstation 2=Domain Controller 3=Server
    switch ([int]$os.ProductType) {
        3 { Add-Check 'PC-002' 'Product type' 'PASS' 'Server (3)' 'Server (3)' }
        2 {
            $st = if ($policy.allow_domain_controller) { 'WARN' } else { 'FAIL' }
            Add-Check 'PC-002' 'Product type' $st 'Server (3)' 'Domain Controller (2)' `
                'SQL Server domain controller üzerine kurulması Microsoft tarafından önerilmez.'
        }
        default { Add-Check 'PC-002' 'Product type' 'FAIL' 'Server (3)' "Workstation ($($os.ProductType))" 'İstemci işletim sistemi hedeflenmemeli.' }
    }

    # PC-003: sadece x64
    $cpuArch = @(Get-CimInstance -ClassName Win32_Processor)[0].Architecture   # 9 = x64, 12 = ARM64
    if ($os.OSArchitecture -like '64*' -and $cpuArch -eq 9) {
        Add-Check 'PC-003' 'Architecture' 'PASS' 'x64' 'x64'
    }
    else {
        Add-Check 'PC-003' 'Architecture' 'FAIL' 'x64' "$($os.OSArchitecture) / cpu=$cpuArch" "$($policy.product) sadece x64 destekler."
    }

    Add-Check 'PC-004' 'Installation type' 'INFO' '-' $cv.InstallationType
}

# ------------------------------------------------------------- .NET ---------
Invoke-Section 'PC-005' '.NET Framework' {
    $rel = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release
    $facts.dotnet_release = $rel
    if ($null -eq $policy.min_dotnet_release) {
        # Microsoft bu sürüm için ayrı bir .NET şartı belirtmiyor (OS ile gelen yeterli).
        Add-Check 'PC-005' '.NET Framework' 'INFO' 'OS-supplied' "release=$rel" `
            "$($policy.product) için ayrı .NET şartı yok; desteklenen OS'in .NET sürümü yeterli."
    }
    elseif ($rel -and [int]$rel -ge [int]$policy.min_dotnet_release) {
        Add-Check 'PC-005' '.NET Framework' 'PASS' ">= $($policy.min_dotnet_release)" $rel
    }
    else {
        Add-Check 'PC-005' '.NET Framework' 'FAIL' ">= $($policy.min_dotnet_release)" "$rel" `
            "$($policy.product) .NET Framework 4.7.2 (release 461808) veya üzerini gerektirir."
    }
}

# ------------------------------------------------------------- CPU / RAM ----
Invoke-Section 'PC-006' 'CPU clock speed' {
    $cpus = @(Get-CimInstance -ClassName Win32_Processor)
    $mhz  = [int]($cpus | Measure-Object -Property MaxClockSpeed -Minimum).Minimum
    $facts.cpu = [ordered]@{
        sockets            = $cpus.Count
        cores              = [int]($cpus | Measure-Object -Property NumberOfCores -Sum).Sum
        logical_processors = [int]($cpus | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        max_clock_mhz      = $mhz
        name               = $cpus[0].Name.Trim()
    }
    $st = if ($mhz -ge [int]$policy.min_cpu_mhz) { 'PASS' } else { 'FAIL' }
    Add-Check 'PC-006' 'CPU clock speed (MHz)' $st ">= $($policy.min_cpu_mhz)" $mhz 'Microsoft minimumu 1.4 GHz.'
    Add-Check 'PC-007' 'CPU topology' 'INFO' '-' "sockets=$($facts.cpu.sockets) cores=$($facts.cpu.cores) logical=$($facts.cpu.logical_processors)"
}

Invoke-Section 'PC-008' 'Physical memory' {
    $ramMb = [int][math]::Floor($cs.TotalPhysicalMemory / 1MB)
    $facts.memory_mb = $ramMb
    $st = if ($ramMb -ge [int]$policy.min_ram_mb) { 'PASS' } else { 'FAIL' }
    Add-Check 'PC-008' 'Physical memory (MB)' $st ">= $($policy.min_ram_mb)" $ramMb 'Microsoft minimumu (Express dışı) 1 GB.'
}

# ------------------------------------------------------------- Disks --------
$volumes = @(Get-CimInstance -ClassName Win32_Volume -Filter 'DriveLetter IS NOT NULL')
$facts.volumes = @()

function Get-DiskNumber([string]$Letter) {
    try { return [string](Get-Partition -DriveLetter $Letter -ErrorAction Stop | Select-Object -First 1).DiskNumber }
    catch { return 'n/a' }
}

# Microsoft: 6 GB boş alan SİSTEM sürücüsünde gerekli (Windows Installer geçici dosyaları),
# bileşenler başka sürücüye kurulsa bile.
Invoke-Section 'PC-009' 'System drive free space' {
    $sys = $env:SystemDrive.TrimEnd(':').ToUpper()
    $v = $volumes | Where-Object { $_.DriveLetter -eq "$($sys):" }
    $freeGb = [math]::Round($v.FreeSpace / 1GB, 1)
    $st = if ($freeGb -ge [double]$policy.min_system_drive_free_gb) { 'PASS' } else { 'FAIL' }
    Add-Check 'PC-009' "System drive $($sys): free (GB)" $st ">= $($policy.min_system_drive_free_gb)" $freeGb `
        'Microsoft minimumu: sistem sürücüsünde 6 GB (setup geçici dosyaları).'

    $bin = ([string]$policy.binaries_drive).ToUpper()
    if ($bin -ne $sys) {
        $b = $volumes | Where-Object { $_.DriveLetter -eq "$($bin):" }
        $bFree = if ($b) { [math]::Round($b.FreeSpace / 1GB, 1) } else { 'missing' }
        $st = if ($b) { 'INFO' } else { 'FAIL' }
        Add-Check 'PC-019' "Binaries drive $($bin): free (GB)" $st '-' $bFree "Binary sürücüsü $($bin): bulunamadı."
    }
}

$idx = 10
foreach ($d in $policy.required_drives) {
    $letter = ([string]$d.letter).ToUpper()
    $base = $idx
    $idx += 3
    Invoke-Section ('PC-{0:D3}' -f $base) "Drive $($letter): present" {
        $v = $volumes | Where-Object { $_.DriveLetter -eq "$($letter):" }
        if (-not $v) {
            Add-Check ('PC-{0:D3}' -f $base) "Drive $($letter): present ($($d.purpose))" 'FAIL' 'local fixed disk' 'missing' `
                "Standart gereği $($letter): sürücüsü $($d.purpose) için zorunlu."
            Add-Check ('PC-{0:D3}' -f ($base + 1)) "Drive $($letter): filesystem" 'SKIPPED' ($policy.allowed_filesystems -join '/') 'missing'
            Add-Check ('PC-{0:D3}' -f ($base + 2)) "Drive $($letter): allocation unit" 'SKIPPED' "$($policy.recommended_allocation_unit_kb) KB" 'missing'
            return
        }
        $diskNo = Get-DiskNumber $letter
        $sizeGb = [math]::Round($v.Capacity / 1GB, 1)
        $freeGb = [math]::Round($v.FreeSpace / 1GB, 1)
        $auKb   = [int]($v.BlockSize / 1KB)
        $facts.volumes += [ordered]@{
            letter = $letter; purpose = $d.purpose; drive_type = [int]$v.DriveType
            filesystem = $v.FileSystem; label = $v.Label; size_gb = $sizeGb; free_gb = $freeGb
            allocation_unit_kb = $auKb; disk_number = $diskNo
        }

        # DriveType 3 = Local Disk. 2 = Removable, 4 = Network, 5 = CD-ROM (ör. mount edilmiş ISO)
        $st = if ([int]$v.DriveType -eq 3) { 'PASS' } else { 'FAIL' }
        Add-Check ('PC-{0:D3}' -f $base) "Drive $($letter): present ($($d.purpose))" $st 'local fixed disk' `
            "type=$($v.DriveType) size=${sizeGb}GB free=${freeGb}GB disk#$diskNo" `
            "$($letter): yerel sabit disk değil (CD-ROM/ISO, ağ veya çıkarılabilir olabilir)."

        $st = if ($policy.allowed_filesystems -contains $v.FileSystem) { 'PASS' } else { 'FAIL' }
        Add-Check ('PC-{0:D3}' -f ($base + 1)) "Drive $($letter): filesystem" $st ($policy.allowed_filesystems -join '/') $v.FileSystem `
            'SQL Server veri dosyaları NTFS veya ReFS gerektirir.'

        $st = if ($auKb -eq [int]$policy.recommended_allocation_unit_kb) { 'PASS' } else { 'WARN' }
        Add-Check ('PC-{0:D3}' -f ($base + 2)) "Drive $($letter): allocation unit" $st "$($policy.recommended_allocation_unit_kb) KB" "$auKb KB" `
            'SQL Server için 64 KB allocation unit önerilir. Değiştirmek formatlama gerektirir; kurulumdan ÖNCE düzeltilmeli.'
    }
}

# ------------------------------------------------------- Pending reboot -----
Invoke-Section 'PC-030' 'Pending reboot' {
    $reasons = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons += 'CBS' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons += 'WindowsUpdate' }
    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\JoinDomain') { $reasons += 'DomainJoin' }
    $pfro = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($pfro) { $reasons += 'PendingFileRename' }
    $active  = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
    $pending = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
    if ($active -ne $pending) { $reasons += 'ComputerRename' }
    $uev = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Updates' -Name UpdateExeVolatile -ErrorAction SilentlyContinue).UpdateExeVolatile
    if ($uev -and [int]$uev -ne 0) { $reasons += 'UpdateExeVolatile' }

    $facts.pending_reboot = [ordered]@{ pending = ($reasons.Count -gt 0); reasons = $reasons }
    if ($reasons.Count -eq 0) {
        Add-Check 'PC-030' 'Pending reboot' 'PASS' 'none' 'none'
    }
    else {
        $st = if ($policy.fail_on_pending_reboot) { 'FAIL' } else { 'WARN' }
        Add-Check 'PC-030' 'Pending reboot' $st 'none' ($reasons -join ',') `
            'Bekleyen reboot var; SQL setup RebootRequiredCheck kuralında durur. Otomasyon reboot YAPMAZ, planlı reboot gerekir.'
    }
}

# ---------------------------------------------------- Windows Installer -----
Invoke-Section 'PC-031' 'Windows Installer service' {
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='msiserver'"
    $st = if ($svc -and $svc.StartMode -ne 'Disabled') { 'PASS' } else { 'FAIL' }
    Add-Check 'PC-031' 'Windows Installer service' $st 'not Disabled' "$($svc.StartMode)" 'SQL setup msiserver servisine ihtiyaç duyar.'
}

# ---------------------------------------------------- Existing instances ----
Invoke-Section 'PC-032' 'Target instance state' {
    $instances = @()
    $key = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    if (Test-Path $key) {
        $props = Get-ItemProperty -Path $key
        foreach ($p in $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) {
            $setup = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$($p.Value)\Setup" -ErrorAction SilentlyContinue
            $instances += [ordered]@{
                name = $p.Name; id = $p.Value
                version = $setup.Version; patch_level = $setup.PatchLevel; edition = $setup.Edition
            }
        }
    }
    $facts.sql_instances = $instances
    $target = $instances | Where-Object { $_.name -eq $policy.instance_name }
    if ($target) {
        $installedMajor = [int](([string]$target.version).Split('.')[0])
        if ($installedMajor -eq [int]$policy.target_major) {
            Add-Check 'PC-032' "Instance '$($policy.instance_name)' state" 'WARN' 'not installed' `
                "installed $($target.patch_level) $($target.edition)" `
                'Aynı sürüm zaten kurulu. Install fazı yeniden kurulum YAPMAYACAK; build/edition doğrulamasına geçecek.'
        }
        else {
            Add-Check 'PC-032' "Instance '$($policy.instance_name)' state" 'FAIL' "not installed (target major $($policy.target_major))" `
                "installed major $installedMajor ($($target.patch_level))" `
                'Aynı adla farklı sürüm kurulu. Instance adı çakışıyor; in-place upgrade bu otomasyonun kapsamı dışında. Farklı instance adı seçin.'
        }
    }
    else {
        Add-Check 'PC-032' "Instance '$($policy.instance_name)' state" 'PASS' 'not installed' 'not installed'
    }
    $others = @($instances | Where-Object { $_.name -ne $policy.instance_name } | ForEach-Object { "$($_.name)=$($_.patch_level)" })
    if ($others.Count -gt 0) {
        Add-Check 'PC-033' 'Other SQL instances (side-by-side)' 'INFO' '-' ($others -join ', ') `
            'Bilgi: farklı sürümler side-by-side kurulabilir; instance adları farklı olmalı.'
    }
}

# ---------------------------------------------------------- TCP port --------
Invoke-Section 'PC-034' 'TCP port availability' {
    $port = [int]$policy.tcp_port
    $listen = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
    if ($listen.Count -eq 0) {
        Add-Check 'PC-034' "TCP $port free" 'PASS' 'not listening' 'free'
    }
    else {
        $owners = ($listen | ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName } | Sort-Object -Unique) -join ','
        # Port yalnızca hedef instance AYNI major sürümle zaten kuruluysa "beklenen" sayılır
        $sameInstance = @($facts.sql_instances | Where-Object {
                $_.name -eq $policy.instance_name -and [int](([string]$_.version).Split('.')[0]) -eq [int]$policy.target_major
            }).Count -gt 0
        if ($sameInstance -and $owners -eq 'sqlservr') {
            # Port, zaten kurulu olan hedef instance'a ait (PC-032 ile tutarlı)
            Add-Check 'PC-034' "TCP $port free" 'INFO' 'not listening' "in use by sqlservr (existing target instance)"
        }
        else {
            Add-Check 'PC-034' "TCP $port free" 'WARN' 'not listening' "in use by $owners" `
                'Port başka bir süreç tarafından kullanılıyor; port çakışması kurulum sonrası servis başlatmayı engeller.'
        }
    }
}

$Ansible.Result = [ordered]@{
    facts  = $facts
    checks = $checks
}
