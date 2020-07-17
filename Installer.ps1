[CmdletBinding()]
param (
    # The identifier of a package to install.
    [Parameter()]
    [Alias("Id")]
    [string[]]
    $PackageId,

    # The package set to install.
    [Parameter()]
    [Alias("Set")]
    [string[]]
    $PackageSet,

    # The path to the install configuration.
    [Parameter(
        Mandatory
    )]
    [Alias("Config")]
    [string]
    $ConfigurationPath
)

[ref] $webClient = $null

#region Configuration

# Get the content of the configuration file that defines the packages.

# Parse the path so that we know whether it refers to web content or a file on disk.
$configUri = [uri] $ConfigurationPath

switch ($configUri.Scheme)
{
    file
    {
        $configContent = Get-Content $ConfigurationPath
        if (-not $configContent)
        {
            Write-Error "Failed to read configuration."
            return
        }
    }
    { $_ -in "http", "https" }
    {
        $webClient.Value = New-Object Net.WebClient
        $configContent = $webClient.Value.DownloadString($ConfigurationPath)
        if (-not $configContent)
        {
            Write-Error "Failed to download configuration."
            return
        }
    }
    Default
    {
        Write-Error "Malformed uri: $ConfigurationPath"
        return
    }
}

$configuration = $configContent | ConvertFrom-Json

if (-not $configuration)
{
    Write-Error "Failed to parse configuration."
    return
}

#endregion

#region Collect Packages

$packages = $(
    # Concatenate the explicit packages with the packages from the specified sets.

    $PackageId

    $PackageSet | Select-Object -Unique | ForEach-Object {
        $setName = $_
        $set = $configuration.packageSets | Where-Object name -EQ $setName | Select-Object -First 1
        if (-not $set)
        {
            Write-Warning "A package set with the name '$setName' could not be found in the configuration."
            return
        }

        return $set
    } | Select-Object -ExpandProperty packages
) | Select-Object -Unique | ForEach-Object {
    $packageIdentifier = $_
    $package = $configuration.packages | Where-Object packageId -EQ $packageIdentifier
    if (-not $package)
    {
        Write-Warning "A package identified by '$packageIdentifier' could not be found in the configuration."
    }

    return $package
}

#endregion

#region Define Package Managers

enum InstallerExitCode
{
    Success
    Skipped
    Failure
    SuccessAbort
    FailureAbort
}

$packageManagers = @(
    @{
        Id                    = "Choco"
        Name                  = "Chocolatey"
        RequiresWebClient     = $true
        CheckManagerInstalled = {
            # Chocolatey is considered to be installed if choco.exe is on the path.
            return Get-Command choco -ErrorAction SilentlyContinue
        }
        InstallManager        = {
            param ($webClient)
            Write-Debug "Installing Chocolatey"
            Invoke-Expression ($webClient.DownloadString('https://chocolatey.org/install.ps1'))
        }
        InstallPackage        = {
            param ($package, $installerExitCode)

            $arguments = @(
                'install'
                $package.Sources.Choco.Id
            )

            if ($package.Parameters)
            {
                $arguments += '--params'
                $arguments += "`"$($package.Parameters)`""
            }

            Write-Debug "Invoke: choco $arguments"
            choco @arguments

            # Exit code reference: https://chocolatey.org/docs/commands-install#exit-codes
            switch ($LASTEXITCODE)
            {
                0
                {
                    $installerExitCode.Value = [InstallerExitCode]::Success
                    break
                }
                350
                {
                    # Pending reboot detected, no action has occurred.
                    Write-Warning "A reboot is pending. Please execute this script again to install."
                    return [InstallerExitCode]::Skipped
                    break
                }
                1604
                {
                    # Install suspended, incomplete.
                    Write-Warning "The install has been canceled."
                    $installerExitCode.Value = [InstallerExitCode]::Skipped
                    break
                }
                1641
                {
                    # Success, reboot initiated.
                    Write-Warning "A reboot has been initiated. Please execute this script again to continue."
                    $installerExitCode.Value = [InstallerExitCode]::SuccessAbort
                    break
                }
                3010
                {
                    # Success, reboot required.
                    Write-Warning "A reboot is required to use the applicate."
                    $installerExitCode.Value = [InstallerExitCode]::Success
                    break
                }
                Default
                {
                    # An error has occurred.
                    $installerExitCode.Value = [InstallerExitCode]::Failure
                    break
                }
            }
        }
    }
    @{
        Id                    = "MicrosoftStore"
        Name                  = "Microsoft Store"
        IsInstalled           = $true
        RequiresWebClient     = $false
        CheckManagerInstalled = {
            return $true
        }
        InstallManager        = {
            param ($webClient)
        }
        InstallPackage        = {
            param ($package, $installerExitCode)

            # This install is manual because it is very difficult and fragile to automate
            # app installation from the Microsoft Store.
            Start-Process "ms-windows-store://pdp/?ProductId=$($package.Sources.MicrosoftStore.Id)"
            Write-Host "Please install the app from the store before continuing."
            Pause

            $installerExitCode.Value = [InstallerExitCode]::Success
        }
    }
    @{
        Id                    = "WinGet"
        Name                  = "WinGet"
        RequiresWebClient     = $true
        CheckManagerInstalled = {
            # WinGet is considered to be installed if choco.exe is on the path.
            return Get-Command winget -ErrorAction SilentlyContinue
        }
        InstallManager        = {
            param ($webClient)
            Write-Verbose "Installing WinGet"
            $downloadSource = 'https://github.com/microsoft/winget-cli/releases/download/v0.1.41821-preview/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appxbundle'
            $downloadDestination = "$env:HOMEPATH\Downloads\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appxbundle"
            $webClient.DownloadFile($downloadSource, $downloadDestination)

            Write-Debug "Installing WinGet appxbundle"
            Add-AppxPackage -Path $downloadDestination
        }
        InstallPackage        = {
            param ($package, $installerExitCode)

            $arguments = @(
                'install'
                '--id'
                $package.Sources.WinGet.Id
                '--exact'
            )

            if ($package.Parameters)
            {
                $arguments += '--override'
                $arguments += "`"$($package.Parameters)`""
            }

            Write-Debug "Invoke: winget $arguments"
            winget @arguments

            switch ($LASTEXITCODE)
            {
                0
                {
                    $installerExitCode.Value = [InstallerExitCode]::Success
                    break
                }
                Default
                {
                    # An error occurred.
                    $installerExitCode.Value = [InstallerExitCode]::Failure
                    break
                }
            }
        }
    }
)

#endregion

#region Install Package Managers

# Gather the package managers that host the desired packages.
$configuredSourceNames = $packages | ForEach-Object {
    $_.sources | Get-Member -MemberType NoteProperty
} | Select-Object -ExpandProperty Name -Unique

# Get the package managers that are both defined and desired.
$allowedPackageManagers = $(
    if ($configuration.sourcePreference)
    {
        # If preferences are specified, select only the package managers that we actually need.
        $configuration.sourcePreference | Where-Object {
            $_ -in $configuredSourceNames
        }
    }
    else
    {
        # Otherwise, use all package managers we need.
        $configuredSourceNames
    }
) | ForEach-Object {
    $managerId = $_

    # Find the package manager by ID.
    $packageManager = $packageManagers | Where-Object Id -EQ $managerId
    if (-not $packageManager)
    {
        Write-Warning "A package manager identified as '$managerId' is not defined."
        return
    }

    return $packageManager
}

if (-not $allowedPackageManagers)
{
    Write-Error "None of the selected packages can be installed from the preferred sources."
    return
}

# Install each package manager if not already installed.
$allowedPackageManagers | ForEach-Object {
    $packageManager = $_

    if ($packageManager.IsInstalled)
    {
        return
    }

    if (& $packageManager.CheckManagerInstalled)
    {
        Write-Verbose "Skipping installation of $($packageManager.Name) because it is already installed."
        $packageManager.IsInstalled = $true
        return
    }

    Write-Verbose "Istalling package manager: $($packageManager.Name)"

    if ($packageManager.RequiresWebClient -and -not $webClient.Value)
    {
        $webClient.Value = New-Object Net.WebClient
    }

    & $packageManager.InstallManager $webClient.Value

    # Reload the path variable in case the package manager was not added to the path of the current session.
    # We use the path to determine whether the manager is installed.
    # Reference: https://stackoverflow.com/questions/17794507/reload-the-path-in-powershell
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    $packageManager.IsInstalled = [bool] (& $packageManager.CheckManagerInstalled)

    if (-not $packageManager.IsInstalled)
    {
        Write-Error "Failed to install package manager: $($packageManager.Name)"
    }
}

$enabledPackageManagers = $allowedPackageManagers | Where-Object IsInstalled -EQ $true

#endregion

#region Installation Progress Persistence

# Keep track of files that we have installed so that we can resume
# if one of the installs initiated a reboot.

$installationProgressPath = "$env:HOMEPATH\.WinConfig.json"

$installedPackages = $null
if (Test-Path $installationProgressPath)
{
    $json = Get-Content $installationProgressPath | ConvertFrom-Json
    $installedPackages = $json.Packages
}

if ($installedPackages -isnot [array])
{
    $installedPackages = @()
}

$installProgress = [PSCustomObject] @{
    Packages = $installedPackages
}

# Keep track of all packages we have already installed.
$installedPackages = @{}
$installProgress.Packages | ForEach-Object {
    if ($_.Id)
    {
        $installedPackages[$_.Id] = $_
    }
}

#endregion

#region Install Packages

[ref] $abort = $false

$packages | ForEach-Object {
    if ($abort.Value)
    {
        return
    }

    $package = $_

    $packageIdentifier = $package.packageId

    if ($installedPackages.ContainsKey($packageIdentifier))
    {
        Write-Verbose "Skipping $packageIdentifier because it has already been installed."
        return
    }

    [ref] $success = $false

    $enabledPackageManagers | ForEach-Object {
        if ($success.Value)
        {
            # We already successfully installed this package.
            return
        }

        $managerId = $_.Id

        $packageManager = $package.sources.$managerId
        if (-not $packageManager)
        {
            # This package cannot be installed with this package manager.
            return
        }

        Write-Host "Installing $packageIdentifier"
        [ref] $installerExitCode = [InstallerExitCode]::Failure
        & $packageManager.InstallPackage $package $installerExitCode

        switch ($installerExitCode.Value)
        {
            Success
            {
                $success.Value = $true
                return
            }
            SuccessAbort
            {
                $success.Value = $true
                $abort.Value = $true
                return
            }
            FailureAbort
            {
                $abort.Value = $true
                break
            }
        }
    }

    if ($success.Value)
    {
        $installedPackage = [PSCustomObject] @{
            Id = $packageIdentifier
        }

        $installProgress.Packages += $installedPackage
        $installedPackages[$packageIdentifier] = $installedPackage

        $installProgress | ConvertTo-Json | Set-Content $installationProgressPath
    }
    else
    {
        Write-Error "Failed to install package: $packageIdentifier"
    }
}

if ($abort.Value)
{
    Write-Warning "Installation has aborted."
}

#endregion
