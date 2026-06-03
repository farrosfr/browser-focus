[CmdletBinding()]
param(
  [Alias('r')]
  [switch] $RestartBrowsers,

  [string] $CustomAllowlistPath = (Join-Path (Get-Location) 'allowlist.local.txt')
)

$ErrorActionPreference = 'Stop'

function Assert-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
  }
}

function Set-NumberedStringList {
  param(
    [string] $Path,
    [string[]] $Values
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
      New-Item -Path $parent -Force | Out-Null
    }
    New-Item -Path $Path -Force | Out-Null
  }

  foreach ($property in (Get-Item -LiteralPath $Path).Property) {
    Remove-ItemProperty -LiteralPath $Path -Name $property -Force -ErrorAction SilentlyContinue
  }

  $index = 1
  foreach ($value in $Values) {
    New-ItemProperty -LiteralPath $Path -Name ([string] $index) -Value $value -PropertyType String -Force | Out-Null
    $index++
  }
}

function Backup-PolicyBranch {
  param(
    [string] $Path,
    [string] $Name
  )

  $backupDir = Join-Path (Get-Location) 'policy-backups'
  if (-not (Test-Path -LiteralPath $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
  }

  $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $safeName = $Name -replace '[^A-Za-z0-9_.-]', '-'
  $file = Join-Path $backupDir "$safeName-$timestamp.reg"

  if (Test-Path -LiteralPath $Path) {
    $regPath = $Path -replace '^HKLM:', 'HKLM'
    & reg.exe export $regPath $file /y | Out-Null
    return $file
  }

  return $null
}

function Write-FirefoxPolicyFile {
  param(
    [string] $FirefoxInstallDir,
    [string[]] $BlockPatterns,
    [string[]] $ExceptionPatterns
  )

  $distributionDir = Join-Path $FirefoxInstallDir 'distribution'
  if (-not (Test-Path -LiteralPath $distributionDir)) {
    New-Item -ItemType Directory -Path $distributionDir -Force | Out-Null
  }

  $policyPath = Join-Path $distributionDir 'policies.json'
  $policy = [ordered]@{
    policies = [ordered]@{
      BlockAboutConfig = $true
      DisableFirefoxAccounts = $true
      DisableFirefoxStudies = $true
      DisableTelemetry = $true
      DNSOverHTTPS = [ordered]@{
        Enabled = $false
        Locked = $true
      }
      WebsiteFilter = [ordered]@{
        Block = $BlockPatterns
        Exceptions = $ExceptionPatterns
      }
    }
  }

  [IO.File]::WriteAllText($policyPath, ($policy | ConvertTo-Json -Depth 8), [Text.Encoding]::ASCII)
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

function Convert-AllowlistEntryToFirefoxPatterns {
  param([string] $Entry)

  $value = ($Entry -replace '\s+#.*$', '').Trim()
  if (-not $value -or $value.StartsWith('#')) { return @() }

  if ($value -match '^(\*|https?|file|ftp)://') {
    return @($value)
  }

  $value = $value -replace '^https?://', ''
  $value = $value.TrimEnd('/')

  if ($value -like '*/*') {
    return @("http://$value", "https://$value")
  }

  if ($value -eq 'localhost') {
    return @(
      'http://localhost/*',
      'https://localhost/*',
      'http://localhost:*/*',
      'https://localhost:*/*'
    )
  }

  if ($value -match '^\d{1,3}(\.\d{1,3}){3}$') {
    return @("http://$value/*", "https://$value/*")
  }

  if ($value -match '^\d{1,3}(\.\d{1,3}){1,2}\.\*$') {
    return @("http://$value/*", "https://$value/*")
  }

  if ($value -match '^\d{1,3}(\.\d{1,3}){1,2}$') {
    return @("http://$value.*/*", "https://$value.*/*")
  }

  if ($value.StartsWith('*.')) {
    $root = $value.Substring(2)
    return @("*://$root/*", "*://*.$root/*")
  }

  return @("*://$value/*", "*://*.$value/*")
}

function Convert-AllowlistEntryToChromiumPatterns {
  param([string] $Entry)

  $value = ($Entry -replace '\s+#.*$', '').Trim()
  if (-not $value -or $value.StartsWith('#')) { return @() }

  if ($value -match '^(\*|https?|file|ftp)://') {
    return @($value)
  }

  $value = $value -replace '^https?://', ''
  $value = $value.TrimEnd('/')

  if ($value -like '*/*') {
    return @($value)
  }

  if ($value -eq 'localhost') {
    return @(
      'http://localhost',
      'https://localhost',
      'http://localhost:*',
      'https://localhost:*'
    )
  }

  if ($value.StartsWith('*.')) {
    $root = $value.Substring(2)
    return @($root, "*.$root")
  }

  return @($value)
}

function Read-CustomAllowlist {
  param(
    [string] $Path,
    [ValidateSet('Chromium', 'Firefox')]
    [string] $BrowserFamily
  )

  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
    return @()
  }

  if ($BrowserFamily -eq 'Chromium') {
    Get-Content -LiteralPath $Path |
      ForEach-Object { Convert-AllowlistEntryToChromiumPatterns -Entry $_ } |
      Where-Object { $_ } |
      Select-Object -Unique
  } else {
    Get-Content -LiteralPath $Path |
      ForEach-Object { Convert-AllowlistEntryToFirefoxPatterns -Entry $_ } |
      Where-Object { $_ } |
      Select-Object -Unique
  }
}

Assert-Administrator

$allowedDomains = @()

$chromiumAllowPatterns = @()
$firefoxAllowPatterns = @()
foreach ($domain in $allowedDomains) {
  $chromiumAllowPatterns += Convert-AllowlistEntryToChromiumPatterns -Entry $domain
  $firefoxAllowPatterns += Convert-AllowlistEntryToFirefoxPatterns -Entry $domain
}

$chromiumAllowPatterns += @(
  'http://10.*',
  'https://10.*',
  'http://172.*',
  'https://172.*',
  'http://192.168.*',
  'https://192.168.*',
  'http://localhost',
  'https://localhost',
  'http://localhost:*',
  'https://localhost:*',
  'http://127.0.0.1',
  'https://127.0.0.1',
  'http://127.0.0.1:*',
  'https://127.0.0.1:*',
  'chrome://policy',
  'edge://policy'
) | Select-Object -Unique

$firefoxAllowPatterns += @(
  'http://10.*/*',
  'https://10.*/*',
  'http://172.*/*',
  'https://172.*/*',
  'http://192.168.*/*',
  'https://192.168.*/*',
  'http://localhost/*',
  'https://localhost/*',
  'http://localhost:*/*',
  'https://localhost:*/*',
  'http://127.0.0.1/*',
  'https://127.0.0.1/*',
  'http://127.0.0.1:*/*',
  'https://127.0.0.1:*/*',
  'chrome://policy/*',
  'edge://policy/*',
  'about:policies'
) | Select-Object -Unique

$customChromiumAllowPatterns = @(Read-CustomAllowlist -Path $CustomAllowlistPath -BrowserFamily Chromium)
$customFirefoxAllowPatterns = @(Read-CustomAllowlist -Path $CustomAllowlistPath -BrowserFamily Firefox)
$chromiumAllowPatterns = @($chromiumAllowPatterns + $customChromiumAllowPatterns) | Select-Object -Unique
$firefoxAllowPatterns = @($firefoxAllowPatterns + $customFirefoxAllowPatterns) | Select-Object -Unique

$chromeEdgeBlockAll = @('*')
$firefoxBlockAll = @('<all_urls>')

$chromeBase = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
$edgeBase = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$firefoxBase = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'

$backups = @(
  Backup-PolicyBranch -Path $chromeBase -Name 'Chrome'
  Backup-PolicyBranch -Path $edgeBase -Name 'Edge'
  Backup-PolicyBranch -Path $firefoxBase -Name 'Firefox'
) | Where-Object { $_ }

Set-NumberedStringList -Path (Join-Path $chromeBase 'URLBlocklist') -Values $chromeEdgeBlockAll
Set-NumberedStringList -Path (Join-Path $chromeBase 'URLAllowlist') -Values $chromiumAllowPatterns

Set-NumberedStringList -Path (Join-Path $edgeBase 'URLBlocklist') -Values $chromeEdgeBlockAll
Set-NumberedStringList -Path (Join-Path $edgeBase 'URLAllowlist') -Values $chromiumAllowPatterns

New-Item -Path $firefoxBase -Force | Out-Null
New-ItemProperty -Path $firefoxBase -Name 'DisableFirefoxAccounts' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $firefoxBase -Name 'DisableFirefoxStudies' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $firefoxBase -Name 'DisableTelemetry' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $firefoxBase -Name 'BlockAboutConfig' -Value 1 -PropertyType DWord -Force | Out-Null

$firefoxDohPath = Join-Path $firefoxBase 'DNSOverHTTPS'
New-Item -Path $firefoxDohPath -Force | Out-Null
New-ItemProperty -Path $firefoxDohPath -Name 'Enabled' -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $firefoxDohPath -Name 'Locked' -Value 1 -PropertyType DWord -Force | Out-Null

$firefoxFilterPath = Join-Path $firefoxBase 'WebsiteFilter'
Set-NumberedStringList -Path (Join-Path $firefoxFilterPath 'Block') -Values $firefoxBlockAll
Set-NumberedStringList -Path (Join-Path $firefoxFilterPath 'Exceptions') -Values $firefoxAllowPatterns

$firefoxInstalls = @(
  'C:\Program Files\Mozilla Firefox',
  'C:\Program Files\Firefox Developer Edition',
  'C:\Program Files (x86)\Mozilla Firefox'
) | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'firefox.exe') }

foreach ($install in $firefoxInstalls) {
  Write-FirefoxPolicyFile -FirefoxInstallDir $install -BlockPatterns $firefoxBlockAll -ExceptionPatterns $firefoxAllowPatterns
}

$restartDelay = $null
if ($RestartBrowsers) {
  $restartDelay = Restart-OpenBrowsers
}

[pscustomobject]@{
  Mode = 'AllowlistOnly'
  ChromeBlocklist = Join-Path $chromeBase 'URLBlocklist'
  ChromeAllowlist = Join-Path $chromeBase 'URLAllowlist'
  EdgeBlocklist = Join-Path $edgeBase 'URLBlocklist'
  EdgeAllowlist = Join-Path $edgeBase 'URLAllowlist'
  FirefoxWebsiteFilter = $firefoxFilterPath
  ChromiumAllowedPatternCount = $chromiumAllowPatterns.Count
  FirefoxAllowedPatternCount = $firefoxAllowPatterns.Count
  CustomAllowlistPath = $CustomAllowlistPath
  CustomChromiumAllowedPatternCount = $customChromiumAllowPatterns.Count
  CustomFirefoxAllowedPatternCount = $customFirefoxAllowPatterns.Count
  Backups = ($backups -join '; ')
  RestartDelaySeconds = $restartDelay
}
