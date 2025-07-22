# GitLab Runner Installation Script for Windows

This PowerShell script automates the installation and configuration of GitLab Runner on Windows Server systems.

## Prerequisites

- Windows Server 2016 or later
- PowerShell 5.1 or later
- Administrator privileges
- GitLab Runner authentication token (starts with `glrt-`)
- GitLab Instance with Group or Project Configured (This is where you get the Token)

## Quick Start

pull the script first

### Basic Installation (Interactive Mode)

Run the script without parameters for interactive registration:

```powershell
.\gitlab-runner-install.ps1
```

The script will:
1. Download GitLab Runner binary
2. Set secure permissions
3. Prompt for interactive runner registration
4. Install and start the Windows service
5. Configure automatic startup

### Non-Interactive Installation

Provide parameters for automated installation:

```powershell
.\gitlab-runner-install.ps1 `
    -Url "https://gitlab.com/" `
    -Token "glrt-your-runner-token" `
    -Description "my-windows-runner" `
    -TagList "windows,powershell" `
    -Executor "shell"
```

## Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `InstallPath` | Installation directory | `C:\GitLab-Runner` | No |
| `Url` | GitLab instance URL | `""` | Yes (for non-interactive) |
| `Token` | Runner authentication token | `""` | Yes (for non-interactive) |
| `Description` | Runner description | `"windows-runner"` | No |
| `TagList` | Comma-separated tags | `"windows,powershell"` | No |
| `Executor` | Executor type | `"shell"` | No |
| `DockerImage` | Docker image (for docker executor) | `""` | No |
| `UseUserAccount` | Use specific user account | `$false` | No |
| `Username` | Username for service account | `""` | No |
| `Password` | Password for service account | `""` | No |

## Executor Types

### Shell Executor (Default)
Best for native Windows jobs:

```powershell
.\gitlab-runner-install.ps1 `
    -Url "https://gitlab.com/" `
    -Token "glrt-your-token" `
    -Executor "shell" `
    -TagList "windows,shell,powershell"
```

### Docker Executor
Best for containerized jobs:

```powershell
.\gitlab-runner-install.ps1 `
    -Url "https://gitlab.com/" `
    -Token "glrt-your-token" `
    -Executor "docker-windows" `
    -DockerImage "mcr.microsoft.com/windows/servercore:ltsc2019" `
    -TagList "windows,docker"
```

## Adding Additional Runners to Same Installation

After running the installation script, you can register additional runners to the same GitLab Runner installation:

```powershell
# After Instalation add additional registrations manually
cd C:\GitLab-Runner
.\gitlab-runner.exe register `
    --non-interactive `
    --url "https://gitlab.com/" `
    --token "glrt-docker-token" `
    --description "docker-runner" `
    --tag-list "windows,docker" `
    --executor "docker-windows" `
    --docker-image "mcr.microsoft.com/windows/servercore:ltsc2019"

# Set concurrent jobs to 2 (or above) IMPORTANT TO RUN CONCURRENTLY !!!

#use scripts
$configPath = "C:\GitLab-Runner\config.toml"
(Get-Content $configPath) -replace '^(concurrent\s*=\s*)\d+', '${1}2' | Set-Content $configPath
# or edit manually using notepad
notepad C:\GitLab-Runner\config.toml

# Restart the service to apply changes
.\gitlab-runner.exe restart
```

This creates one Windows service managing multiple runner registrations with different executors.

## Configuration Management

### Config File Location
The runner configuration is stored in:
```
C:\GitLab-Runner\config.toml
```

## Service Management

### Manual Service Operations

```powershell
# Navigate to runner directory
cd C:\GitLab-Runner

# Service commands
.\gitlab-runner.exe status    # Check status
.\gitlab-runner.exe stop      # Stop service
.\gitlab-runner.exe start     # Start service  
.\gitlab-runner.exe restart   # Restart service
.\gitlab-runner.exe uninstall # Remove service
```

### Windows Service Manager

```powershell
# PowerShell service commands
Get-Service gitlab-runner          # Check status
Start-Service gitlab-runner        # Start service
Stop-Service gitlab-runner         # Stop service
Restart-Service gitlab-runner      # Restart service
Set-Service gitlab-runner -StartupType Automatic  # Auto-start
```

## Troubleshooting

### Common Issues

#### Permission Denied Errors
The script sets secure permissions automatically. If issues persist:

```powershell
# Manual permission fix
icacls C:\GitLab-Runner /grant "SYSTEM:(OI)(CI)F" /grant "Administrators:(OI)(CI)F" /T
```

#### Service Won't Start
Check Event Viewer or run:

```powershell
cd C:\GitLab-Runner
.\gitlab-runner.exe run  # Run in foreground to see errors
```

#### Registration Issues
If registration fails, try interactive mode:

```powershell
cd C:\GitLab-Runner
.\gitlab-runner.exe register  # Interactive registration
```

### Log Locations

- **Windows Event Log**: Applications and Services Logs → GitLab Runner
- **Service Logs**: Use `.\gitlab-runner.exe run` for console output
- **Job Logs**: Available in GitLab web interface

## Support

For issues with this script, check:
- [GitLab Runner Documentation](https://docs.gitlab.com/runner/)
- [Gitlab Runner Registration Guide](https://docs.gitlab.com/runner/register/)
- [Windows Installation Guide](https://docs.gitlab.com/runner/install/windows.html)
- Event Viewer logs
- GitLab Runner logs via `.\gitlab-runner.exe run`

## Tested on
- Windows Server 2025 Standard Evaluation (Build 26100)
- PowerShell 5.1.26100.1591
- GitLab Runner 18.2.0 (x64)
