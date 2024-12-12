[CmdletBinding()]
param (
    # The path to the install configuration.
    [Parameter()]
    [Alias("Config")]
    [string] $ConfigurationPath
)

$exampleConfigurationPath = "Example.jsonc"
$installerPath = "Installer.ps1"
$gitHubPath = "https://raw.githubusercontent.com/DanielPotter/WinConfig/master"

$fullConfigPath = if ($ConfigurationPath)
{
    $ConfigurationPath -replace '''', '`'''
}
elseif ($PSScriptRoot)
{
    "$PSScriptRoot\$exampleConfigurationPath"
}
else
{
    "$gitHubPath/$exampleConfigurationPath"
}

if ($PSScriptRoot)
{
    & "$PSScriptRoot\$installerPath" -ConfigurationPath $fullConfigPath
}
else
{
    $webClient = New-Object System.Net.WebClient
    $installer = $webClient.DownloadString("$gitHubPath/$installerPath")
    Invoke-Expression "& { $installer } -ConfigurationPath '$fullConfigPath'"
}
