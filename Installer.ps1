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
    [string[]]
    $ConfigurationPath
)

[ref] $webClient = $null

#region Configuration Classes

class Configuration
{
    [string[]] $SourcePreference
    [PackageSet[]] $PackageSets
    [PackageDefinition[]] $Packages

    [void] Add([Configuration] $other)
    {
        $this.SourcePreference = $this.SourcePreference, $other.SourcePreference | Select-Object -Unique

        $setsToMerge = [System.Collections.ArrayList]::new($other.PackageSets)
        $this.PackageSets | ForEach-Object {
            $currentSet = $_
            for ($index = 0; $index -lt $setsToMerge.Count; $index++)
            {
                $otherSet = $setsToMerge[$index]
                if ($otherSet.name -eq $currentSet.name)
                {
                    $currentSet.Add($otherSet)
                    $setsToMerge.RemoveAt($index)
                    break
                }
            }
        }

        if ($setsToMerge.Count)
        {
            $this.PackageSets += $setsToMerge
        }

        $packagesToMerge = [System.Collections.ArrayList]::new($other.Packages)
        $this.Packages | ForEach-Object {
            $currentPackage = $_
            for ($index = 0; $index -lt $packagesToMerge.Count; $index++)
            {
                $otherPackage = $packagesToMerge[$index]
                if ($otherPackage.name -eq $currentPackage.name)
                {
                    $currentPackage.Add($otherPackage)
                    $packagesToMerge.RemoveAt($index)
                    break
                }
            }
        }

        if ($packagesToMerge.Count)
        {
            $this.Packages += $packagesToMerge
        }
    }
}

class PackageSet
{
    [string] $Name
    [string] $Description
    [string[]] $Packages

    [void] Add([PackageSet] $other)
    {
        if (-not $this.Description)
        {
            $this.Description = $other.Description
        }

        $this.Packages = $this.Packages, $other.Packages | Select-Object -Unique
    }
}

class PackageDefinition : PackageInstallSettings
{
    [string] $PackageId
    [string] $Description
    [PackageSourceDefinition[]] $Sources

    [void] Add([PackageDefinition] $other)
    {
        ([PackageInstallSettings] $this).Add($other)

        $this.Sources = $this.Sources, $other.Sources | Select-Object -Unique
    }
}

class PackageInstallSettings
{
    [string[]] $Parameters

    [void] Add([PackageInstallSettings] $other)
    {
        $this.Parameters = $this.Parameters, $other.Parameters | Select-Object -Unique
    }
}

class PackageSourceDefinition : PackageInstallSettings
{
    [string] $Id
}

class GitPackageSourceDefinition : PackageSourceDefinition
{
    [string] $Destination
}

#endregion

#region Configuration

# Get the content of the configuration files that define the packages.
$configuration = [Configuration]::new()

# Parse the path so that we know whether it refers to web content or a file on disk.
$ConfigurationPath | ForEach-Object {
    $configPath = $_
    $configUri = [uri] $configPath

    switch ($configUri.Scheme)
    {
        file
        {
            $configContent = Get-Content $configPath
            if (-not $configContent)
            {
                Write-Error "Failed to read configuration from $configPath."
                return
            }
            break
        }
        { $_ -in "http", "https" }
        {
            $webClient.Value = New-Object Net.WebClient
            $configContent = $webClient.Value.DownloadString($configPath)
            if (-not $configContent)
            {
                Write-Error "Failed to download configuration from $configPath."
                return
            }
            break
        }
        Default
        {
            Write-Error "Malformed uri: $configPath"
            return
        }
    }

    [Configuration] $newConfiguration = $configContent | ConvertFrom-Json
    if (-not $newConfiguration)
    {
        Write-Error "Failed to parse configuration from $configPath."
        return
    }

    $configuration.Add($newConfiguration)
}

if (-not $configuration.Packages)
{
    Write-Error "Failed to parse packages from configuration."
    return
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
            $destination = $package.Sources.Git.Destination
            if (-not $destination)
            {
                Write-Error "$($package.PackageId): No destination was provided."
                $installerExitCode.Value = [InstallerExitCode]::Failure
                return
            }

            $destination = $destination -replace '\${HOME}', $HOME

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
                $package.Sources.Git.Id
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
        Id                    = "WinGet"
        Name                  = "WinGet"
        RequiresWebClient     = $true
        CheckManagerInstalled = {
            # WinGet is considered to be installed if winget.exe is on the path.
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

function isPermittedPackageManager ($id)
{
    if ($configuration.sourcePreference)
    {
        return $id -in $configuration.sourcePreference
    }

    return $true
}

function selectPermittedPackageManager ([string[]] $id)
{
    if ($configuration.sourcePreference)
    {
        # If preferences are specified, select only the package managers that we actually need.
        return $configuration.sourcePreference | Where-Object {
            $_ -in $id
        }
    }
    else
    {
        # Otherwise, use all package managers.
        return $id
    }
}

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
        [object]
        $PackageManager
    )

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

#endregion

#region Collect Packages

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
            $package = $configuration.packages | Where-Object packageId -EQ $packageIdentifier
            if (-not $package)
            {
                Write-Warning "A package identified by '$packageIdentifier' could not be found in the configuration."
            }
        
            return $package
        }
    }
}

$desiredPackageIdentifiers = $(
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
) | Select-Object -Unique

$desiredPackages = getPackage $desiredPackageIdentifiers

function installPackage
{
    param (
        [Parameter(
            Position = 0,
            ValueFromPipeline
        )]
        [object]
        $Package,

        [Parameter()]
        [string[]]
        $PackageManager,

        [Parameter()]
        [ref]
        $Success,

        [Parameter()]
        [ref]
        $Abort
    )

    process
    {
        $packageIdentifier = $Package.packageId

        if ($installedPackages.ContainsKey($packageIdentifier))
        {
            Write-Verbose "Skipping $packageIdentifier because it has already been installed."
            return
        }

        $PackageManager | ForEach-Object {
            if ($Success.Value)
            {
                # We already successfully installed this package.
                return
            }

            $managerId = $_
            $manager = getPackageManager -id $managerId

            $packageManager = $Package.sources.$managerId
            if (-not $packageManager)
            {
                # This package cannot be installed with this package manager.
                return
            }

            Write-Host "Installing $packageIdentifier"
            [ref] $installerExitCode = [InstallerExitCode]::Failure
            Invoke-Command $manager.InstallPackage -ArgumentList $Package, $installerExitCode

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

    $packageIdentifier = $Package.packageId

    # If this package was already added to queue skip it.
    # This can happen if this package is a dependency of an earlier package or manager.
    if ($packageIdentifier -in $installQueue)
    {
        return $true
    }

    $sourceNames = $Package.sources | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

    # Add required package managers.
    $canBeInstalled = [ref] $false
    $sourceNames | ForEach-Object {
        $managerId = $_

        if ($managerId -in $installQueue)
        {
            $canBeInstalled.Value = $true
            return
        }

        if (-not (isPermittedPackageManager -id $managerId))
        {
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
            # $preferredPackageManagers will be available by the time this script block executes.
            installPackage -Package $self.Package -PackageManager $preferredPackageManagers -Success $success -Abort $abort
        }
    }

    return $true
}

$desiredPackages | ForEach-Object {
    enqueuePackage $_ | Out-Null
}

$preferredPackageManagers = selectPermittedPackageManager $enabledPackageManagers

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
