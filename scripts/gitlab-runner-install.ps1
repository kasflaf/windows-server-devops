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

# Step 2: Download GitLab Runner binary
Write-Host "Downloading GitLab Runner binary..." -ForegroundColor Yellow
$RunnerExePath = Join-Path $InstallPath "gitlab-runner.exe"

try {
    # Download the latest GitLab Runner for Windows
    $DownloadUrl = "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-windows-amd64.exe"
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $RunnerExePath
    Write-Host "GitLab Runner binary downloaded successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to download GitLab Runner binary: $($_.Exception.Message)"
    exit 1
}

# Step 3: Set proper permissions on the directory and executable
Write-Host "Setting permissions on GitLab Runner directory..." -ForegroundColor Yellow
try {
    # Remove write permissions for regular users
    $acl = Get-Acl $InstallPath
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Users", "Write", "Deny")
    $acl.SetAccessRule($accessRule)
    Set-Acl -Path $InstallPath -AclObject $acl
    
    # Set permissions on the executable
    $acl = Get-Acl $RunnerExePath
    $acl.SetAccessRule($accessRule)
    Set-Acl -Path $RunnerExePath -AclObject $acl
    
    Write-Host "Permissions set successfully." -ForegroundColor Green
} catch {
    Write-Warning "Failed to set permissions: $($_.Exception.Message)"
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
        & .\gitlab-runner.exe $registerArgs
        Write-Host "Runner registered successfully." -ForegroundColor Green
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
        & .\gitlab-runner.exe install --user $Username --password $Password
    } else {
        # Install with built-in system account (recommended)
        Write-Host "Installing service with built-in system account..." -ForegroundColor Yellow
        & .\gitlab-runner.exe install
    }
    
    Write-Host "Service installed successfully." -ForegroundColor Green
    
    # Start the service
    Write-Host "Starting GitLab Runner service..." -ForegroundColor Yellow
    & .\gitlab-runner.exe start
    Write-Host "Service started successfully." -ForegroundColor Green
    
} catch {
    Write-Error "Failed to install or start service: $($_.Exception.Message)"
    exit 1
}

# Optional: Display configuration file location
$configPath = Join-Path $InstallPath "config.toml"
Write-Host ""
Write-Host "Installation completed successfully!" -ForegroundColor Green
Write-Host "Configuration file location: $configPath" -ForegroundColor Cyan
Write-Host "You can modify the 'concurrent' value in config.toml to allow multiple concurrent jobs." -ForegroundColor Cyan
Write-Host "Logs are available in Windows Event Log." -ForegroundColor Cyan
Write-Host ""
Write-Host "To verify the installation, run:" -ForegroundColor Yellow
Write-Host "Get-Service gitlab-runner" -ForegroundColor Yellow