param([string]$Script)
$global:Ansible = [pscustomobject]@{ Changed = $true; Result = $null; CheckMode = $true }

function global:Get-CimInstance { [CmdletBinding()] param([string]$ClassName, [string]$Filter)
  switch ($ClassName) {
    'Win32_OperatingSystem' { [pscustomobject]@{ Caption='Microsoft Windows Server 2022 Datacenter'; BuildNumber='20348'; ProductType=3; OSArchitecture='64-bit' } }
    'Win32_ComputerSystem'  { [pscustomobject]@{ TotalPhysicalMemory=[uint64]34359738368 } }
    'Win32_Processor'       { 1..2 | % { [pscustomobject]@{ Architecture=9; MaxClockSpeed=2600; NumberOfCores=4; NumberOfLogicalProcessors=8; Name=' Intel(R) Xeon(R) Gold 6338 ' } } }
    'Win32_Volume' {
      [pscustomobject]@{ DriveLetter='C:'; DriveType=3; FileSystem='NTFS'; Label='OS';   Capacity=[uint64]128GB; FreeSpace=[uint64]50GB; BlockSize=4096 }
      [pscustomobject]@{ DriveLetter='D:'; DriveType=3; FileSystem='NTFS'; Label='DATA'; Capacity=[uint64]500GB; FreeSpace=[uint64]480GB; BlockSize=65536 }
      [pscustomobject]@{ DriveLetter='L:'; DriveType=3; FileSystem='NTFS'; Label='LOG';  Capacity=[uint64]200GB; FreeSpace=[uint64]199GB; BlockSize=4096 }
      [pscustomobject]@{ DriveLetter='E:'; DriveType=5; FileSystem='UDF';  Label='ISO';  Capacity=[uint64]1GB;   FreeSpace=0; BlockSize=2048 }
    }
    'Win32_Service' { [pscustomobject]@{ Name='msiserver'; StartMode='Manual' } }
  }
}
function global:Get-ItemProperty { [CmdletBinding()] param([string]$Path, [string]$Name)
  switch -Wildcard ($Path) {
    '*Windows NT\CurrentVersion'      { [pscustomobject]@{ InstallationType='Server Core'; UBR=2849 } }
    '*NDP\v4\Full'                    { [pscustomobject]@{ Release=533320 } }
    '*Session Manager'                { [pscustomobject]@{ PendingFileRenameOperations=$null } }
    '*ActiveComputerName'             { [pscustomobject]@{ ComputerName='SQLSRV01' } }
    '*ComputerName\ComputerName'      { [pscustomobject]@{ ComputerName='SQLSRV01' } }
    '*Microsoft\Updates'              { [pscustomobject]@{ UpdateExeVolatile=0 } }
    '*Instance Names\SQL'             { [pscustomobject]@{ MSSQLSERVER='MSSQL16.MSSQLSERVER'; PSPath='x'; PSChildName='SQL' } }
    '*MSSQL16.MSSQLSERVER\Setup'      { [pscustomobject]@{ Version='16.0.4135.4'; PatchLevel='16.0.4135.4'; Edition='Enterprise Edition' } }
    default { $null }
  }
}
function global:Test-Path { param([string]$Path)
  if ($Path -like '*RebootPending' -or $Path -like '*Instance Names\SQL') { return $true }; return $false }
function global:Get-Partition { [CmdletBinding()] param([string]$DriveLetter)
  [pscustomobject]@{ DiskNumber = @{ D=1; L=2 }[$DriveLetter] } }
function global:Get-NetTCPConnection { [CmdletBinding()] param([int]$LocalPort, [string]$State)
  if ($LocalPort -eq 1433) { [pscustomobject]@{ OwningProcess=1234 } } }
function global:Get-Process { [CmdletBinding()] param([int]$Id) [pscustomobject]@{ ProcessName='sqlservr' } }

$policy = @{
  supported_os = @(@{build=17763;name='Windows Server 2019'},@{build=20348;name='Windows Server 2022'},@{build=26100;name='Windows Server 2025'})
  min_ram_mb=1024; min_cpu_mhz=1400; min_binaries_free_gb=6; min_dotnet_release=461808
  binaries_drive='C'; required_drives=@(@{letter='D';purpose='data + system DB root'},@{letter='L';purpose='log'},@{letter='T';purpose='tempdb'})
  allowed_filesystems=@('NTFS','ReFS'); recommended_allocation_unit_kb=64; instance_name='MSSQLSERVER'; tcp_port=1433
  fail_on_pending_reboot=$true; allow_domain_controller=$false
} | ConvertTo-Json -Depth 5

& $Script -PolicyJson $policy
"Changed=$($Ansible.Changed)"
$Ansible.Result.checks | % { '{0,-7} {1,-8} {2,-40} {3,-28} {4}' -f $_.id,$_.status,$_.name,$_.expected,$_.actual }
'--- facts ---'
$Ansible.Result.facts | ConvertTo-Json -Depth 5 -Compress
