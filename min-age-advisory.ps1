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

    $cleanVersion = $Version.Trim()
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

function Check-NpmVersion {
    $npmCommand = Get-Command npm -ErrorAction SilentlyContinue

    if ($null -eq $npmCommand) {
        Write-Info "npm is not installed; skipping npm version check"
        return
    }

    $npmVersion = (& npm --version 2>$null).Trim()

    if ([string]::IsNullOrWhiteSpace($npmVersion)) {
        Write-Warn "npm is installed, but its version could not be detected"
        return
    }

    Write-Info "npm version: ${npmVersion}"

    if (Test-VersionLessThan $npmVersion $MinNpmMajor $MinNpmMinor $MinNpmPatch) {
        Write-Warn "npm min-release-age requires npm 11.10.0 or newer."
        Write-Warn "Update npm before relying on min-release-age."
    }
}

function Check-NpmrcMinReleaseAge {
    if (Test-Path $Npmrc -PathType Leaf) {
        $content = Get-Content $Npmrc -Raw

        if ($content -match "(?m)^\s*min-release-age\s*=") {
            Write-Info ".npmrc already contains min-release-age"
        } else {
            Write-Info "Suggestion: add this to ${Npmrc}:"
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
        Write-Info "If you ever use npm, consider adding this to ~/.npmrc:"
        Write-Info "min-release-age=3"

        if (Confirm-Apply "Create ${Npmrc} with this setting?") {
            Set-Content -Path $Npmrc -Value "min-release-age=3"
            Write-Info "Created ${Npmrc}"
        } else {
            Write-Info "Skipped .npmrc creation"
        }
    }
}

function Check-BunfigMinimumReleaseAge {
    if (-not (Test-Path $Bunfig -PathType Leaf)) {
        Write-Info "${Bunfig} does not exist."
        Write-Info "Suggestion: create it with:"
        Write-Info "[install]"
        Write-Info "minimumReleaseAge = 259200"

        if (Confirm-Apply "Create ${Bunfig} with this setting?") {
            $newContent = @"
[install]
minimumReleaseAge = 259200
"@
            Set-Content -Path $Bunfig -Value $newContent
            Write-Info "Created ${Bunfig}"
        } else {
            Write-Info "Skipped bunfig creation"
        }

        return
    }

    $content = Get-Content $Bunfig -Raw

    if ($content -match "(?m)^\s*minimumReleaseAge\s*=") {
        Write-Info "bunfig.toml already contains minimumReleaseAge"
        return
    }

    Write-Info "Suggestion: add this to ${Bunfig}:"
    Write-Info "[install]"
    Write-Info "minimumReleaseAge = 259200"

    if (-not (Confirm-Apply "Apply this change?")) {
        Write-Info "Skipped bunfig change"
        return
    }

    if ($content -match "(?m)^\s*\[install\]\s*$") {
        $updated = $content -replace "(?m)^(\s*\[install\]\s*)$", "`$1`r`nminimumReleaseAge = 259200"
        Set-Content -Path $Bunfig -Value $updated -NoNewline
    } else {
        Add-Content -Path $Bunfig -Value ""
        Add-Content -Path $Bunfig -Value "[install]"
        Add-Content -Path $Bunfig -Value "minimumReleaseAge = 259200"
    }

    Write-Info "Added Bun minimumReleaseAge to ${Bunfig}"
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
        Write-Warn "UPDATE BUN IMMEDIATELY!"
        exit 1
    }

    Check-BunfigMinimumReleaseAge
}

function Main {
    Check-Bun
    Check-NpmVersion
    Check-NpmrcMinReleaseAge

    Write-Info "Checkup complete"
}

Main