param([string]$Helper = "$PSScriptRoot\BlackBoxHelper.ps1", [switch]$IncludeLaunchAndMedia)
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Run this acceptance script on the selected Windows PC.' }
$Root = Join-Path $env:TEMP ('BlackBox-Test-' + [guid]::NewGuid().ToString())
$null = New-Item -ItemType Directory -Path $Root
function Call-Helper($Operation, $Arguments) {
    $Data = @{ version=1; operation=$Operation; arguments=$Arguments; roots=@($Root) } | ConvertTo-Json -Depth 8 -Compress
    $Encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Data))
    $Output = & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File $Helper -PayloadB64 $Encoded
    return ($Output | ConvertFrom-Json)
}
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message }; Write-Output ('PASS: ' + $Message) }
try {
    Assert ((Call-Helper 'capabilities' @{}).marker -eq 'BLACKBOX_HELPER_V1') 'Versioned capability handshake'
    $Folder = Join-Path $Root 'new'; Assert ((Call-Helper 'create_folder' @{path=$Folder}).exists) 'Create folder and observe it'
    Assert (-not (Call-Helper 'create_folder' @{path=$Folder}).ok) 'Existing folder never overwritten'
    $A = Join-Path $Root 'a.txt'; $B = Join-Path $Root 'b.txt'; Set-Content -LiteralPath $A -Value 'sample'
    $Moved = Call-Helper 'move_file' @{source=$A;destination=$B}; Assert ($Moved.sourceAbsent -and $Moved.destinationExists) 'Move file and observe both paths'
    Set-Content -LiteralPath $A -Value 'other'; Assert (-not (Call-Helper 'move_file' @{source=$A;destination=$B}).ok) 'Existing destination never overwritten'
    Assert (-not (Call-Helper 'validate_path' @{path=(Join-Path $Root '..\outside.txt')}).ok) 'Traversal rejected'
    $Metrics = Call-Helper 'inspect_resources' @{}
    Assert ($Metrics.totalPhysicalBytes -gt 0 -and $Metrics.observedAt -and @($Metrics.processes).Count -gt 0) 'Timestamped actual RAM and process measurements'
    if ($IncludeLaunchAndMedia) {
        Assert ((Call-Helper 'open_url' @{url='https://www.youtube.com'}).accepted) 'URL launch acknowledged (visually verify page)'
        Assert ((Call-Helper 'open_application' @{application='notepad'}).accepted) 'Application launch acknowledged (visually verify window)'
        Assert ((Call-Helper 'media_control' @{command='pause'}).accepted) 'Pause message acknowledged (verify player)'
    }
} finally { Remove-Item -LiteralPath $Root -Recurse -Force }
