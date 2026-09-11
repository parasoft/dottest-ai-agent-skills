# Verify and restore the environment snapshot passed to a fix subagent.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedJson,

    # In verification-only mode do not modify the process environment. This
    # lets the caller detect drift before deciding whether to restore it.
    [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"

try {
    $expected = $ExpectedJson | ConvertFrom-Json
} catch {
    Write-Error "ERROR: The environment JSON could not be parsed: $($_.Exception.Message)"
    exit 1
}

$properties = @($expected.PSObject.Properties)
if (-not $expected -or $properties.Count -eq 0) {
    Write-Error "ERROR: The environment JSON is empty."
    exit 1
}

# The normal mode is used by fix agents to restore the supplied snapshot.
# Verification-only mode intentionally skips this block so drift remains
# observable to the caller.
if (-not $VerifyOnly) {
    foreach ($property in $properties) {
        $expectedValue = if ($null -eq $property.Value) { "" } else { [string]$property.Value }
        [Environment]::SetEnvironmentVariable($property.Name, $expectedValue, [EnvironmentVariableTarget]::Process)
    }
}

$mismatches = [System.Collections.Generic.List[string]]::new()
foreach ($property in $properties) {
    $expectedValue = if ($null -eq $property.Value) { "" } else { [string]$property.Value }
    $actualValue = [Environment]::GetEnvironmentVariable($property.Name, [EnvironmentVariableTarget]::Process)
    if ($null -eq $actualValue) { $actualValue = "" }

    if (-not [String]::Equals($actualValue, $expectedValue, [StringComparison]::Ordinal)) {
        $mismatches.Add("$($property.Name): expected '$expectedValue', actual '$actualValue'")
    }
}

if ($mismatches.Count -gt 0) {
    $message = if ($VerifyOnly) {
        "ERROR: Current environment does not match the resolved configuration."
    } else {
        "ERROR: Restored environment does not match the JSON snapshot."
    }
    Write-Error $message
    $mismatches | ForEach-Object { Write-Error $_ }
    if ($VerifyOnly) { exit 1 }
}

Write-Output "ENVIRONMENT_VERIFIED=$($properties.Count)"
exit 0
