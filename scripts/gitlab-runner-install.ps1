param(
    [string]$InstallPath = "C:\GitLab-Runner",
    [string]$Url = "",  # Changed from RunnerUrl to match --url
    [string]$Token = "",  # Changed from RegistrationToken to match --token
    [string]$Description = "windows-runner",  # Changed from RunnerName to match --description
    [string]$TagList = "windows,powershell",  # Changed from RunnerTags to match --tag-list
    [string]$Executor = "shell",
    [string]$DockerImage = "",  # Add for docker executor
    [switch]$UseUserAccount,
    [string]$Username = "",
    [string]$Password = ""
)

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator!"
    exit 1
}

Write-Host "GitLab Runner Installation Script" -ForegroundColor Green
Write-Host "=================================" -ForegroundColor Green

# Step 1: Create GitLab Runner directory
Write-Host "Creating GitLab Runner directory at $InstallPath..." -ForegroundColor Yellow
if (!(Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Host "Directory created successfully." -ForegroundColor Green
} else {
    Write-Host "Directory already exists." -ForegroundColor Yellow
}

# Step 2: Download GitLab Runner binary (check if it already exists)
$RunnerExePath = Join-Path $InstallPath "gitlab-runner.exe"

if (Test-Path $RunnerExePath) {
    Write-Host "GitLab Runner binary already exists at $RunnerExePath" -ForegroundColor Yellow
    $overwrite = Read-Host "Do you want to re-download it? (y/N)"
    if ($overwrite -eq 'y' -or $overwrite -eq 'Y') {
        Write-Host "Re-downloading GitLab Runner binary..." -ForegroundColor Yellow
        try {
            $DownloadUrl = "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-windows-amd64.exe"
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $RunnerExePath -Force
            Write-Host "GitLab Runner binary re-downloaded successfully." -ForegroundColor Green
        } catch {
            Write-Error "Failed to download GitLab Runner binary: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "Using existing GitLab Runner binary." -ForegroundColor Green
    }
} else {
    Write-Host "Downloading GitLab Runner binary..." -ForegroundColor Yellow
    try {
        $DownloadUrl = "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-windows-amd64.exe"
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $RunnerExePath
        Write-Host "GitLab Runner binary downloaded successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to download GitLab Runner binary: $($_.Exception.Message)"
        exit 1
    }
}

# Step 3: Set comprehensive permissions to prevent access denied errors
Write-Host "Setting comprehensive permissions on GitLab Runner directory..." -ForegroundColor Yellow
try {
    # Use icacls for more reliable permission setting
    Write-Host "Setting directory permissions..." -ForegroundColor Gray
    & icacls $InstallPath /grant "SYSTEM:(OI)(CI)F" /grant "Administrators:(OI)(CI)F" /grant "LOCAL SERVICE:(OI)(CI)F" /grant "NETWORK SERVICE:(OI)(CI)F" /grant "Everyone:(OI)(CI)M" /T /C /Q
    
    Write-Host "Setting executable permissions..." -ForegroundColor Gray
    & icacls $RunnerExePath /grant "SYSTEM:F" /grant "Administrators:F" /grant "LOCAL SERVICE:F" /grant "NETWORK SERVICE:F" /grant "Everyone:M" /C /Q
    
    Write-Host "Permissions set successfully." -ForegroundColor Green
} catch {
    Write-Warning "Failed to set permissions using icacls: $($_.Exception.Message)"
    
    # Fallback to PowerShell ACL method
    try {
        Write-Host "Trying PowerShell ACL method..." -ForegroundColor Yellow
        $acl = Get-Acl $InstallPath
        
        # Add broad permissions to ensure registration works
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $everyoneRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        
        $acl.SetAccessRule($systemRule)
        $acl.SetAccessRule($adminRule)
        $acl.SetAccessRule($everyoneRule)
        
        Set-Acl -Path $InstallPath -AclObject $acl
        Set-Acl -Path $RunnerExePath -AclObject $acl
        
        Write-Host "Fallback permissions set successfully." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to set permissions: $($_.Exception.Message)"
        Write-Host "Continuing with installation - you may need to set permissions manually." -ForegroundColor Yellow
    }
}

# Step 4: Register the runner
$configPath = Join-Path $InstallPath "config.toml"
$isRegistered = Test-Path $configPath

if (-not $isRegistered) {
    Set-Location $InstallPath
    
    if ($Url -and $Token) {
        # Non-interactive mode - all parameters provided
        Write-Host "Registering GitLab Runner (non-interactive mode)..." -ForegroundColor Yellow
        
        $registerArgs = @(
            "register",
            "--non-interactive",
            "--url", $Url,
            "--token", $Token,
            "--description", $Description,
            "--tag-list", $TagList,
            "--executor", $Executor
        )
        
        # Add docker-specific parameters if using docker executor
        if ($Executor -eq "docker" -or $Executor -eq "docker-windows") {
            if ($DockerImage) {
                $registerArgs += @("--docker-image", $DockerImage)
            } else {
                # Default Windows docker image
                $registerArgs += @("--docker-image", "mcr.microsoft.com/windows/servercore:ltsc2019")
            }
        }
        
        Write-Host "Registration parameters:" -ForegroundColor Cyan
        Write-Host "  URL: $Url" -ForegroundColor Gray
        Write-Host "  Description: $Description" -ForegroundColor Gray
        Write-Host "  Tags: $TagList" -ForegroundColor Gray
        Write-Host "  Executor: $Executor" -ForegroundColor Gray
        if ($DockerImage) {
            Write-Host "  Docker Image: $DockerImage" -ForegroundColor Gray
        }
        
        try {
            $result = & .\gitlab-runner.exe $registerArgs 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Runner registered successfully (non-interactive)." -ForegroundColor Green
                $isRegistered = $true
            } else {
                Write-Error "Failed to register runner. Exit code: $LASTEXITCODE. Output: $result"
                exit 1
            }
        } catch {
            Write-Error "Failed to register runner: $($_.Exception.Message)"
            exit 1
        }
    } else {
        # Interactive mode - missing parameters
        Write-Host ""
        Write-Host "RUNNER REGISTRATION REQUIRED" -ForegroundColor Yellow
        Write-Host "============================" -ForegroundColor Yellow
        Write-Host "GitLab Runner needs to be registered before installing the service." -ForegroundColor Yellow
        Write-Host ""
        
        if (-not $Url -and -not $Token) {
            Write-Host "No registration parameters provided. Starting interactive registration..." -ForegroundColor Cyan
        } else {
            Write-Host "Missing required parameters for non-interactive registration:" -ForegroundColor Red
            if (-not $Url) { Write-Host "  - Url" -ForegroundColor Red }
            if (-not $Token) { Write-Host "  - Token" -ForegroundColor Red }
            Write-Host ""
            Write-Host "Starting interactive registration instead..." -ForegroundColor Cyan
        }
        
        Write-Host ""
        Write-Host "During interactive registration, you'll be prompted for:" -ForegroundColor White
        Write-Host "  - GitLab URL (e.g., https://gitlab.com/)" -ForegroundColor Gray
        Write-Host "  - Runner authentication token (starts with glrt-)" -ForegroundColor Gray
        Write-Host "  - Description for the runner" -ForegroundColor Gray
        Write-Host "  - Job tags (e.g., windows,powershell)" -ForegroundColor Gray
        Write-Host "  - Executor type (recommended: shell)" -ForegroundColor Gray
        Write-Host ""
        
        $proceed = Read-Host "Start interactive registration now? (Y/n)"
        if ($proceed -eq '' -or $proceed -eq 'y' -or $proceed -eq 'Y') {
            Write-Host "Starting interactive registration..." -ForegroundColor Green
            
            try {
                & .\gitlab-runner.exe register
                
                # Check if registration was successful
                if (Test-Path $configPath) {
                    Write-Host "Runner registered successfully (interactive)!" -ForegroundColor Green
                    $isRegistered = $true
                } else {
                    Write-Warning "Registration may have failed - config.toml not found."
                    Write-Host "Please check the registration output above for errors." -ForegroundColor Yellow
                    exit 1
                }
            } catch {
                Write-Error "Failed to start interactive registration: $($_.Exception.Message)"
                exit 1
            }
        } else {
            Write-Host ""
            Write-Host "Registration cancelled. You can:" -ForegroundColor Yellow
            Write-Host "1. Run this script again with parameters:" -ForegroundColor Cyan
            Write-Host "   .\gitlab-runner-install.ps1 -Url 'https://gitlab.com/' -Token 'glrt-your-token'" -ForegroundColor Cyan
            Write-Host "2. Or register manually:" -ForegroundColor Cyan
            Write-Host "   cd $InstallPath" -ForegroundColor Cyan
            Write-Host "   .\gitlab-runner.exe register" -ForegroundColor Cyan
            Write-Host "   Then run this script again to install the service." -ForegroundColor Cyan
            exit 0
        }
    }
} else {
    Write-Host "Runner configuration already exists at $configPath" -ForegroundColor Green
    $isRegistered = $true
}

# Step 5: Install and start the service (only proceed if registered)
if ($isRegistered) {
    Write-Host ""
    Write-Host "Installing GitLab Runner as a Windows service..." -ForegroundColor Yellow
    Set-Location $InstallPath

    try {
        if ($UseUserAccount -and $Username -and $Password) {
            # Install with user account
            Write-Host "Installing service with user account: $Username" -ForegroundColor Yellow
            $installResult = & .\gitlab-runner.exe install --user $Username --password $Password 2>&1
            $installExitCode = $LASTEXITCODE
        } else {
            # Install with built-in system account (recommended)
            Write-Host "Installing service with built-in system account..." -ForegroundColor Yellow
            $installResult = & .\gitlab-runner.exe install 2>&1
            $installExitCode = $LASTEXITCODE
        }
        
        if ($installExitCode -eq 0) {
            Write-Host "Service installed successfully." -ForegroundColor Green
            
            # Now that service is installed, add permissions for the gitlab-runner service account
            Write-Host "Setting permissions for GitLab Runner service account..." -ForegroundColor Yellow
            try {
                & icacls $InstallPath /grant "NT SERVICE\gitlab-runner:(OI)(CI)F" /T /C /Q
                Write-Host "GitLab Runner service permissions set successfully." -ForegroundColor Green
            } catch {
                Write-Warning "Failed to set GitLab Runner service permissions: $($_.Exception.Message)"
            }
            
        } else {
            Write-Error "Failed to install service. Exit code: $installExitCode. Output: $installResult"
            exit 1
        }
        
        # Start the service
        Write-Host "Starting GitLab Runner service..." -ForegroundColor Yellow
        $startResult = & .\gitlab-runner.exe start 2>&1
        $startExitCode = $LASTEXITCODE
        
        if ($startExitCode -eq 0) {
            Write-Host "Service started successfully." -ForegroundColor Green
        } else {
            Write-Error "Failed to start service. Exit code: $startExitCode. Output: $startResult"
            exit 1
        }
        
    } catch {
        Write-Error "Failed to install or start service: $($_.Exception.Message)"
        exit 1
    }

    # Verify service is running
    Write-Host "Verifying service status..." -ForegroundColor Yellow
    try {
        $service = Get-Service -Name "gitlab-runner" -ErrorAction Stop
        if ($service.Status -eq "Running") {
            Write-Host "GitLab Runner service is running successfully." -ForegroundColor Green
        } else {
            Write-Warning "GitLab Runner service is installed but not running. Status: $($service.Status)"
        }
    } catch {
        Write-Warning "Could not verify service status: $($_.Exception.Message)"
    }

    # Display final information
    Write-Host ""
    Write-Host "Installation completed successfully!" -ForegroundColor Green
    Write-Host "Configuration file location: $configPath" -ForegroundColor Cyan
    Write-Host "You can modify the 'concurrent' value in config.toml to allow multiple concurrent jobs." -ForegroundColor Cyan
    Write-Host "Logs are available in Windows Event Log." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage examples:" -ForegroundColor Yellow
    Write-Host "  Non-interactive: .\gitlab-runner-install.ps1 -Url 'https://gitlab.com/' -Token 'glrt-your-token'" -ForegroundColor Cyan
    Write-Host "  Docker executor: .\gitlab-runner-install.ps1 -Url 'https://gitlab.com/' -Token 'glrt-your-token' -Executor 'docker'" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To verify the installation, run:" -ForegroundColor Yellow
    Write-Host "Get-Service gitlab-runner" -ForegroundColor Yellow
} else {
    Write-Error "Runner registration failed. Cannot proceed with service installation."
    exit 1
}