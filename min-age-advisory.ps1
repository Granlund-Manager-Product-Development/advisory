#!/usr/bin/env pwsh

$ErrorActionPreference = "Stop"

$MinBunMajor = 1
$MinBunMinor = 3
$MinBunPatch = 0

$MinNpmMajor = 11
$MinNpmMinor = 10
$MinNpmPatch = 0

$Npmrc = Join-Path $HOME ".npmrc"
$Bunfig = Join-Path $HOME ".bunfig.toml"

$BunMinimumReleaseAgeExcludes = @(
    "@gm/event-hub",
    "@gm/styles",
    "@gm/ui-components",
    "@gm/gm-api-clients-base",
    "@gm/gm-asset-hierachy-api-client",
    "@gm/gm-businessrelations-api-client",
    "@gm/gm-cloud-components",
    "@gm/gm-cloud-e2e-test-base",
    "@gm/gm-cloud-events",
    "@gm/gm-cloud-tenant",
    "@gm/gm-cloud-tenant-tanstack",
    "@gm/gm-cloud-tenant-wouter",
    "@gm/gm-cloud-theme",
    "@gm/gm-coding-conventions",
    "@gm/gm-component-library",
    "@gm/gm-energy-api-client",
    "@gm/gm-kendo-intl",
    "@gm/gm-notifications-api-client",
    "@gm/gm-tasks-api-client",
    "@gm/gm-usermanagement-api-client",
    "@gm/gm-utils"
)

function Write-Info {
    param([string]$Message)
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Warning $Message
}

function Test-IsInteractive {
    if ([Console]::IsInputRedirected) {
        return $false
    }

    if ($Host.Name -eq "ServerRemoteHost") {
        return $false
    }

    return $true
}

function Confirm-Apply {
    param([string]$Prompt)

    if (-not (Test-IsInteractive)) {
        Write-Info "$Prompt [y/N] n"
        Write-Info "Non-interactive mode detected; skipping change"
        return $false
    }

    $answer = Read-Host "$Prompt [y/N]"

    switch ($answer) {
        "y" { return $true }
        "Y" { return $true }
        "yes" { return $true }
        "YES" { return $true }
        "Yes" { return $true }
        default { return $false }
    }
}

function Get-VersionParts {
    param([string]$Version)

    $cleanVersion = $Version.Trim() -replace "^[vV]", ""
    $parts = $cleanVersion.Split(".")

    $major = 0
    $minor = 0
    $patch = 0

    if ($parts.Count -ge 1) {
        $rawMajor = $parts[0] -replace "[^0-9].*$", ""
        [void][int]::TryParse($rawMajor, [ref]$major)
    }

    if ($parts.Count -ge 2) {
        $rawMinor = $parts[1] -replace "[^0-9].*$", ""
        [void][int]::TryParse($rawMinor, [ref]$minor)
    }

    if ($parts.Count -ge 3) {
        $rawPatch = $parts[2] -replace "[^0-9].*$", ""
        [void][int]::TryParse($rawPatch, [ref]$patch)
    }

    return @{
        Major = $major
        Minor = $minor
        Patch = $patch
    }
}

function Test-VersionLessThan {
    param(
        [string]$Version,
        [int]$MinMajor,
        [int]$MinMinor,
        [int]$MinPatch
    )

    $parts = Get-VersionParts $Version

    if ($parts.Major -lt $MinMajor) {
        return $true
    }

    if ($parts.Major -gt $MinMajor) {
        return $false
    }

    if ($parts.Minor -lt $MinMinor) {
        return $true
    }

    if ($parts.Minor -gt $MinMinor) {
        return $false
    }

    if ($parts.Patch -lt $MinPatch) {
        return $true
    }

    return $false
}

function Format-TomlString {
    param([string]$Value)

    return '"' + ($Value -replace "\\", "\\" -replace '"', '\"') + '"'
}

function Format-TomlStringArray {
    param([string[]]$Values)

    $escaped = $Values | ForEach-Object {
        Format-TomlString $_
    }

    return "[" + ($escaped -join ", ") + "]"
}

function Test-BunfigInstallKey {
    param(
        [string]$Content,
        [string]$Key
    )

    $inInstall = $false
    $escapedKey = [regex]::Escape($Key)

    foreach ($line in ($Content -split "`r?`n")) {
        if ($line -match "^\s*\[.*\]\s*$") {
            $inInstall = $line -match "^\s*\[install\]\s*$"
            continue
        }

        if ($inInstall -and $line -match "^\s*${escapedKey}\s*=") {
            return $true
        }
    }

    return $false
}

function Check-NpmVersion {
    $npmCommand = Get-Command npm -ErrorAction SilentlyContinue

    if ($null -eq $npmCommand) {
        Write-Info "npm is not installed; skipping npm version check"
        return $true
    }

    $npmVersion = (& npm --version 2>$null).Trim()

    if ([string]::IsNullOrWhiteSpace($npmVersion)) {
        Write-Warn "npm is installed, but its version could not be detected"
        return $true
    }

    Write-Info "npm version: ${npmVersion}"

    if (Test-VersionLessThan $npmVersion $MinNpmMajor $MinNpmMinor $MinNpmPatch) {
        Write-Warn "npm min-release-age requires npm ${MinNpmMajor}.${MinNpmMinor}.${MinNpmPatch} or newer."
        Write-Warn "Update npm before relying on min-release-age."
        return $false
    }

    return $true
}

function Check-NpmrcMinReleaseAge {
    param([bool]$NpmMinReleaseAgeSupported)

    if (Test-Path $Npmrc -PathType Leaf) {
        $content = Get-Content $Npmrc -Raw

        if ($content -match "(?m)^\s*min-release-age\s*=") {
            Write-Info ".npmrc already contains min-release-age"
        } else {
            if ($NpmMinReleaseAgeSupported) {
                Write-Info "Suggestion: add this to ${Npmrc}:"
            } else {
                Write-Info "You can add this to ${Npmrc} now, but update npm before relying on it:"
            }

            Write-Info "min-release-age=3"

            if (Confirm-Apply "Apply this change?") {
                Add-Content -Path $Npmrc -Value ""
                Add-Content -Path $Npmrc -Value "min-release-age=3"
                Write-Info "Added min-release-age=3 to ${Npmrc}"
            } else {
                Write-Info "Skipped .npmrc change"
            }
        }
    } else {
        Write-Info "${Npmrc} does not exist."

        if ($NpmMinReleaseAgeSupported) {
            Write-Info "If you ever use npm, consider adding this to ~/.npmrc:"
        } else {
            Write-Info "You can create ~/.npmrc now, but update npm before relying on it:"
        }

        Write-Info "min-release-age=3"

        if (Confirm-Apply "Create ${Npmrc} with this setting?") {
            Set-Content -Path $Npmrc -Value "min-release-age=3"
            Write-Info "Created ${Npmrc}"
        } else {
            Write-Info "Skipped .npmrc creation"
        }
    }
}

function Get-BunfigInstallLinesToAdd {
    param([string]$Content)

    $linesToAdd = @()

    if (-not (Test-BunfigInstallKey $Content "minimumReleaseAge")) {
        $linesToAdd += "minimumReleaseAge = 259200"
    }

    if (-not (Test-BunfigInstallKey $Content "minimumReleaseAgeExcludes")) {
        $excludes = Format-TomlStringArray $BunMinimumReleaseAgeExcludes
        $linesToAdd += "minimumReleaseAgeExcludes = ${excludes}"
    }

    return $linesToAdd
}

function Update-BunfigInstallSection {
    param(
        [string]$Content,
        [string[]]$LinesToAdd
    )

    if ($LinesToAdd.Count -eq 0) {
        return $Content
    }

    $insert = $LinesToAdd -join [Environment]::NewLine

    if ($Content -match "(?m)^\s*\[install\]\s*$") {
        return $Content -replace "(?m)^(\s*\[install\]\s*)$", "`$1$([Environment]::NewLine)$insert"
    }

    $prefix = $Content

    if (-not $prefix.EndsWith([Environment]::NewLine)) {
        $prefix += [Environment]::NewLine
    }

    return $prefix + [Environment]::NewLine + "[install]" + [Environment]::NewLine + $insert + [Environment]::NewLine
}

function Check-BunfigMinimumReleaseAge {
    $excludeLine = "minimumReleaseAgeExcludes = $(Format-TomlStringArray $BunMinimumReleaseAgeExcludes)"

    if (-not (Test-Path $Bunfig -PathType Leaf)) {
        Write-Info "${Bunfig} does not exist."
        Write-Info "Suggestion: create it with:"
        Write-Info "[install]"
        Write-Info "minimumReleaseAge = 259200"
        Write-Info $excludeLine

        if (Confirm-Apply "Create ${Bunfig} with this setting?") {
            $newContent = @"
[install]
minimumReleaseAge = 259200
$excludeLine
"@
            Set-Content -Path $Bunfig -Value $newContent
            Write-Info "Created ${Bunfig}"
        } else {
            Write-Info "Skipped bunfig creation"
        }

        return
    }

    $content = Get-Content $Bunfig -Raw
    $linesToAdd = Get-BunfigInstallLinesToAdd $content

    if ($linesToAdd.Count -eq 0) {
        Write-Info "bunfig.toml already contains minimumReleaseAge and minimumReleaseAgeExcludes under [install]"
        return
    }

    Write-Info "Suggestion: ensure ${Bunfig} contains this under [install]:"

    foreach ($line in $linesToAdd) {
        Write-Info $line
    }

    if (-not (Confirm-Apply "Apply this change?")) {
        Write-Info "Skipped bunfig change"
        return
    }

    $updated = Update-BunfigInstallSection $content $linesToAdd
    Set-Content -Path $Bunfig -Value $updated -NoNewline

    Write-Info "Updated Bun minimumReleaseAge settings in ${Bunfig}"
}

function Check-Bun {
    $bunCommand = Get-Command bun -ErrorAction SilentlyContinue

    if ($null -eq $bunCommand) {
        Write-Info "Bun is not installed; skipping Bun checks"
        return
    }

    $bunVersion = (& bun --version 2>$null).Trim()

    if ([string]::IsNullOrWhiteSpace($bunVersion)) {
        Write-Warn "Bun is installed, but its version could not be detected"
        return
    }

    Write-Info "Bun version: ${bunVersion}"

    if (Test-VersionLessThan $bunVersion $MinBunMajor $MinBunMinor $MinBunPatch) {
        Write-Warn "Bun minimumReleaseAge requires Bun ${MinBunMajor}.${MinBunMinor}.${MinBunPatch} or newer."
        Write-Warn "Update Bun immediately."
        exit 1
    }

    Check-BunfigMinimumReleaseAge
}

function Main {
    if ([string]::IsNullOrWhiteSpace($HOME)) {
        Write-Warn "HOME is not set; cannot check user npm/Bun config files"
        exit 1
    }

    Check-Bun

    $npmMinReleaseAgeSupported = Check-NpmVersion
    Check-NpmrcMinReleaseAge $npmMinReleaseAgeSupported

    Write-Info "Checkup complete"
}

Main