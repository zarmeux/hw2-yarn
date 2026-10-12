param(
    [string]$KeyPath = '',
    [string]$Edge = '111.88.130.214',
    [string]$User = 'team',
    [string]$KnownHostsFile = ''
)
$ErrorActionPreference = 'Stop'
$uiPorts = @(18088,19870,19868,19889,19864,19865,19866,18042,18043,18044)
$sshArgs = @('-N','-o','StrictHostKeyChecking=yes','-o','ExitOnForwardFailure=yes',
             '-o','ServerAliveInterval=30','-o','ServerAliveCountMax=3')
if ($KeyPath) { $sshArgs += @('-i',(Resolve-Path -LiteralPath $KeyPath).Path,'-o','IdentitiesOnly=yes') }
if ($KnownHostsFile) { $sshArgs += @('-o',"UserKnownHostsFile=$KnownHostsFile",'-o','StrictHostKeyChecking=yes') }
foreach ($uiPort in $uiPorts) { $sshArgs += @('-L',"127.0.0.1:${uiPort}:127.0.0.1:${uiPort}") }
Write-Host 'Open http://127.0.0.1:18088 (YARN), http://127.0.0.1:19870 (HDFS), http://127.0.0.1:19889 (JobHistory).'
Write-Host 'Keep this terminal open; Ctrl+C closes the tunnel.'
& ssh @sshArgs "$User@$Edge"
if ($LASTEXITCODE -ne 0) { throw "SSH exited with code $LASTEXITCODE" }
