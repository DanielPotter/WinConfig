[CmdletBinding()]
param (
    # Install all applications.
    [Parameter()]
    [switch]
    $All,

    # Allow the use of WinGet.
    [Parameter()]
    [switch]
    $WinGet
)

$applications = @(
    # These are ordered dictionaries so that the applications are installed
    # using the same order of package managers.

    # Applications I use all the time and want on all machines.
    [ordered] @{
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
    [ordered] @{
        WinGet = @{
            Id = 'Microsoft.PowerShell'
        }
        Choco  = @{
            Id = 'powershell-core'
        }
    }
    [ordered] @{
        WinGet = @{
            Id = 'Microsoft.Edge'
        }
        Choco  = @{
            Id = 'microsoft-edge'
        }
    }
    [ordered] @{
        WinGet     = @{
            Id = 'Microsoft.VisualStudioCode'
        }
        Choco      = @{
            Id = 'vscode'
        }
        Parameters = @(
            '/NoDesktopIcon'
            '/NoQuicklaunchIcon'
        )
    }
    [ordered] @{
        WinGet     = @{
            Id = 'Microsoft.VisualStudio.Community'
        }
        Choco      = @{
            Id = 'visualstudio2019community'
        }
        Parameters = @(
            '--add Microsoft.VisualStudio.Workload.ManagedDesktop;includeRecommended'
            '--add Microsoft.VisualStudio.Workload.NetCrossPlat;includeRecommended'
            '--add Microsoft.VisualStudio.Workload.Universal;includeRecommended'
        )
    }
    [ordered] @{
        WinGet         = @{
            Id = 'File-New-Project.EarTrumpet'
        }
        MicrosoftStore = @{
            Id = '9NBLGGH516XP'
        }
    }
    [ordered] @{
        WinGet     = @{
            Id = 'voidtools.Everything'
        }
        Choco      = @{
            Id = 'everything'
        }
        Parameters = @(
            '/client-service'
            '/run-on-system-startup'
            '/start-menu-shortcuts'
        )
    }
    [ordered] @{
        AppId          = 'QuickLook'
        MicrosoftStore = @{
            Id = '9NV4BS3L1H4S'
        }
    }
    [ordered] @{
        AppId          = 'MyTubeBeta'
        MicrosoftStore = @{
            Id = '9WZDNCRDT29J'
        }
    }
    [ordered] @{
        WinGet     = @{
            Id = 'Git.Git'
        }
        Choco      = @{
            Id = 'git'
        }
        Parameters = @(
            '/GitOnlyOnPath'
            '/NoShellIntegration'
        )
    }
    [ordered] @{
        WinGet = @{
            Id = 'GitExtensionsTeam.GitExtensions'
        }
        Choco  = @{
            Id = 'gitextensions'
        }
    }
    [ordered] @{
        WinGet = @{
            Id = 'JoachimEibl.KDiff3'
        }
        Choco  = @{
            Id = 'kdiff3'
        }
    }

    # Applications I don't use as often but still want installed.
    [ordered] @{
        WinGet = @{
            Id = 'Valve.Steam'
        }
        Choco  = @{
            Id = 'steam'
        }
    }
    [ordered] @{
        WinGet = @{
            Id = 'Discord.Discord'
        }
        Choco  = @{
            Id = 'discord'
        }
    }
    [ordered] @{
        WinGet = @{
            Id = 'VideoLAN.VLC'
        }
        Choco  = @{
            Id = 'vlc'
        }
    }
    [ordered] @{
        WinGet = @{
            Id = 'TGRMNSoftware.BulkRenameUtility'
        }
        Choco  = @{
            Id = 'bulkrenameutility'
        }
    }
    [ordered] @{
        # WinDirStat is a disk usage statistics viewer and cleanup tool for various versions of Microsoft Windows.
        WinGet = @{
            Id = 'WinDirStat.WinDirStat'
        }
        Choco  = @{
            Id = 'windirstat'
        }
    }

    # Applications I don't use often enough to install right away.
    [ordered] @{
        Enabled = $All.IsPresent
        WinGet  = @{
            Id = 'Audacity.Audacity'
        }
        Choco   = @{
            Id = 'audacity'
        }
    }
    [ordered] @{
        Enabled = $All.IsPresent
        WinGet  = @{
            Id = 'GIMP.GIMP'
        }
        Choco   = @{
            Id = 'gimp'
        }
    }
    [ordered] @{
        # A utility that helps format and create bootable USB flash drives.
        Enabled = $All.IsPresent
        WinGet  = @{
            Id = 'Rufus.Rufus'
        }
        Choco   = @{
            Id = 'rufus'
        }
    }
)

#region Install Package Managers

enum InstallCode
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
            $appInstallerUrl = 'https://github.com/microsoft/winget-cli/releases/download/v0.1.41821-preview/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appxbundle'
            $appInstallerPath = "$env:HOMEPATH\Downloads\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appxbundle"
            $webClient.DownloadFile($appInstallerUrl, $appInstallerPath)
            Add-AppxPackage -Path $appInstallerPath
        }
        InstallPackage    = {
            param ($package)

            $arguments = @(
                'install'
                '--id'
                $package.WinGet.Id
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
                    return [InstallCode]::Success
                }
                Default
                {
                    # An error occurred.
                    return [InstallCode]::Failure
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
            param ($package)

            $arguments = @(
                'install'
                $package.Choco.Id
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
                    return [InstallCode]::Success
                }
                350
                {
                    # Pending reboot detected, no action has occurred.
                    Write-Warning "A reboot is pending. Please execute this script again to install."
                    return [InstallCode]::Skipped
                }
                1604
                {
                    # Install suspended, incomplete.
                    Write-Warning "The install has been canceled."
                    return [InstallCode]::Skipped
                }
                1641
                {
                    # Success, reboot initiated.
                    Write-Warning "A reboot has been initiated. Please execute this script again to continue."
                    return [InstallCode]::SuccessAbort
                }
                3010
                {
                    # Success, reboot required.
                    return [InstallCode]::Success
                }
                Default
                {
                    # An error has occurred.
                    return [InstallCode]::Failure
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
            param ($package)

            Start-Process "ms-windows-store://pdp/?ProductId=$($package.MicrosoftStore.Id)"
            Write-Host "Please install the app from the store before continuing."
            Pause

            return [InstallCode]::Success
        }
    }
}

[ref] $webClient = $null

# Install package managers that will actually be used.
$applications.Keys | Select-Object -Unique | ForEach-Object {
    # Get the package manager definition.

    if ($packageManagers.$_)
    {
        return $packageManagers.$_
    }
} | ForEach-Object {
    # Install the package manager if not already installed.
    $packageManager = $_

    Write-Debug "Testing status of package manager: $($packageManager.Name)"

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

    if ($packageManager.RequiresWebClient -and -not $webClient.Value)
    {
        $webClient.Value = New-Object Net.WebClient
    }

    & $packageManager.InstallManager $webClient.Value

    # Reload the path variable.
    # Reference: https://stackoverflow.com/questions/17794507/reload-the-path-in-powershell
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    $packageManager.IsInstalled = [bool] (& $packageManager.CheckInstall)

    if (-not $packageManager.IsInstalled)
    {
        Write-Error "Failed to install package manager: $($packageManager.Name)"
    }
}

#endregion

#region Install Progress

$installProgressPath = "$env:HOMEPATH\.WinConfig.json"

$installedPackages = $null
if (Test-Path $installProgressPath)
{
    $json = Get-Content $installProgressPath | ConvertFrom-Json
    $installedPackages = $json.Packages
}

if ($installedPackages -isnot [array])
{
    $installedPackages = @()
}

$installProgress = [PSCustomObject] @{
    Packages = $installedPackages
}

$installedApps = @{}
$installProgress.Packages | ForEach-Object {
    if ($_)
    {
        $installedApps[$_.Id] = $_
    }
}

#endregion

#region Install

[ref] $abort = $false

$applications | ForEach-Object {
    if ($abort.Value)
    {
        return
    }

    $package = $_

    if ($package.Id)
    {
        $appId = $package.Id
    }
    elseif ($package.WinGet.Id)
    {
        $appId = $package.WinGet.Id
    }
    else
    {
        Write-Verbose "Skipping entry because it is missing an ID."
        return
    }

    if ($installedApps.ContainsKey($appId))
    {
        Write-Verbose "Skipping $appId because it has already been installed."
        return
    }

    [ref] $success = $false

    $package.Keys | ForEach-Object {
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

        Write-Host "Installing $appId"
        $installCode = & $packageManagers.$managerName.InstallPackage $package

        switch ($installCode)
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
        $installedApp = [PSCustomObject] @{
            Id = $appId
        }

        $installProgress.Packages += $installedApp
        $installedApps[$appId] = $installedApp

        $installProgress | ConvertTo-Json | Set-Content $installProgressPath
    }
    else
    {
        Write-Error "Failed to install $appId"
    }
}

#endregion
