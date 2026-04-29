# Calls Trigger-LinkPrivateDNSZones.ps1 once per zone (separate pwsh process; that script always exits).
param(
  [string]$AdditionalDnsZonesToLink = '[]',
  [Parameter(Mandatory = $true)][string]$Location,
  [Parameter(Mandatory = $true)][string]$RegionToDnsResourcegroupMappingTable,
  [Parameter(Mandatory = $true)][string]$SubscriptionName,
  [Parameter(Mandatory = $true)][string]$TenantId,
  [Parameter(Mandatory = $true)][string]$WorkingDirectory
)
$ErrorActionPreference = 'Stop'

$raw = if ([string]::IsNullOrWhiteSpace($AdditionalDnsZonesToLink)) { '' } else { $AdditionalDnsZonesToLink.Trim() }
if ([string]::IsNullOrWhiteSpace($raw) -or $raw -eq '[]' -or $raw -eq 'null') {
  exit 0
}

try {
  $parsed = $raw | ConvertFrom-Json
}
catch {
  throw "additionalDnsZonesToLink is not valid JSON: $($_.Exception.Message)"
}

if ($null -eq $parsed) {
  exit 0
}

$items = if ($parsed -is [System.Array]) { $parsed } else { @($parsed) }
if ($items.Count -eq 0) {
  exit 0
}

$region = $Location.ToLowerInvariant()
$map = $null
function Get-DnsRgFromMapping {
  if ($null -eq $script:map) {
    $script:map = $RegionToDnsResourcegroupMappingTable | ConvertFrom-Json
  }
  $rg = $script:map.$region
  if ([string]::IsNullOrWhiteSpace($rg)) {
    throw "No DNS resource group for region '$region' in mapping table (required for legacy string entries in additionalDnsZonesToLink)."
  }
  return $rg
}

function Get-ZoneLinkProperty {
  param([object]$Obj, [string[]]$Names)
  foreach ($n in $Names) {
    foreach ($p in $Obj.PSObject.Properties) {
      if ($p.Name.Equals($n, [StringComparison]::OrdinalIgnoreCase)) {
        return [string]$p.Value
      }
    }
  }
  return $null
}

$trigger = Join-Path $PSScriptRoot 'Trigger-LinkPrivateDNSZones.ps1'
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell -ErrorAction Stop).Source }

foreach ($z in $items) {
  if ($null -eq $z) { continue }

  $zoneName = $null
  $rg = $null

  if ($z -is [string]) {
    $zoneName = $z.Trim()
    if ([string]::IsNullOrWhiteSpace($zoneName)) { continue }
    $rg = Get-DnsRgFromMapping
  }
  else {
    $zn = Get-ZoneLinkProperty -Obj $z -Names @('PrivateDnsZoneName', 'PrivateDNSZoneName')
    $rgName = Get-ZoneLinkProperty -Obj $z -Names @('ResourceGroupName', 'ResourceGroup')
    $zoneName = if ([string]::IsNullOrWhiteSpace($zn)) { '' } else { $zn.Trim() }
    $rg = if ([string]::IsNullOrWhiteSpace($rgName)) { '' } else { $rgName.Trim() }
    if ([string]::IsNullOrWhiteSpace($zoneName) -or [string]::IsNullOrWhiteSpace($rg)) {
      throw "Each additionalDnsZonesToLink object must include ResourceGroupName and PrivateDnsZoneName (see additionalDnsConfig-style JSON in core.yaml)."
    }
  }

  $argList = @(
    '-NoProfile'
    '-NonInteractive'
    '-File', $trigger
    '-PrivateDnsZoneName', $zoneName
    '-ResourceGroupName', $rg
    '-SubscriptionName', $SubscriptionName
    '-TenantId', $TenantId
    '-WorkingDirectory', $WorkingDirectory
  )
  $startParams = @{
    FilePath     = $pwsh
    ArgumentList = $argList
    Wait         = $true
    PassThru     = $true
  }
  if (($null -ne $IsWindows -and $IsWindows) -or $env:OS -like '*Windows*' -or $PSVersionTable.PSEdition -eq 'Desktop') {
    $startParams['NoNewWindow'] = $true
  }
  $proc = Start-Process @startParams
  if ($proc.ExitCode -ne 0) {
    Write-Host "##vso[task.logissue type=error]Trigger-LinkPrivateDNSZones failed (exit code $($proc.ExitCode))."
    exit $proc.ExitCode
  }
}
