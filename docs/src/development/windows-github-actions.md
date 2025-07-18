# Windows GitHub Actions Workflow Guide

This document explains the GitHub Actions workflow for building and testing Zed on Windows, based on the Windows development documentation.

## Overview

The `windows-build.yml` workflow automates the entire Windows build process, from environment setup to creating installers. It's designed to:

1. **Automatically detect** when Windows-specific changes are made
2. **Set up** the complete Windows build environment 
3. **Build** Zed in both debug and release modes
4. **Run tests** and code quality checks
5. **Create installers** for releases

## Workflow Structure

### Jobs

1. **`detect_changes`** - Determines if the workflow should run based on file changes
2. **`setup-windows-environment`** - Validates and sets up the Windows build environment
3. **`build`** - Compiles Zed for Windows
4. **`test`** - Runs tests and code quality checks (Clippy)
5. **`check-dependencies`** - Verifies dependencies and licenses
6. **`setup-backend`** - (Optional) Sets up PostgreSQL and LiveKit for collaborative features
7. **`bundle-windows`** - Creates Windows installer packages
8. **`windows-build-summary`** - Provides a summary of all job results

### Triggers

The workflow runs automatically on:

- **Push to main** or version branches (`v[0-9]+.[0-9]+.x`)
- **Push tags** starting with `v` (e.g., `v1.0.0`)
- **Pull requests** that modify relevant files:
  - Rust source files (`*.rs`)
  - Configuration files (`*.toml`)
  - Source directories (`crates/`, `assets/`, `script/`)
  - Build configuration (`.cargo/`, `.github/`)

Manual triggers:
- **`workflow_dispatch`** - Manual trigger with option to create installer bundle

### Smart Change Detection

The workflow includes intelligent change detection to avoid unnecessary runs:

```yaml
# Only runs if these file patterns change:
- '**.rs'           # Rust source files
- '**.toml'         # Cargo and config files  
- 'crates/**'       # Source code directories
- 'assets/**'       # Asset files
- 'script/**'       # Build scripts
- '.cargo/**'       # Cargo configuration
- '.github/**'      # GitHub Actions files
```

## Environment Setup

### Dependencies Checked

The workflow automatically verifies:

1. **Rust toolchain** (installed via rustup)
2. **Visual Studio Build Tools** with required components:
   - MSVC C++ build tools (x64/x86)
   - MSVC Spectre-mitigated libraries
   - Windows SDK (minimum version 10.0.20348.0)
3. **CMake** (from Visual Studio or standalone installation)

### Required Visual Studio Components

For Visual Studio installations:
```json
{
  "components": [
    "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
    "Microsoft.VisualStudio.Component.Windows11SDK.26100", 
    "Microsoft.VisualStudio.Component.VC.Runtimes.x86.x64.Spectre",
    "Microsoft.VisualStudio.Component.VC.CMake.Project"
  ]
}
```

For Build Tools only:
```json
{
  "components": [
    "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
    "Microsoft.VisualStudio.Component.Windows11SDK.26100",
    "Microsoft.VisualStudio.Component.VC.Runtimes.x86.x64.Spectre",
    "Microsoft.VisualStudio.Component.VC.CMake.Project",
    "Microsoft.VisualStudio.Workload.VCTools"
  ]
}
```

## Build Process

### 1. Environment Configuration

The workflow:
- Enables long path support for Git and Windows
- Installs Rust toolchain from `rust-toolchain.toml`
- Locates and configures CMake
- Sets up CI-specific Cargo configuration

### 2. Compilation

- **Debug build**: `cargo build --workspace`
- **Release build**: `cargo build --release --package zed`
- Uses CI configuration with `-D warnings` for strict compilation

### 3. Testing

- Installs `cargo-nextest` for faster test execution
- Runs `cargo clippy` for code quality checks
- Executes `cargo nextest run --workspace --no-fail-fast`
- Checks for unused dependencies with `cargo-machete`

### 4. Installer Creation (Release/Manual)

For tagged releases or manual triggers:
- Determines release channel (stable, preview, nightly, dev)
- Builds installer using `script/bundle-windows.ps1`
- Creates signed executables (if signing certificates are configured)
- Uploads installer artifacts or attaches to GitHub releases

## Configuration

### Repository Secrets (for signed releases)

To enable code signing for production releases, set these repository secrets:

```
AZURE_SIGNING_TENANT_ID
AZURE_SIGNING_CLIENT_ID  
AZURE_SIGNING_CLIENT_SECRET
```

### Repository Variables

```
AZURE_SIGNING_ACCOUNT_NAME
AZURE_SIGNING_CERT_PROFILE_NAME
AZURE_SIGNING_ENDPOINT
```

### Customization

To modify the workflow:

1. **Change triggers**: Edit the `on:` section
2. **Modify build steps**: Update the `build` job
3. **Add dependencies**: Extend the `setup-windows-environment` job
4. **Customize testing**: Modify the `test` job

## Troubleshooting

### Common Issues

1. **"No Visual Studio found"**
   - Ensure Visual Studio 2019/2022 or Build Tools are installed
   - Verify required components are installed
   - Check that `vswhere.exe` is available

2. **"CMake not found"**
   - Install CMake standalone or via Visual Studio
   - Ensure CMake is in PATH or located in expected directories

3. **"Path too long"**
   - The workflow enables long path support automatically
   - For local development, run as administrator:
     ```powershell
     New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
     ```

4. **"RUSTFLAGS override"**
   - The workflow uses proper Cargo configuration
   - Avoid setting `RUSTFLAGS` environment variable globally

5. **Build failures with signing**
   - Signing is optional for development builds
   - Production signing requires proper Azure certificates setup

### Debug Steps

1. Check the "Environment Verification" step output
2. Review Cargo build logs for specific errors
3. Ensure all dependencies are properly installed
4. Verify Rust toolchain version matches `rust-toolchain.toml`

## Manual Usage

You can trigger the workflow manually:

1. Go to **Actions** tab in the repository
2. Select **"Windows Build & Test"** workflow  
3. Click **"Run workflow"**
4. Optionally enable **"Create Windows installer bundle"**

## Integration with Existing CI

This workflow complements the existing `ci.yml` workflow:

- **`ci.yml`**: Cross-platform CI including Windows tests
- **`windows-build.yml`**: Windows-specific comprehensive build and installer creation

Both can run independently or together, with smart change detection preventing unnecessary runs.

## Performance Optimizations

The workflow includes several optimizations:

1. **Cargo caching** - Caches dependencies between runs
2. **Change detection** - Skips runs for irrelevant changes  
3. **Parallel jobs** - Independent jobs run concurrently
4. **Conditional steps** - Installer creation only for releases
5. **Smart artifact retention** - 7-day retention for development builds

## Local Development

To replicate the workflow locally:

```powershell
# 1. Setup environment (see docs/src/development/windows.md)
# 2. Configure CI settings
New-Item -ItemType Directory -Path "..\\.cargo" -Force
Copy-Item -Path ".\\.cargo\\ci-config.toml" -Destination "..\\.cargo\\config.toml"

# 3. Build and test
cargo build --workspace
cargo test --workspace

# 4. Clean up
Remove-Item -Recurse -Path "..\\.cargo" -Force
```

This ensures your local development environment matches the CI environment.
