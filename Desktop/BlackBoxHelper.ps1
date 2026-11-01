param([Parameter(Mandatory=$true)][string]$PayloadB64)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Out-Result($Object) { $Object | ConvertTo-Json -Depth 10 -Compress }
function Assert-Path([string]$Path, [bool]$MayNotExist = $false) {
    if ($Path -notmatch '^[a-zA-Z]:\\' -or $Path.Substring(2).Contains(':') -or $Path -match '[*?"''\x00-\x1f]' -or $Path -match '\\(\.|\.\.)(\\|$)' -or $Path -match '[. ](\\|$)') { throw 'Unsafe or ambiguous Windows path.' }
    $Full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $Allowed = $false
    foreach ($Root in @($script:Payload.roots)) {
        $CanonicalRoot = [IO.Path]::GetFullPath([string]$Root).TrimEnd('\')
        if ($Full.Equals($CanonicalRoot, [StringComparison]::OrdinalIgnoreCase) -or $Full.StartsWith($CanonicalRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { $Allowed = $true }
    }
    if (-not $Allowed) { throw 'Path outside configured roots.' }
    # Refuse junction/symlink components; lexical containment alone is insufficient.
    $Current = $Full
    while ($Current -and $Current.Length -ge 3) {
        if (Test-Path -LiteralPath $Current) {
            $Item = Get-Item -LiteralPath $Current -Force
            if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse points are excluded.' }
        }
        $Parent = [IO.Path]::GetDirectoryName($Current)
        if ($Parent -eq $Current) { break }; $Current = $Parent
    }
    if (-not $MayNotExist -and -not (Test-Path -LiteralPath $Full)) { throw 'Path not found.' }
    return $Full
}
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
    if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'PowerShell 5 or later is required.' }
    $script:Payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PayloadB64)) | ConvertFrom-Json
    if ($Payload.version -ne 1) { throw 'Unsupported helper protocol.' }
    $A = $Payload.arguments
    $Result = @{ ok = $true; marker = 'BLACKBOX_HELPER_V1'; observedAt = [DateTime]::UtcNow.ToString('o'); operation = $Payload.operation }
    switch ($Payload.operation) {
        'capabilities' {
            $Result.os = 'Windows'; $Result.osVersion = [Environment]::OSVersion.Version.ToString(); $Result.runtime = 'PowerShell ' + $PSVersionTable.PSVersion.ToString()
            $Result.supported = @('open_url','open_alias','open_path','open_application','inspect_resources','media_control','create_folder','move_file','validate_path')
            $Result.evidence = 'Capability handshake only; action acceptance tests are separate.'
        }
        'validate_path' { $Result.path = Assert-Path ([string]$A.path); $Result.evidence = 'Path containment and reparse-point check passed.' }
        'open_url' {
            $Uri = $null
            if (-not [Uri]::TryCreate([string]$A.url, [UriKind]::Absolute, [ref]$Uri) -or $Uri.Scheme -notin @('http','https') -or $Uri.UserInfo) { throw 'Only HTTP(S) URLs without credentials are allowed.' }
            Start-Process -FilePath $Uri.AbsoluteUri
            $Result.accepted = $true; $Result.url = $Uri.AbsoluteUri; $Result.evidence = 'Windows accepted URL launch. Page load/content was not observed.'
        }
        { $_ -in @('open_alias','open_path') } {
            $Path = Assert-Path ([string]$A.path)
            if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
                if ([IO.Path]::GetExtension($Path).ToLowerInvariant() -notin @('.txt','.md','.pdf','.docx','.xlsx','.csv','.png','.jpg','.jpeg','.mp3','.mp4')) { throw 'File launch type is not allowlisted.' }
            }
            Start-Process -FilePath $Path
            $Result.accepted = $true; $Result.path = $Path; $Result.evidence = 'Windows accepted path launch; foreground application not inspected.'
        }
        'open_application' {
            $Apps = @{ notepad='notepad.exe'; calculator='calc.exe'; explorer='explorer.exe'; chrome='chrome.exe'; edge='msedge.exe' }
            $Name = ([string]$A.application).ToLowerInvariant()
            if (-not $Apps.ContainsKey($Name)) { throw 'Application is not allowlisted.' }
            Start-Process -FilePath $Apps[$Name]
            $Result.accepted = $true; $Result.application = $Name; $Result.evidence = 'Windows accepted application launch; window state not inspected.'
        }
        'inspect_resources' {
            $OS = Get-CimInstance Win32_OperatingSystem
            $Total = [long]$OS.TotalVisibleMemorySize * 1024; $Free = [long]$OS.FreePhysicalMemory * 1024
            $Before = @{}; foreach ($P in Get-Process) { try { $Before[$P.Id] = $P.TotalProcessorTime.TotalSeconds } catch {} }
            $Watch = [Diagnostics.Stopwatch]::StartNew(); Start-Sleep -Milliseconds 250
            $Processes = foreach ($P in Get-Process) {
                try {
                    $Cpu = $null
                    if ($Before.ContainsKey($P.Id)) { $Cpu = [Math]::Round(100 * ($P.TotalProcessorTime.TotalSeconds - $Before[$P.Id]) / $Watch.Elapsed.TotalSeconds / [Environment]::ProcessorCount, 2) }
                    @{ pid=$P.Id; name=$P.ProcessName; workingSetBytes=[long]$P.WorkingSet64; privateBytes=[long]$P.PrivateMemorySize64; sampledCPUPercent=$Cpu }
                } catch {}
            }
            $Result.observedAt = [DateTime]::UtcNow.ToString('o'); $Result.sampleWindowSeconds = $Watch.Elapsed.TotalSeconds
            $Result.totalPhysicalBytes = $Total; $Result.freePhysicalBytes = $Free; $Result.usedPhysicalBytes = $Total - $Free
            $Result.processes = @($Processes | Sort-Object -Property @{Expression={$_.workingSetBytes};Descending=$true} | Select-Object -First 20)
            $Result.evidence = 'Measured Windows physical memory and top process working sets in bytes. CPU sampled over stated interval and normalized by logical CPU count; process working sets are not additive system RAM.'
        }
        'media_control' {
            $Codes = @{ pause=47; play_pause=14; next=11; previous=12 }
            if (-not $Codes.ContainsKey([string]$A.command)) { throw 'Unsupported media command.' }
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BlackBoxMedia {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
}
'@
            $Handle = [BlackBoxMedia]::GetForegroundWindow(); $NativeResult = [IntPtr]::Zero
            $Sent = [BlackBoxMedia]::SendMessageTimeout($Handle, 0x319, $Handle, [IntPtr]($Codes[[string]$A.command] -shl 16), 2, 1000, [ref]$NativeResult)
            if ($Sent -eq [IntPtr]::Zero) { throw 'Media message was not acknowledged.' }
            $Result.accepted = $true; $Result.evidence = 'Windows acknowledged media message. Playback state was not observed.'
        }
        'create_folder' {
            $Path = Assert-Path ([string]$A.path) $true
            if (Test-Path -LiteralPath $Path) { throw 'Destination already exists; no overwrite.' }
            $Parent = Assert-Path ([IO.Path]::GetDirectoryName($Path))
            $null = [IO.Directory]::CreateDirectory($Path)
            $Result.path = $Path; $Result.exists = Test-Path -LiteralPath $Path -PathType Container; $Result.evidence = 'Directory existence observed after creation.'
        }
        'move_file' {
            $Source = Assert-Path ([string]$A.source); $Destination = Assert-Path ([string]$A.destination) $true
            if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw 'Only file moves are supported.' }
            if (Test-Path -LiteralPath $Destination) { throw 'Destination exists; no overwrite.' }
            $null = Assert-Path ([IO.Path]::GetDirectoryName($Destination))
            [IO.File]::Move($Source, $Destination)
            $Result.sourceAbsent = -not (Test-Path -LiteralPath $Source); $Result.destinationExists = Test-Path -LiteralPath $Destination -PathType Leaf
            $Result.evidence = 'Source absence and destination existence observed after move.'
        }
        default { throw 'Unsupported operation. No arbitrary shell tool is provided.' }
    }
    Out-Result $Result
} catch {
    Out-Result @{ ok=$false; marker='BLACKBOX_HELPER_V1'; observedAt=[DateTime]::UtcNow.ToString('o'); error=$_.Exception.Message }
    exit 1
}
