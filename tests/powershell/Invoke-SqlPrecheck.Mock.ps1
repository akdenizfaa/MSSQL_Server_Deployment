<#
.SYNOPSIS
    Invoke-SqlPrecheck.ps1'i Windows olmadan, sahte CIM/registry verisiyle test eder.
.DESCRIPTION
    Mock sunucu: Windows Server 2022 (20348), 2x4 çekirdek, 32 GB RAM,
    C: 50 GB boş, D: NTFS 64K, L: NTFS 4K, T: YOK, E: ISO (CD-ROM),
    CBS reboot bekliyor, MSSQLSERVER instance'ı SQL Server 2022 (16.x) olarak kurulu,
    1433 portu sqlservr tarafından dinleniyor.

    Her sürüm için beklenen sonuçlar tabloyla karşılaştırılır; uyuşmazlıkta exit 1.
.EXAMPLE
    pwsh -File tests/powershell/Invoke-SqlPrecheck.Mock.ps1 -Script roles/sql_precheck/files/Invoke-SqlPrecheck.ps1
#>
param([Parameter(Mandatory)][string]$Script)

$ErrorActionPreference = 'Stop'

function global:Get-CimInstance { [CmdletBinding()] param([string]$ClassName, [string]$Filter)
    switch ($ClassName) {
        'Win32_OperatingSystem' { [pscustomobject]@{ Caption = 'Microsoft Windows Server 2022 Datacenter'; BuildNumber = '20348'; ProductType = 3; OSArchitecture = '64-bit' } }
        'Win32_ComputerSystem' { [pscustomobject]@{ TotalPhysicalMemory = [uint64]34359738368 } }
        'Win32_Processor' { 1..2 | ForEach-Object { [pscustomobject]@{ Architecture = 9; MaxClockSpeed = 2600; NumberOfCores = 4; NumberOfLogicalProcessors = 8; Name = ' Intel(R) Xeon(R) Gold 6338 ' } } }
        'Win32_Volume' {
            [pscustomobject]@{ DriveLetter = 'C:'; DriveType = 3; FileSystem = 'NTFS'; Label = 'OS'; Capacity = [uint64]128GB; FreeSpace = [uint64]50GB; BlockSize = 4096 }
            [pscustomobject]@{ DriveLetter = 'D:'; DriveType = 3; FileSystem = 'NTFS'; Label = 'DATA'; Capacity = [uint64]500GB; FreeSpace = [uint64]480GB; BlockSize = 65536 }
            [pscustomobject]@{ DriveLetter = 'L:'; DriveType = 3; FileSystem = 'NTFS'; Label = 'LOG'; Capacity = [uint64]200GB; FreeSpace = [uint64]199GB; BlockSize = 4096 }
            [pscustomobject]@{ DriveLetter = 'E:'; DriveType = 5; FileSystem = 'UDF'; Label = 'ISO'; Capacity = [uint64]1GB; FreeSpace = 0; BlockSize = 2048 }
        }
        'Win32_Service' { [pscustomobject]@{ Name = 'msiserver'; StartMode = 'Manual' } }
    }
}
function global:Get-ItemProperty { [CmdletBinding()] param([string]$Path, [string]$Name)
    switch -Wildcard ($Path) {
        '*Windows NT\CurrentVersion' { [pscustomobject]@{ InstallationType = 'Server Core'; UBR = 2849 } }
        '*NDP\v4\Full' { [pscustomobject]@{ Release = 528449 } }
        '*Session Manager' { [pscustomobject]@{ PendingFileRenameOperations = $null } }
        '*ActiveComputerName' { [pscustomobject]@{ ComputerName = 'SQLSRV01' } }
        '*ComputerName\ComputerName' { [pscustomobject]@{ ComputerName = 'SQLSRV01' } }
        '*Microsoft\Updates' { [pscustomobject]@{ UpdateExeVolatile = 0 } }
        '*Instance Names\SQL' { [pscustomobject]@{ MSSQLSERVER = 'MSSQL16.MSSQLSERVER'; PSPath = 'x'; PSChildName = 'SQL' } }
        '*MSSQL16.MSSQLSERVER\Setup' { [pscustomobject]@{ Version = '16.0.4135.4'; PatchLevel = '16.0.4135.4'; Edition = 'Enterprise Edition' } }
        default { $null }
    }
}
function global:Test-Path { param([string]$Path)
    return ($Path -like '*RebootPending' -or $Path -like '*Instance Names\SQL') }
function global:Get-Partition { [CmdletBinding()] param([string]$DriveLetter)
    [pscustomobject]@{ DiskNumber = @{ D = 1; L = 2 }[$DriveLetter] } }
function global:Get-NetTCPConnection { [CmdletBinding()] param([int]$LocalPort, [string]$State)
    if ($LocalPort -eq 1433) { [pscustomobject]@{ OwningProcess = 1234 } } }
function global:Get-Process { [CmdletBinding()] param([int]$Id) [pscustomobject]@{ ProcessName = 'sqlservr' } }
$env:SystemDrive = 'C:'

# playbooks/group_vars/all/sql_version_matrix.yml ile aynı değerler
$matrix = @{
    '2019' = @{ product = 'SQL Server 2019'; major = 15; dotnet = $null }
    '2022' = @{ product = 'SQL Server 2022'; major = 16; dotnet = 461808 }
    '2025' = @{ product = 'SQL Server 2025'; major = 17; dotnet = 461808 }
}

# Sürüme göre beklenen sonuçlar (diğer kontroller tüm sürümlerde aynı)
$expected = @{
    '2019' = @{ 'PC-005' = 'INFO'; 'PC-032' = 'FAIL'; 'PC-034' = 'WARN' }
    '2022' = @{ 'PC-005' = 'PASS'; 'PC-032' = 'WARN'; 'PC-034' = 'INFO' }
    '2025' = @{ 'PC-005' = 'PASS'; 'PC-032' = 'FAIL'; 'PC-034' = 'WARN' }
}
$common = @{
    'PC-001' = 'PASS'; 'PC-002' = 'PASS'; 'PC-003' = 'PASS'; 'PC-006' = 'PASS'; 'PC-008' = 'PASS'; 'PC-009' = 'PASS'
    'PC-010' = 'PASS'; 'PC-012' = 'PASS'; 'PC-015' = 'WARN'; 'PC-016' = 'FAIL'; 'PC-017' = 'SKIPPED'
    'PC-030' = 'FAIL'; 'PC-031' = 'PASS'
}

$failures = 0
foreach ($ver in '2019', '2022', '2025') {
    $global:Ansible = [pscustomobject]@{ Changed = $true; Result = $null; CheckMode = $true }
    $m = $matrix[$ver]
    $policy = @{
        sql_version = $ver; product = $m.product; target_major = $m.major
        supported_os_builds = @(17763, 20348, 26100)
        os_catalog = @{ '17763' = 'Windows Server 2019'; '20348' = 'Windows Server 2022'; '26100' = 'Windows Server 2025' }
        min_ram_mb = 1024; min_cpu_mhz = 1400; min_system_drive_free_gb = 6; min_dotnet_release = $m.dotnet
        binaries_drive = 'C'
        required_drives = @(@{ letter = 'D'; purpose = 'data + system DB root' }, @{ letter = 'L'; purpose = 'log' }, @{ letter = 'T'; purpose = 'tempdb' })
        allowed_filesystems = @('NTFS', 'ReFS'); recommended_allocation_unit_kb = 64
        instance_name = 'MSSQLSERVER'; tcp_port = 1433; fail_on_pending_reboot = $true; allow_domain_controller = $false
    } | ConvertTo-Json -Depth 5

    & $Script -PolicyJson $policy

    "===== $($m.product) (changed=$($Ansible.Changed)) ====="
    $byId = @{}
    foreach ($c in $Ansible.Result.checks) {
        $byId[$c.id] = $c.status
        '{0,-7} {1,-8} {2,-38} {3,-28} {4}' -f $c.id, $c.status, $c.name, $c.expected, $c.actual
    }
    $want = $common + $expected[$ver]
    foreach ($k in $want.Keys | Sort-Object) {
        if ($byId[$k] -ne $want[$k]) {
            "  ASSERT FAIL $ver $k : expected $($want[$k]) got $($byId[$k])"
            $failures++
        }
    }
    if ($Ansible.Changed) { "  ASSERT FAIL $ver : script reported changed=true"; $failures++ }
}

if ($failures -gt 0) { "RESULT: $failures assertion(s) failed"; exit 1 }
"RESULT: all assertions passed"
