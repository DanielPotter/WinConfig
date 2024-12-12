# WinConfig

Scripts to configure my Windows machines.

## Installation

In a PowerShell session with administrative privileges, execute the following script.

Please inspect <https://raw.githubusercontent.com/DanielPotter/WinConfig/master/Install.ps1> so that you know what you are about to execute.

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex "& { $((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/DanielPotter/WinConfig/master/Install.ps1')) } -Config https://raw.githubusercontent.com/DanielPotter/WinConfig/master/Example.jsonc -Verbose"
```
