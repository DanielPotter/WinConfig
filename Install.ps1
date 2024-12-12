[CmdletBinding()]
param (
    # The path to the install configuration.
    [Parameter()]
    [Alias("Config")]
    [string] $ConfigurationPath
)

$configurationPath = "Example.jsonc"
$installerPath = "Installer.ps1"
$gitHubPath = "https://raw.githubusercontent.com/DanielPotter/WinConfig/master"

$fullConfigPath = if ($ConfigurationPath) {
    $ConfigurationPath -replace '''', '`'''
} else { "$gitHubPath/$configurationPath" }

if ($PSScriptRoot)
{
    & "$PSScriptRoot\$installerPath" -PackageSet $packageSets -ConfigurationPath $PSScriptRoot\$configurationPath
}
else
{
    $webClient = New-Object System.Net.WebClient
    $installer = $webClient.DownloadString("$gitHubPath/$installerPath")
    Invoke-Expression "& { $installer } -ConfigurationPath '$fullConfigPath'"
}
