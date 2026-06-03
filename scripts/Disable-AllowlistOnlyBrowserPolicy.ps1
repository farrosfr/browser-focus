[CmdletBinding()]
param(
  [Alias('r')]
  [switch] $RestartBrowsers
)

$ErrorActionPreference = 'Stop'

function Assert-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
  }
}

function Remove-PolicyKey {
  param([string] $Path)

  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
}

function Restart-OpenBrowsers {
  $browserProcesses = Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(chrome|msedge|firefox)\.exe$' -and $_.ExecutablePath }
  $browserPaths = $browserProcesses | Select-Object -ExpandProperty ExecutablePath -Unique
  foreach ($proc in $browserProcesses) {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Seconds 3
  foreach ($path in $browserPaths) {
    if (Test-Path -LiteralPath $path) {
      Start-Process -FilePath $path | Out-Null
    }
  }
  return 0
}

Assert-Administrator

$chromeBase = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
$edgeBase = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$firefoxBase = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'

Remove-PolicyKey -Path (Join-Path $chromeBase 'URLBlocklist')
Remove-PolicyKey -Path (Join-Path $chromeBase 'URLAllowlist')
Remove-PolicyKey -Path (Join-Path $edgeBase 'URLBlocklist')
Remove-PolicyKey -Path (Join-Path $edgeBase 'URLAllowlist')
Remove-PolicyKey -Path (Join-Path $firefoxBase 'WebsiteFilter')

$firefoxInstalls = @(
  'C:\Program Files\Mozilla Firefox',
  'C:\Program Files\Firefox Developer Edition',
  'C:\Program Files (x86)\Mozilla Firefox'
) | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'firefox.exe') }

$removedPolicyFiles = @()
foreach ($install in $firefoxInstalls) {
  $policyPath = Join-Path $install 'distribution\policies.json'
  if (Test-Path -LiteralPath $policyPath) {
    Remove-Item -LiteralPath $policyPath -Force
    $removedPolicyFiles += $policyPath
  }
}

$restartDelay = $null
if ($RestartBrowsers) {
  $restartDelay = Restart-OpenBrowsers
}

[pscustomobject]@{
  Mode = 'AllowlistOnlyDisabled'
  RemovedChromeKeys = 'URLBlocklist, URLAllowlist'
  RemovedEdgeKeys = 'URLBlocklist, URLAllowlist'
  RemovedFirefoxWebsiteFilter = $true
  RemovedFirefoxPolicyFiles = ($removedPolicyFiles -join '; ')
  RestartDelaySeconds = $restartDelay
}
