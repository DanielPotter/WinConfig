[CmdletBinding()]
param (
    # The path to the install configuration.
    [Parameter(
        Mandatory
    )]
    [Alias("Config")]
    [string] $ConfigurationPath
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
        $configContent = Get-Content $ConfigurationPath -Raw
        if (-not $configContent)
        {
            Write-Error "Failed to read configuration."
            return
        }
        break
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
        break
    }
    Default
    {
        Write-Error "Malformed uri: $ConfigurationPath"
        return
    }
}

function ConvertFrom-JsonInternal
{
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(
            Position = 0,
            Mandatory,
            ValueFromPipeline
        )]
        [string] $InputObject
    )

    process
    {
        # Strip out comments without removing any lines.
        # We use the Multiline option to let us use the start (^) and end ($) anchors as line anchors.
        # Reference: https://stackoverflow.com/a/59264162 (12/12/2024)
        $sanitizedInputObject = $InputObject -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*' -replace '(?ms)/\*.*?\*/'
        return ConvertFrom-Json $sanitizedInputObject
    }
}

$configuration = $configContent | ConvertFrom-JsonInternal

if (-not $configuration)
{
    Write-Error "Failed to parse configuration."
    return
}

#endregion

#region Define Package Managers

function resolvePathString
{
    [OutputType([string])]
    param (
        [Parameter(
            Position = 0,
            ValueFromPipeline
        )]
        [string] $InputString
    )

    process
    {
        if ($InputString)
        {
            return $InputString -replace '\${HOME}', $HOME
        }
    }
}

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
                $package.PackageId
            )

            if ($package.Parameters)
            {
                $arguments += '--params'
                $arguments += "`"$($package.Parameters)`""
            }

            Write-Debug "$($package.PackageId): Invoke: choco $arguments"
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
                    Write-Warning "$($package.PackageId): A reboot is pending. Please execute this script again to install."
                    $installerExitCode.Value = [InstallerExitCode]::Skipped
                    break
                }
                1604
                {
                    # Install suspended, incomplete.
                    Write-Warning "$($package.PackageId): The install has been canceled."
                    $installerExitCode.Value = [InstallerExitCode]::Skipped
                    break
                }
                1641
                {
                    # Success, reboot initiated.
                    Write-Warning "$($package.PackageId): A reboot has been initiated. Please execute this script again to continue."
                    $installerExitCode.Value = [InstallerExitCode]::SuccessAbort
                    break
                }
                3010
                {
                    # Success, reboot required.
                    Write-Warning "$($package.PackageId): A reboot is required to use the applicate."
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
        Id = "Git"
        Name = "Git"
        RequiresWebClient = $false
        RequiredPackages = @(
            "Git.Git"
        )
        CheckManagerInstalled = {
            # Git is considered to be installed if git.exe is on the path.
            return Get-Command git -ErrorAction SilentlyContinue
        }
        InstallManager = {
            param ($webClient)
            Write-Error "Git should be installed using another package manager."
        }
        InstallPackage = {
            param ($package, $installerExitCode)

            $arguments = @(
                'clone'
            )

            if ($package.Parameters)
            {
                $arguments += $package.Parameters
            }

            # Resolve variables in the destination path.
            $destination = $package.Destination
            if (-not $destination)
            {
                Write-Error "$($package.PackageId): No destination was provided."
                $installerExitCode.Value = [InstallerExitCode]::Failure
                return
            }

            $destination = resolvePathString $destination

            # Resolve the path.  This will convert it to an absolute path even if it doesn't exist.
            $absoluteDestination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($destination)
            if (-not $absoluteDestination)
            {
                Write-Error "$($package.PackageId): Failed to resolve the destination to an absolute path: $destination."
                $installerExitCode.Value = [InstallerExitCode]::Failure
                return
            }

            $destinationDirectory = Split-Path $absoluteDestination

            $arguments += @(
                '--'
                $package.PackageId
                $absoluteDestination
            )

            # Ensure the destination directory exists.
            if (-not (Test-Path $destinationDirectory))
            {
                New-Item $destinationDirectory -ItemType Directory | Out-Null
            }

            Write-Debug "$($package.PackageId): Invoke: git $arguments"
            git @arguments

            switch ($LASTEXITCODE)
            {
                0
                {
                    $installerExitCode.Value = [InstallerExitCode]::Success
                    break
                }
                Default
                {
                    # An error has occurred.  Output from Git has already passed through to the console.
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
        Id                    = "Executable"
        Name                  = "Executable"
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

            $arguments = @()
            if ($package.Parameters)
            {
                $arguments += $package.Parameters
            }

            $packageDisplayName = if ($package.Name) { $package.Name } else { $package.PackageId }

            # Resolve variables in the destination path.
            $destination = $package.Destination
            if (-not $destination)
            {
                Write-Error "$($packageDisplayName): No destination was provided."
                $installerExitCode.Value = [InstallerExitCode]::Failure
                return
            }

            $destination = resolvePathString $destination

            $response = Invoke-WebRequest -Uri $package.PackageId -OutFile $destination -PassThru
            if ($response.StatusCode -ne 200)
            {
                Write-Error "$($packageDisplayName): Failed to download executable. [$($response.StatusCode)] $($response.StatusDescription)"
                $installerExitCode.Value = [InstallerExitCode]::Failure
                return
            }

            if (-not (Test-Path $destination))
            {
                Write-Error "$($packageDisplayName): The executable did not download to the expected location: $($destination)"
                $installerExitCode.Value = [InstallerExitCode]::Failure
                return
            }

            & $destination @arguments

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
    @{
        Id                    = "WinGet"
        Name                  = "WinGet"
        RequiresWebClient     = $false
        CheckManagerInstalled = {
            # WinGet is considered to be installed if winget.exe is on the path.
            return Get-Command winget -ErrorAction SilentlyContinue
        }
        InstallManager        = {
            param ($webClient)
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

            Write-Debug "$($package.PackageId): Invoke: winget $arguments"
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

function getPackageManager ($id)
{
    return $packageManagers | Where-Object Id -EQ $id
}

function installPackageManager
{
    param (
        [Parameter(
            Position = 0,
            ValueFromPipeline
        )]
        [object] $PackageManager
    )

    process
    {
        if ($PackageManager.IsInstalled)
        {
            return
        }

        if (Invoke-Command -ScriptBlock $PackageManager.CheckManagerInstalled)
        {
            Write-Verbose "Skipping installation of $($PackageManager.Name) because it is already installed."
            $PackageManager.IsInstalled = $true
            return
        }

        Write-Verbose "Istalling package manager: $($PackageManager.Name)"

        if ($PackageManager.RequiresWebClient -and -not $webClient.Value)
        {
            $webClient.Value = New-Object Net.WebClient
        }

        Invoke-Command -ScriptBlock $PackageManager.InstallManager -ArgumentList $webClient.Value

        # Reload the path variable in case the package manager was not added to the path of the current session.
        # We use the path to determine whether the manager is installed.
        # Reference: https://stackoverflow.com/questions/17794507/reload-the-path-in-powershell
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        $PackageManager.IsInstalled = [bool] (Invoke-Command -ScriptBlock $PackageManager.CheckManagerInstalled)

        if (-not $PackageManager.IsInstalled)
        {
            Write-Error "Failed to install package manager: $($PackageManager.Name)"
        }
    }
}

#endregion

#region Collect Packages

$packagesToInstall = [ordered] @{}
$configuration.packages.psobject.Properties | ForEach-Object {
    $package = [ordered] @{
        packageId = $_.Name
    }
    $_.Value.psobject.Properties | ForEach-Object {
        $package[$_.Name] = $_.Value
    }
    return $package
}

function getPackage
{
    param (
        [Parameter(
            Position = 0,
            ValueFromPipeline
        )]
        [string[]]
        $Identifier
    )

    process
    {
        if (-not $Identifier)
        {
            return
        }

        $Identifier | ForEach-Object {
            $packageIdentifier = $_
            $package = $packagesToInstall | Where-Object packageId -EQ $packageIdentifier
            if (-not $package)
            {
                Write-Warning "A package identified by '$packageIdentifier' could not be found in the configuration."
            }

            return $package
        }
    }
}

$desiredPackages = $packagesToInstall

function installPackage
{
    param (
        [Parameter(
            Position = 0,
            ValueFromPipeline
        )]
        [object] $Package,

        [Parameter()]
        [ref] $Success,

        [Parameter()]
        [ref] $Abort
    )

    process
    {
        $packageIdentifier = $Package.packageId

        if ($installedPackages.ContainsKey($packageIdentifier))
        {
            Write-Verbose "Skipping $packageIdentifier because it has already been installed."
            return
        }

        if ($Success.Value)
        {
            # We already successfully installed this package.
            return
        }

        $managerId = $Package.source
        $packageManager = getPackageManager -id $managerId
        if (-not $packageManager)
        {
            # This package cannot be installed with this package manager.
            return
        }

        Write-Host "Installing $packageIdentifier"
        [ref] $installerExitCode = [InstallerExitCode]::Failure
        Invoke-Command $packageManager.InstallPackage -ArgumentList $Package, $installerExitCode

        switch ($installerExitCode.Value)
        {
            Success
            {
                $Success.Value = $true
                return
            }
            SuccessAbort
            {
                $Success.Value = $true
                $Abort.Value = $true
                return
            }
            FailureAbort
            {
                $Abort.Value = $true
                break
            }
        }
    }
}

#endregion

#region Build Installation Queue

# Using the desired packages, determine which package managers we need to make sure are installed.
# We want to ensure they are installed first if not already.
# If any package manager depends on a package from another,
# we need to install the package after its source manager but before its dependent manager.

# The queue contains the identifiers of the containers to install
# in the order in which we need to install them.
$installQueue = [System.Collections.ArrayList]::new()
$installContainers = @{}

$checkedManagers = [System.Collections.ArrayList]::new()
$enabledPackageManagers = [System.Collections.ArrayList]::new()

function enqueuePackage
{
    param (
        [Parameter(
            Position = 0,
            ValueFromPipeline
        )]
        [object]
        $Package
    )

    process
    {
        $packageIdentifier = $Package.packageId

        # If this package was already added to queue, skip it.
        # This can happen if this package is a dependency of an earlier package or manager.
        if ($packageIdentifier -in $installQueue)
        {
            return $true
        }

        # Add required package managers.
        $canBeInstalled = [ref] $false
        & {
            $managerId = $Package.source

            if ($managerId -in $installQueue)
            {
                $canBeInstalled.Value = $true
                return
            }

            if ($managerId -notin $checkedManagers)
            {
                # Mark this manager as checked so we don't warn about undefined managers more than once.
                [void] $checkedManagers.Add($managerId)

                $packageManager = getPackageManager -id $managerId
                if (-not $packageManager)
                {
                    Write-Warning "A package manager identified as '$managerId' is not defined."
                    return
                }

                if ($packageManager.RequiredPackages)
                {
                    $allRequirementsEnqueued = [ref] $true
                    $packageManager.RequiredPackages | ForEach-Object {
                        $requiredPackageId = $_
                        if ($requiredPackageId)
                        {
                            $requiredPackage = getPackage $requiredPackageId
                            if ($requiredPackage)
                            {
                                # TODO: Only enqueue if all required packages can be added. (Daniel Potter, 2020/08/19)
                                if (-not (enqueuePackage $requiredPackage))
                                {
                                    $allRequirementsEnqueued.Value = $false
                                }
                            }
                        }
                    }

                    if (-not $allRequirementsEnqueued.Value)
                    {
                        # Abort enqueuing this manager.
                        Write-Warning "$($packageIdentifier): Cannot install source package manager ($($packageManager.Name)) because it has a missing dependency."
                        return
                    }
                }

                [void] $installQueue.Add($managerId)
                $installContainers[$managerId] = @{
                    Id      = $managerId
                    Manager = $packageManager
                    Install = {
                        param ($self, $success, $abort)
                        installPackageManager $self.Manager
                        if ($self.Manager.IsInstalled)
                        {
                            $success.Value = $true
                        }
                        else
                        {
                            $abort.Value = $true
                        }
                    }
                }

                [void] $enabledPackageManagers.Add($managerId)
                $canBeInstalled.Value = $true
            }
        }

        if (-not $canBeInstalled.Value)
        {
            Write-Warning "$($packageIdentifier): Skipping package because it has no accessible package managers."
            return $false
        }

        [void] $installQueue.Add($packageIdentifier)
        $installContainers[$packageIdentifier] = @{
            Id = $packageIdentifier
            Package = $Package
            Install = {
                param ($self, $success, $abort)
                installPackage -Package $self.Package -Success $success -Abort $abort
            }
        }

        return $true
    }
}

$desiredPackages | ForEach-Object {
    enqueuePackage $_ | Out-Null
}

#endregion

#region Installation Progress Persistence

# Keep track of files that we have installed so that we can resume
# if one of the installs initiated a reboot.

$installationProgressPath = "$env:HOMEPATH\.WinConfig.json"

$installedPackageList = $null
if (Test-Path $installationProgressPath)
{
    $json = Get-Content $installationProgressPath | ConvertFrom-Json
    $installedPackageList = $json.Packages
}

if ($installedPackageList -isnot [array])
{
    $installedPackageList = @()
}

$installProgress = [PSCustomObject] @{
    Packages = $installedPackageList
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

#region Install from Queue

[ref] $abort = $false

$installQueue | ForEach-Object {
    if ($abort.Value)
    {
        return
    }

    $installIdentifier = $_
    $container = $installContainers[$_]

    if (-not $container)
    {
        Write-Error "Unknown install container: $installIdentifier"
        return
    }

    if ($installedPackages.ContainsKey($installIdentifier))
    {
        Write-Verbose "Skipping $installIdentifier because it has already been installed."
        return
    }

    [ref] $success = $false

    Invoke-Command -ScriptBlock $container.Install -ArgumentList $container, $success, $abort

    if ($success.Value)
    {
        $installedPackage = [PSCustomObject] @{
            Id = $installIdentifier
        }

        $installProgress.Packages += $installedPackage
        $installedPackages[$installIdentifier] = $installedPackage

        $installProgress | ConvertTo-Json | Set-Content $installationProgressPath
    }
    else
    {
        Write-Error "Failed to install package: $installIdentifier"
    }
}

if ($abort.Value)
{
    Write-Warning "Installation has aborted."
}

#endregion
