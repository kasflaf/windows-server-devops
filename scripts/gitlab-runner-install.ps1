param(
    [string]$InstallPath = "C:\GitLab-Runner",
    [string]$RunnerUrl = "",
    [string]$RegistrationToken = "",
    [string]$RunnerName = "windows-runner",
    [string]$RunnerTags = "windows,powershell",
    [string]$Executor = "shell",
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

# Step 3: Set proper permissions on the directory and executable
Write-Host "Setting permissions on GitLab Runner directory..." -ForegroundColor Yellow
try {
    # Get current ACL
    $acl = Get-Acl $InstallPath
    
    # Remove inherited permissions and keep existing explicit permissions
    $acl.SetAccessRuleProtection($true, $true)
    
    # Add explicit permissions for accounts that need access
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $serviceRule = New-Object System.Security.AccessControl.FileSystemAccessRule("NT SERVICE\gitlab-runner", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $localServiceRule = New-Object System.Security.AccessControl.FileSystemAccessRule("LOCAL SERVICE", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $networkServiceRule = New-Object System.Security.AccessControl.FileSystemAccessRule("NETWORK SERVICE", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    
    # Remove any existing rules for these accounts first
    $acl.SetAccessRule($systemRule)
    $acl.SetAccessRule($adminRule)
    $acl.SetAccessRule($serviceRule)
    $acl.SetAccessRule($localServiceRule) 
    $acl.SetAccessRule($networkServiceRule)
    
    # Apply permissions to directory
    Set-Acl -Path $InstallPath -AclObject $acl
    
    # Apply same permissions to executable
    Set-Acl -Path $RunnerExePath -AclObject $acl
    
    Write-Host "Permissions set successfully." -ForegroundColor Green
} catch {
    Write-Warning "Failed to set permissions: $($_.Exception.Message)"
    Write-Host "Attempting alternative permission method..." -ForegroundColor Yellow
    
    # Alternative method using icacls
    try {
        & icacls $InstallPath /grant "SYSTEM:(OI)(CI)F" /grant "Administrators:(OI)(CI)F" /grant "NT SERVICE\gitlab-runner:(OI)(CI)F" /grant "LOCAL SERVICE:(OI)(CI)F" /grant "NETWORK SERVICE:(OI)(CI)F" /T
        & icacls $RunnerExePath /grant "SYSTEM:F" /grant "Administrators:F" /grant "NT SERVICE\gitlab-runner:F" /grant "LOCAL SERVICE:F" /grant "NETWORK SERVICE:F"
        Write-Host "Alternative permissions set successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to set permissions with alternative method: $($_.Exception.Message)"
        Write-Host "You may need to manually set permissions on $InstallPath" -ForegroundColor Red
    }
}

# Step 4: Register the runner (if URL and token provided)
if ($RunnerUrl -and $RegistrationToken) {
    Write-Host "Registering GitLab Runner..." -ForegroundColor Yellow
    Set-Location $InstallPath
    
    $registerArgs = @(
        "register",
        "--non-interactive",
        "--url", $RunnerUrl,
        "--registration-token", $RegistrationToken,
        "--name", $RunnerName,
        "--tag-list", $RunnerTags,
        "--executor", $Executor
    )
    
    try {
        $result = & .\gitlab-runner.exe $registerArgs 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Runner registered successfully." -ForegroundColor Green
        } else {
            Write-Error "Failed to register runner. Exit code: $LASTEXITCODE. Output: $result"
            exit 1
        }
    } catch {
        Write-Error "Failed to register runner: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "Skipping runner registration (URL and token not provided)." -ForegroundColor Yellow
    Write-Host "To register manually, run:" -ForegroundColor Cyan
    Write-Host "cd $InstallPath" -ForegroundColor Cyan
    Write-Host ".\gitlab-runner.exe register" -ForegroundColor Cyan
}

# Step 5: Install and start the service
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
$configPath = Join-Path $InstallPath "config.toml"
Write-Host ""
Write-Host "Installation completed successfully!" -ForegroundColor Green
Write-Host "Configuration file location: $configPath" -ForegroundColor Cyan
Write-Host "You can modify the 'concurrent' value in config.toml to allow multiple concurrent jobs." -ForegroundColor Cyan
Write-Host "Logs are available in Windows Event Log." -ForegroundColor Cyan
Write-Host ""
Write-Host "To verify the installation, run:" -ForegroundColor Yellow
Write-Host "Get-Service gitlab-runner" -ForegroundColor Yellow