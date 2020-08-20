[CmdletBinding()]
param ()

$definitionsPath = "Definitions.json"
$configurationPath = "Configuration.json"
$installerPath = "Installer.ps1"
$gitHubPath = "https://raw.githubusercontent.com/DanielPotter/WinConfig/master"
$packageSets = @(
    "common"
    "development"
    "games"
    "utilities"
)

if ($PSScriptRoot)
{
    & "$PSScriptRoot\$installerPath" -PackageSet $packageSets -ConfigurationPath $PSScriptRoot\$definitionsPath, $PSScriptRoot\$configurationPath
}
else
{
    $webClient = New-Object System.Net.WebClient
    $installer = $webClient.DownloadString("$gitHubPath/$installerPath")
    Invoke-Expression "& { $installer } -PackageSet $($packageSets -join ', ') -ConfigurationPath '$gitHubPath/$definitionsPath', '$gitHubPath/$configurationPath'"
}
