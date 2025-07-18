#!/usr/bin/env powershell
<#
.SYNOPSIS
    Test Windows build environment for Zed development
.DESCRIPTION
    This script verifies that all required dependencies for building Zed on Windows are properly installed.
    It mimics the environment checks performed by the GitHub Actions workflow.
.PARAMETER Fix
    Attempt to fix issues where possible (install missing components)
.PARAMETER Verbose
    Show detailed information about each check
.EXAMPLE
    .\test-windows-environment.ps1
    Basic environment check
.EXAMPLE
    .\test-windows-environment.ps1 -Verbose -Fix
    Detailed check with automatic fixes
#>

[CmdletBinding()]
param(
    [switch]$Fix,
    [switch]$ShowDetails
)

$ErrorActionPreference = 'Continue'
$script:issuesFound = @()
$script:checks = @{
    'passed' = 0
    'failed' = 0
    'warnings' = 0
}

function Write-Check {
    param(
        [string]$Message,
        [string]$Status = "INFO",
        [string]$Details = ""
    )
    
    $color = switch ($Status.ToUpper()) {
        "PASS" { "Green"; $script:checks.passed++ }
        "FAIL" { "Red"; $script:checks.failed++; $script:issuesFound += $Message }
        "WARN" { "Yellow"; $script:checks.warnings++ }
        default { "White" }
    }
    
    $prefix = switch ($Status.ToUpper()) {
        "PASS" { "[PASS]" }
        "FAIL" { "[FAIL]" }
        "WARN" { "[WARN]" }
        default { "[INFO]" }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $color
    if ($Details -and ($ShowDetails -or $Status -eq "FAIL")) {
        Write-Host "   $Details" -ForegroundColor Gray
    }
}

function Test-Command {
    param([string]$Command)
    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-RegistryPath {
    param([string]$Path)
    try {
        $null = Get-Item $Path -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-GitLongPaths {
    try {
        $gitConfig = git config --global core.longpaths
        return $gitConfig -eq "true"
    } catch {
        return $false
    }
}

function Test-WindowsLongPaths {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
        $regValue = Get-ItemProperty -Path $regPath -Name "LongPathsEnabled" -ErrorAction SilentlyContinue
        return $regValue.LongPathsEnabled -eq 1
    } catch {
        return $false
    }
}

function Get-VisualStudioInfo {
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    
    if (!(Test-Path $vsWhere)) {
        return $null
    }
    
    try {
        $installations = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json | ConvertFrom-Json
        return $installations
    } catch {
        return $null
    }
}

function Get-WindowsSDKVersions {
    $sdkPath = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (!(Test-Path $sdkPath)) {
        return @()
    }
    
    $versions = Get-ChildItem $sdkPath -Directory | Where-Object { $_.Name -like "10.0.*" } | Sort-Object Name -Descending
    return $versions.Name
}

function Find-CMake {
    $cmakePaths = @(
        "${env:ProgramFiles}\CMake\bin\cmake.exe",
        "${env:ProgramFiles(x86)}\CMake\bin\cmake.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
    )
    
    foreach ($path in $cmakePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    # Check if cmake is in PATH
    if (Test-Command "cmake") {
        return (Get-Command cmake).Source
    }
    
    return $null
}

# Main environment checks
Write-Host "[CHECK] Zed Windows Build Environment Checker" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Check 1: Rust toolchain
Write-Host "[RUST] Checking Rust Environment..." -ForegroundColor Yellow

if (Test-Command "rustup") {
    Write-Check "Rustup is installed" -Status "PASS"
    
    try {
        $rustcVersion = rustc --version
        Write-Check "Rust compiler: $rustcVersion" -Status "PASS"
        
        $cargoVersion = cargo --version
        Write-Check "Cargo: $cargoVersion" -Status "PASS"
    } catch {
        Write-Check "Rust toolchain not properly configured" -Status "FAIL" -Details "Run: rustup show"
    }
} else {
    Write-Check "Rustup not found" -Status "FAIL" -Details "Install from: https://rustup.rs/"
    if ($Fix) {
        Write-Host "   Downloading rustup installer..."
        try {
            Invoke-WebRequest -Uri "https://win.rustup.rs/x86_64" -OutFile "rustup-init.exe"
            Write-Host "   Run 'rustup-init.exe' to install Rust"
        } catch {
            Write-Check "Failed to download rustup installer" -Status "FAIL"
        }
    }
}

# Check 2: Git configuration
Write-Host "`n[GIT] Checking Git Configuration..." -ForegroundColor Yellow

if (Test-Command "git") {
    Write-Check "Git is installed" -Status "PASS"
    
    if (Test-GitLongPaths) {
        Write-Check "Git long paths enabled" -Status "PASS"
    } else {
        Write-Check "Git long paths not enabled" -Status "WARN" -Details "Run: git config --global core.longpaths true"
        if ($Fix) {
            try {
                git config --global core.longpaths true
                Write-Check "Enabled Git long paths" -Status "PASS"
            } catch {
                Write-Check "Failed to enable Git long paths" -Status "FAIL"
            }
        }
    }
} else {
    Write-Check "Git not found" -Status "FAIL" -Details "Install Git for Windows"
}

# Check 3: Windows long paths
Write-Host "`n[LONGPATH] Checking Windows Long Path Support..." -ForegroundColor Yellow

if (Test-WindowsLongPaths) {
    Write-Check "Windows long paths enabled" -Status "PASS"
} else {
    Write-Check "Windows long paths not enabled" -Status "WARN" -Details "May require admin rights to enable"
    if ($Fix) {
        try {
            New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
            Write-Check "Enabled Windows long paths" -Status "PASS"
        } catch {
            Write-Check "Failed to enable Windows long paths (requires admin)" -Status "WARN"
        }
    }
}

# Check 4: Visual Studio / Build Tools
Write-Host "`n[VSTOOLS] Checking Visual Studio / Build Tools..." -ForegroundColor Yellow

$vsInfo = Get-VisualStudioInfo
if ($vsInfo -and $vsInfo.Count -gt 0) {
    foreach ($installation in $vsInfo) {
        $displayName = $installation.displayName
        $version = $installation.installationVersion
        Write-Check "Found: $displayName (v$version)" -Status "PASS"
    }
} else {
    Write-Check "Visual Studio with C++ tools not found" -Status "FAIL" -Details "Install Visual Studio 2019/2022 with C++ workload"
}

# Check 5: Windows SDK
Write-Host "`n[SDK] Checking Windows SDK..." -ForegroundColor Yellow

$sdkVersions = Get-WindowsSDKVersions
if ($sdkVersions.Count -gt 0) {
    $latestSdk = $sdkVersions[0]
    Write-Check "Windows SDK found: $latestSdk" -Status "PASS"
    
    # Check if version meets minimum requirement (10.0.20348.0)
    if ($latestSdk -ge "10.0.20348") {
        Write-Check "SDK version meets minimum requirement (10.0.20348.0)" -Status "PASS"
    } else {
        Write-Check "SDK version below minimum requirement" -Status "WARN" -Details "Consider updating to 10.0.20348.0 or newer"
    }
} else {
    Write-Check "Windows SDK not found" -Status "FAIL" -Details "Install Windows 10/11 SDK"
}

# Check 6: CMake
Write-Host "`n[CMAKE] Checking CMake..." -ForegroundColor Yellow

$cmakePath = Find-CMake
if ($cmakePath) {
    Write-Check "CMake found: $cmakePath" -Status "PASS"
    
    try {
        $cmakeVersion = cmake --version | Select-Object -First 1
        Write-Check "CMake version: $cmakeVersion" -Status "PASS"
    } catch {
        Write-Check "CMake not working properly" -Status "FAIL"
    }
} else {
    Write-Check "CMake not found" -Status "FAIL" -Details "Install CMake or Visual Studio with CMake tools"
}

# Check 7: Optional tools
Write-Host "`n[OPTIONAL] Checking Optional Tools..." -ForegroundColor Yellow

$optionalTools = @{
    "docker" = "Docker for backend services"
    "node" = "Node.js for some tests"
    "code" = "VS Code for development"
}

foreach ($tool in $optionalTools.GetEnumerator()) {
    if (Test-Command $tool.Key) {
        Write-Check "$($tool.Value) available" -Status "PASS"
    } else {
        Write-Check "$($tool.Value) not found" -Status "WARN" -Details "Optional but recommended"
    }
}

# Check 8: Zed workspace
Write-Host "`n[WORKSPACE] Checking Zed Workspace..." -ForegroundColor Yellow

if (Test-Path "Cargo.toml") {
    Write-Check "Found Cargo.toml in current directory" -Status "PASS"
    
    if (Test-Path "rust-toolchain.toml") {
        Write-Check "Found rust-toolchain.toml" -Status "PASS"
    } else {
        Write-Check "rust-toolchain.toml not found" -Status "WARN"
    }
    
    if (Test-Path "crates\zed") {
        Write-Check "Found Zed source directory" -Status "PASS"
    } else {
        Write-Check "Zed source directory not found" -Status "FAIL" -Details "Are you in the Zed repository root?"
    }
} else {
    Write-Check "Not in a Rust workspace" -Status "FAIL" -Details "Navigate to the Zed repository root"
}

# Summary
Write-Host "`n[SUMMARY] Environment Check Summary" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan
Write-Host "[PASS] Passed: $($script:checks.passed)" -ForegroundColor Green
Write-Host "[WARN] Warnings: $($script:checks.warnings)" -ForegroundColor Yellow  
Write-Host "[FAIL] Failed: $($script:checks.failed)" -ForegroundColor Red

if ($script:checks.failed -eq 0 -and $script:checks.warnings -eq 0) {
    Write-Host "`n[SUCCESS] Your environment is ready for Zed development!" -ForegroundColor Green
    Write-Host "You can now run: cargo build" -ForegroundColor Green
} elseif ($script:checks.failed -eq 0) {
    Write-Host "`n[OK] Your environment should work for Zed development." -ForegroundColor Yellow
    Write-Host "Some optional components are missing, but core functionality should work." -ForegroundColor Yellow
} else {
    Write-Host "`n[ERROR] Environment setup incomplete. Please address the following issues:" -ForegroundColor Red
    foreach ($issue in $script:issuesFound) {
        Write-Host "   • $issue" -ForegroundColor Red
    }
    Write-Host "`nSee: docs/src/development/windows.md for detailed setup instructions" -ForegroundColor Yellow
}

Write-Host "`n[COMMANDS] Useful Commands:" -ForegroundColor Cyan
Write-Host "   cargo build              # Build debug version"
Write-Host "   cargo build --release    # Build release version"
Write-Host "   cargo test --workspace   # Run tests"
Write-Host "   cargo clippy             # Run linter"
Write-Host ""
