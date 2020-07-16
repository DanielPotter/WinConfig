[CmdletBinding()]
param (
    # Install all packages.
    [Parameter()]
    [switch]
    $All,

    # Allow the use of WinGet.
    [Parameter()]
    [switch]
    $WinGet
)

$packages = @(
    # Applications I use all the time and want on all machines.
    @{
        PackageId = 'Microsoft.WindowsTerminal'
        Sources   = [ordered] @{
            # We will attempt to install using this order.  If one fails, try the next.
            MicrosoftStore = @{
                Id = '9N0DX20HK701'
            }
            WinGet         = @{
                Id = 'Microsoft.WindowsTerminal'
            }
            Choco          = @{
                Id = 'microsoft-windows-terminal'
            }
        }
    }
    @{
        PackageId = 'Microsoft.PowerShell'
        Sources   = [ordered] @{
            WinGet = @{
                Id = 'Microsoft.PowerShell'
            }
            Choco  = @{
                Id = 'powershell-core'
            }
        }
    }
    @{
        PackageId = 'Microsoft.Edge'
        Sources   = [ordered] @{
            WinGet = @{
                Id = 'Microsoft.Edge'
            }
            Choco  = @{
                Id = 'microsoft-edge'
            }
        }
    }
    @{
        PackageId  = 'Microsoft.VisualStudioCode'
        Sources    = [ordered] @{
            WinGet = @{
                Id = 'Microsoft.VisualStudioCode'
            }
            Choco  = @{
                Id = 'vscode'
            }
        }
        Parameters = @(
            '/NoDesktopIcon'
            '/NoQuicklaunchIcon'
        )
    }
    @{
        PackageId  = 'Microsoft.VisualStudio.Community'
        Sources    = [ordered] @{
            WinGet = @{
                Id = 'Microsoft.VisualStudio.Community'
            }
            Choco  = @{
                Id = 'visualstudio2019community'
            }
        }
        Parameters = @(
            '--add Microsoft.VisualStudio.Workload.ManagedDesktop;includeRecommended'
            '--add Microsoft.VisualStudio.Workload.NetCrossPlat;includeRecommended'
            '--add Microsoft.VisualStudio.Workload.Universal;includeRecommended'
        )
    }
    @{
        # A modern volume mixer for Windows.
        PackageId = 'File-New-Project.EarTrumpet'
        Sources   = [ordered] @{
            MicrosoftStore = @{
                Id = '9NBLGGH516XP'
            }
            WinGet         = @{
                Id = 'File-New-Project.EarTrumpet'
            }
        }
    }
    @{
        # A tool for locating files and folders.
        PackageId  = 'voidtools.Everything'
        Sources    = [ordered] @{
            WinGet = @{
                Id = 'voidtools.Everything'
            }
            Choco  = @{
                Id = 'everything'
            }
        }
        Parameters = @(
            '/client-service'
            '/run-on-system-startup'
            '/start-menu-shortcuts'
        )
    }
    @{
        # Enables a quick preview of file contents by pressing the Spacebar.
        PackageId = 'PaddyXu.QuickLook'
        Sources   = [ordered] @{
            MicrosoftStore = @{
                Id = '9NV4BS3L1H4S'
            }
        }
    }
    @{
        # The best YouTube experience around.
        PackageId = 'RykenStudio.MyTubeBeta'
        Sources   = [ordered] @{
            MicrosoftStore = @{
                Id = '9WZDNCRDT29J'
            }
        }
    }
    @{
        PackageId  = 'Git.Git'
        Sources    = [ordered] @{
            WinGet = @{
                Id = 'Git.Git'
            }
            Choco  = @{
                Id = 'git'
            }
        }
        Parameters = @(
            '/GitOnlyOnPath'
            '/NoShellIntegration'
        )
    }
    @{
        PackageId = 'GitExtensionsTeam.GitExtensions'
        Sources   = [ordered] @{
            WinGet = @{
                Id = 'GitExtensionsTeam.GitExtensions'
            }
            Choco  = @{
                Id = 'gitextensions'
            }
        }
    }
    @{
        PackageId = 'JoachimEibl.KDiff3'
        Sources   = [ordered] @{
            WinGet = @{
                Id = 'JoachimEibl.KDiff3'
            }
            Choco  = @{
                Id = 'kdiff3'
            }
        }
    }

    # Applications I don't use as often but still want installed.
    @{
        PackageId = 'Valve.Steam'
        Sources   = [ordered] @{
            WinGet = @{
                Id = 'Valve.Steam'
            }
            Choco  = @{
                Id = 'steam'
            }
        }
    }
    @{
        PackageId = 'Discord.Discord'
        Sources   = [ordered] @{
            WinGet = @{
                Id = 'Discord.Discord'
            }
            Choco  = @{
                Id = 'discord'
            }
        }
    }
    @{
        PackageId = 'VideoLAN.VLC'
        Sources   = [ordered] @{
            WinGet = @{
                Id = 'VideoLAN.VLC'
            }
            Choco  = @{
                Id = 'vlc'
            }
        }
    }
    @{
        PackageId = 'TGRMNSoftware.BulkRenameUtility'
        Sources   = [ordered] @{
            WinGet = @{
                Id = 'TGRMNSoftware.BulkRenameUtility'
            }
            Choco  = @{
                Id = 'bulkrenameutility'
            }
        }
    }
    @{
        # WinDirStat is a disk usage statistics viewer and cleanup tool for various versions of Microsoft Windows.
        PackageId = 'WinDirStat.WinDirStat'
        Sources   = [ordered] @{
            WinGet = @{
                Id = 'WinDirStat.WinDirStat'
            }
            Choco  = @{
                Id = 'windirstat'
            }
        }
    }

    # Applications I don't use often enough to install right away.
    @{
        PackageId = 'Audacity.Audacity'
        Enabled   = $All.IsPresent
        Sources   = [ordered] @{
            WinGet = @{
                Id = 'Audacity.Audacity'
            }
            Choco  = @{
                Id = 'audacity'
            }
        }
    }
    @{
        PackageId = 'GIMP.GIMP'
        Enabled   = $All.IsPresent
        Sources   = [ordered] @{
            WinGet = @{
                Id = 'GIMP.GIMP'
            }
            Choco  = @{
                Id = 'gimp'
            }
        }
    }
    @{
        # A utility that helps format and create bootable USB flash drives.
        PackageId = 'Rufus.Rufus'
        Enabled   = $All.IsPresent
        Sources   = [ordered] @{
            WinGet = @{
                Id = 'Rufus.Rufus'
            }
            Choco  = @{
                Id = 'rufus'
            }
        }
    }
)

#region Install Package Managers

enum InstallerExitCode
{
    Success
    Skipped
    Failure
    SuccessAbort
    FailureAbort
}

# Define the package managers.
$packageManagers = @{
    WinGet         = @{
        Name              = "WinGet"
        Enabled           = $WinGet.IsPresent
        RequiresWebClient = $true
        CheckInstall      = {
            Get-Command winget -ErrorAction SilentlyContinue
        }
        InstallManager    = {
            param ($webClient)
            Write-Verbose "Installing WinGet"
            $downloadSource = 'https://github.com/microsoft/winget-cli/releases/download/v0.1.41821-preview/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appxbundle'
            $downloadDestination = "$env:HOMEPATH\Downloads\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appxbundle"
            $webClient.DownloadFile($downloadSource, $downloadDestination)
            Add-AppxPackage -Path $downloadDestination
        }
        InstallPackage    = {
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
    Choco          = @{
        Name              = "Chocolatey"
        Enabled           = $true
        RequiresWebClient = $true
        CheckInstall      = {
            Get-Command choco -ErrorAction SilentlyContinue
        }
        InstallManager    = {
            param ($webClient)
            Write-Verbose "Installing Chocolatey"
            Invoke-Expression ($webClient.DownloadString('https://chocolatey.org/install.ps1'))
        }
        InstallPackage    = {
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
    MicrosoftStore = @{
        Name              = 'Microsoft Store'
        Enabled           = $true
        RequiresWebClient = $false
        CheckInstall      = {
            return $true
        }
        InstallManager    = {
            param ($webClient)
        }
        InstallPackage    = {
            param ($package, $installerExitCode)

            # This install is manual because it is very difficult and fragile to automate
            # app installation from the Microsoft Store.
            Start-Process "ms-windows-store://pdp/?ProductId=$($package.MicrosoftStore.Id)"
            Write-Host "Please install the app from the store before continuing."
            Pause

            $installerExitCode.Value = [InstallerExitCode]::Success
        }
    }
}

[ref] $webClient = $null

# Install package managers that will actually be used.
$packages.Sources.Keys | Select-Object -Unique | ForEach-Object {
    # Get the package manager definition.

    if ($packageManagers.$_)
    {
        return $packageManagers.$_
    }
    else
    {
        Write-Warning "A package with the name '$_' is not defined."
    }
} | ForEach-Object {
    # Install the package manager if not already installed.
    $packageManager = $_

    if ($packageManager.IsInstalled)
    {
        return
    }

    if (& $packageManager.CheckInstall)
    {
        $packageManager.IsInstalled = $true
        return
    }

    if (-not $packageManager.Enabled)
    {
        Write-Verbose "Skipping installation of $($packageManager.Name) because it is not enabled."
        return
    }

    Write-Debug "Testing installation status of package manager: $($packageManager.Name)"

    if ($packageManager.RequiresWebClient -and -not $webClient.Value)
    {
        $webClient.Value = New-Object Net.WebClient
    }

    & $packageManager.InstallManager $webClient.Value

    # Reload the path variable in case the package manager was not added to the path of the current session.
    # Reference: https://stackoverflow.com/questions/17794507/reload-the-path-in-powershell
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    $packageManager.IsInstalled = [bool] (& $packageManager.CheckInstall)

    if (-not $packageManager.IsInstalled)
    {
        Write-Error "Failed to install package manager: $($packageManager.Name)"
    }
}

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

$installedPackages = @{}
$installProgress.Packages | ForEach-Object {
    if ($_.Id)
    {
        $installedPackages[$_.Id] = $_
    }
}

#endregion

#region Install

[ref] $abort = $false

$packages | ForEach-Object {
    if ($abort.Value)
    {
        return
    }

    $package = $_

    if ($package.PackageId)
    {
        $packageId = $package.PackageId
    }
    else
    {
        Write-Verbose "Skipping entry because it is missing an ID."
        return
    }

    if ($installedPackages.ContainsKey($packageId))
    {
        Write-Verbose "Skipping $packageId because it has already been installed."
        return
    }

    [ref] $success = $false

    $package.Sources.Keys | ForEach-Object {
        if ($success.Value)
        {
            # We already successfully installed this package.
            return
        }

        $managerName = $_

        if (-not $packageManagers.$managerName)
        {
            # This is not a defined package manager.
            return
        }

        if (-not $packageManagers.$managerName.Enabled)
        {
            return
        }

        Write-Host "Installing $packageId"
        [ref] $installerExitCode = [InstallerExitCode]::Failure
        & $packageManagers.$managerName.InstallPackage $package $installerExitCode

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
            Id = $packageId
        }

        $installProgress.Packages += $installedPackage
        $installedPackages[$packageId] = $installedPackage

        $installProgress | ConvertTo-Json | Set-Content $installationProgressPath
    }
    else
    {
        Write-Error "Failed to install $packageId"
    }
}

#endregion
