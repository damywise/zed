# Windows Build Workflow Configuration Examples

This directory contains example configurations and customizations for the Windows build workflow.

## Basic Configuration

The default workflow runs on:
- Push to main/version branches
- Pull requests with relevant changes
- Manual dispatch

## Customization Examples

### 1. Run on Different Branches

```yaml
on:
  push:
    branches:
      - main
      - develop
      - "feature/*"
      - "v[0-9]+.[0-9]+.x"
```

### 2. Custom Change Detection

```yaml
# Add more file patterns to trigger builds
paths:
  - '**.rs'
  - '**.toml'
  - '**.md'           # Documentation changes
  - 'docs/**'         # Documentation directory
  - 'assets/**'
  - 'extensions/**'   # Extension changes
```

### 3. Production Release Configuration

For production use, add these repository secrets:

```bash
# GitHub Secrets (Settings → Secrets and variables → Actions → New repository secret)
AZURE_SIGNING_TENANT_ID          # Azure AD tenant ID for code signing
AZURE_SIGNING_CLIENT_ID          # Azure service principal client ID  
AZURE_SIGNING_CLIENT_SECRET      # Azure service principal secret
```

And these repository variables:

```bash
# GitHub Variables (Settings → Secrets and variables → Actions → Variables tab)
AZURE_SIGNING_ACCOUNT_NAME       # Azure signing account name
AZURE_SIGNING_CERT_PROFILE_NAME  # Certificate profile name
AZURE_SIGNING_ENDPOINT          # Azure signing service endpoint
```

### 4. Self-Hosted Runner Configuration

To use self-hosted Windows runners:

```yaml
runs-on: [self-hosted, windows, x64]

# Add environment setup for self-hosted runners
- name: Environment Setup for Self-Hosted
  run: |
    $RunnerDir = Split-Path -Parent $env:RUNNER_WORKSPACE
    Write-Output "RUSTUP_HOME=$RunnerDir\.rustup" >> $env:GITHUB_ENV
    Write-Output "CARGO_HOME=$RunnerDir\.cargo" >> $env:GITHUB_ENV
```

### 5. Matrix Builds for Multiple Configurations

```yaml
strategy:
  matrix:
    target: [x86_64-pc-windows-msvc, aarch64-pc-windows-msvc]
    config: [debug, release]
    include:
      - target: x86_64-pc-windows-msvc
        arch: x64
      - target: aarch64-pc-windows-msvc  
        arch: arm64

steps:
  - name: Build for ${{ matrix.target }}
    run: cargo build --target ${{ matrix.target }} ${{ matrix.config == 'release' && '--release' || '' }}
```

### 6. Dependency Caching Customization

```yaml
- name: Cache Cargo dependencies
  uses: actions/cache@v3
  with:
    path: |
      ~/.cargo/registry
      ~/.cargo/git
      target
    key: ${{ runner.os }}-${{ matrix.target }}-cargo-${{ hashFiles('**/Cargo.lock') }}
    restore-keys: |
      ${{ runner.os }}-${{ matrix.target }}-cargo-
      ${{ runner.os }}-cargo-
```

### 7. Extended Testing Configuration

```yaml
- name: Install additional test tools
  run: |
    cargo install cargo-nextest --locked
    cargo install cargo-tarpaulin --locked  # Code coverage
    cargo install cargo-audit --locked      # Security audit

- name: Run extended tests
  run: |
    cargo nextest run --workspace
    cargo tarpaulin --out xml             # Generate coverage
    cargo audit                           # Security audit
```

### 8. Artifact Upload Customization

```yaml
- name: Upload build artifacts
  uses: actions/upload-artifact@v4
  with:
    name: zed-windows-${{ matrix.target }}-${{ github.sha }}
    path: |
      target/${{ matrix.target }}/release/zed.exe
      target/${{ matrix.target }}/release/cli.exe
    retention-days: 14  # Custom retention period
```

### 9. Notification Configuration

```yaml
- name: Notify on failure
  if: failure()
  uses: 8398a7/action-slack@v3
  with:
    status: failure
    channel: '#build-notifications'
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

### 10. Performance Optimization

```yaml
env:
  # Optimize Rust compilation
  CARGO_INCREMENTAL: 0
  RUSTFLAGS: "-C target-cpu=native"
  
  # Use faster linker if available
  RUSTFLAGS: "-C link-arg=-fuse-ld=lld"
```

## Environment-Specific Configurations

### Development Environment

```yaml
# .github/workflows/windows-dev.yml
name: Windows Development Build

on:
  pull_request:
    branches: [develop]

jobs:
  quick-build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Quick debug build
        run: cargo build --bin zed
      - name: Basic tests
        run: cargo test --package zed
```

### Staging Environment  

```yaml
# .github/workflows/windows-staging.yml
name: Windows Staging Build

on:
  push:
    branches: [staging]

jobs:
  staging-build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Full build and test
        run: |
          cargo build --release
          cargo test --workspace
      - name: Create unsigned installer
        run: .\script\bundle-windows.ps1
```

### Production Environment

```yaml
# .github/workflows/windows-production.yml  
name: Windows Production Release

on:
  push:
    tags: ['v*']

jobs:
  production-release:
    runs-on: windows-latest
    environment: production  # Requires approval
    steps:
      - uses: actions/checkout@v4
      - name: Production build
        run: cargo build --release
      - name: Create signed installer
        env:
          # Production signing secrets
          AZURE_TENANT_ID: ${{ secrets.AZURE_SIGNING_TENANT_ID }}
          # ... other signing vars
        run: .\script\bundle-windows.ps1
```

## Troubleshooting Configurations

### Debug Mode

```yaml
- name: Enable debug logging
  run: |
    Write-Output "RUST_LOG=debug" >> $env:GITHUB_ENV
    Write-Output "RUST_BACKTRACE=full" >> $env:GITHUB_ENV

- name: Debug environment
  run: |
    Get-ChildItem env: | Sort-Object Name
    rustc --version --verbose
    cargo --version --verbose
```

### Verbose Output

```yaml
- name: Verbose build
  run: cargo build --verbose --release

- name: Verbose tests  
  run: cargo test --verbose --workspace
```

## Security Considerations

### Secure Secret Handling

```yaml
- name: Verify secrets are available
  run: |
    if ([string]::IsNullOrEmpty($env:AZURE_TENANT_ID)) {
      Write-Error "Azure signing secrets not configured"
      exit 1
    }
  env:
    AZURE_TENANT_ID: ${{ secrets.AZURE_SIGNING_TENANT_ID }}
```

### Dependency Verification

```yaml
- name: Verify dependencies
  run: |
    cargo verify-project
    cargo tree --duplicates
    cargo audit
```

## Performance Monitoring

```yaml
- name: Build timing
  run: |
    $start = Get-Date
    cargo build --release
    $end = Get-Date
    $duration = $end - $start
    Write-Host "Build completed in $($duration.TotalMinutes) minutes"
```

These examples can be mixed and matched based on your specific requirements. Always test configuration changes in a development branch before applying to production workflows.
