# WinConfig

Scripts to configure my Windows machines.

## Installation

In an administrative PowerShell shell, execute the following script.

Please inspect <https://raw.githubusercontent.com/DanielPotter/WinConfig/master/Install.ps1> before executing.

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/DanielPotter/WinConfig/master/Install.ps1'))
```
