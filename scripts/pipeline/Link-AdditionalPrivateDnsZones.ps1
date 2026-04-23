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
if ([string]::IsNullOrWhiteSpace($raw) -or $raw -eq '[]' -or $raw -eq 'null') { exit 0 }
$zones = $raw | ConvertFrom-Json
if ($zones -isnot [System.Array]) { $zones = @($zones) }
$region = $Location.ToLowerInvariant()
$map = $RegionToDnsResourcegroupMappingTable | ConvertFrom-Json
$rg = $map.$region
if ([string]::IsNullOrWhiteSpace($rg)) { throw "No DNS resource group for region '$region' in mapping table." }
$trigger = Join-Path $PSScriptRoot 'Trigger-LinkPrivateDNSZones.ps1'
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell -ErrorAction Stop).Source }
foreach ($z in $zones) {
  $name = [string]$z
  if ([string]::IsNullOrWhiteSpace($name)) { continue }
  & $pwsh -NoProfile -File $trigger `
    -PrivateDnsZoneName $name `
    -ResourceGroupName $rg `
    -SubscriptionName $SubscriptionName `
    -TenantId $TenantId `
    -WorkingDirectory $WorkingDirectory
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
