[CmdletBinding()]
param(
    [Alias('IsoRoot')][string]$SaveDirectory,
    [switch]$InstallOnly,
    [string]$PackagePath
)

$ErrorActionPreference='Stop'

function Get-WidDefaultInstallRoot {
    $local=[string]$env:LOCALAPPDATA
    if([string]::IsNullOrWhiteSpace($local)){$local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)}
    if([string]::IsNullOrWhiteSpace($local)){throw 'Windows LocalAppData could not be resolved.'}
    Join-Path $local 'WindowsIsoDownloader'
}

function Get-WidWindowsPowerShell {
    $path=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Windows PowerShell 5.1 was not found: $path"}
    $path
}

function Invoke-WidDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [Parameter(Mandatory)][string]$Destination,
        [string[]]$AllowedHosts=@('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com'),
        [ValidateRange(0,10)][int]$MaximumRedirects=5
    )
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $current=$Uri
    for($redirect=0;$redirect -le $MaximumRedirects;$redirect++){
        if($current.Scheme -ne 'https'){throw "Release download requires HTTPS: $current"}
        if($AllowedHosts -notcontains $current.DnsSafeHost){throw "Release download host is not allowed: $($current.DnsSafeHost)"}
        $request=[Net.HttpWebRequest]::Create($current)
        $request.AllowAutoRedirect=$false
        $request.Timeout=30000
        $request.ReadWriteTimeout=30000
        $request.UserAgent='WindowsIsoDownloader/0.5.0'
        try{
            $response=$request.GetResponse()
            try{
                $status=[int]$response.StatusCode
                if($status -ge 300 -and $status -lt 400){
                    if($redirect -eq $MaximumRedirects){throw "Release download exceeded $MaximumRedirects redirects."}
                    $location=[string]$response.Headers['Location']
                    if([string]::IsNullOrWhiteSpace($location)){throw 'Release redirect did not include a destination.'}
                    $current=[uri]::new($current,$location)
                    continue
                }
                if($status -ne 200){throw "Release download returned HTTP $status."}
                $parent=Split-Path -Parent $Destination
                New-Item -ItemType Directory -Path $parent -Force|Out-Null
                $input=$response.GetResponseStream()
                $output=[IO.File]::Open($Destination,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
                try{$input.CopyTo($output)}finally{$output.Dispose();$input.Dispose()}
                return [pscustomobject]@{Path=$Destination;FinalUri=[string]$current}
            }finally{$response.Dispose()}
        }catch [Net.WebException]{
            if($_.Exception.Response){$_.Exception.Response.Dispose()}
            throw
        }
    }
}

function Expand-WidArchiveSafely {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ArchivePath,[Parameter(Mandatory)][string]$Destination)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root=[IO.Path]::GetFullPath($Destination).TrimEnd('\','/')
    New-Item -ItemType Directory -Path $root -Force|Out-Null
    $prefix=$root+[IO.Path]::DirectorySeparatorChar
    $zip=[IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try{
        foreach($entry in $zip.Entries){
            $relative=[string]$entry.FullName
            if([string]::IsNullOrWhiteSpace($relative)){throw 'Release archive contains an empty entry name.'}
            $relative=$relative.Replace('/','\')
            if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.\.(\\|$)' -or $relative.Contains(':')){throw "Unsafe release archive entry: $($entry.FullName)"}
            $target=[IO.Path]::GetFullPath((Join-Path $root $relative))
            if(-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "Release archive entry escapes staging: $($entry.FullName)"}
            if([string]::IsNullOrEmpty($entry.Name)){
                New-Item -ItemType Directory -Path $target -Force|Out-Null
                continue
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null
            $input=$entry.Open()
            $output=[IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$input.CopyTo($output)}finally{$output.Dispose();$input.Dispose()}
        }
    }finally{$zip.Dispose()}
}

function Assert-WidPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$Version)
    $root=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
    $manifestPath=Join-Path $root 'package-manifest.json'
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'Release package manifest is missing.'}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    if([string]$manifest.Product -ne 'Windows ISO Downloader'){throw 'Release package product identity is invalid.'}
    if([string]$manifest.Version -ne $Version){throw "Release package version '$($manifest.Version)' does not match '$Version'."}
    if([string]::IsNullOrWhiteSpace([string]$manifest.EntryPoint)){throw 'Release package entry point is missing.'}
    $expected=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($file in @($manifest.Files)){
        $relative=[string]$file.Path
        if([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.\.(\\|$)' -or $relative.Contains(':')){throw "Unsafe manifest path: $relative"}
        if(-not $expected.Add($relative.Replace('/','\'))){throw "Duplicate manifest path: $relative"}
        $path=[IO.Path]::GetFullPath((Join-Path $root $relative))
        if(-not $path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Manifest path escapes package root: $relative"}
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Manifest file is missing: $relative"}
        $item=Get-Item -LiteralPath $path
        if([int64]$file.Length -ne [int64]$item.Length){throw "Manifest length mismatch: $relative"}
        $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if($hash -ne [string]$file.Sha256){throw "Manifest hash mismatch: $relative"}
    }
    $actual=@(Get-ChildItem -LiteralPath $root -File -Recurse|Where-Object {$_.FullName -ne $manifestPath}|ForEach-Object {$_.FullName.Substring($root.Length).TrimStart('\').Replace('/','\')})
    if($actual.Count -ne $expected.Count){throw 'Release package contains missing or unexpected payload files.'}
    foreach($relative in $actual){if(-not $expected.Contains($relative)){throw "Unexpected release package file: $relative"}}
    $entryPath=[IO.Path]::GetFullPath((Join-Path $root ([string]$manifest.EntryPoint)))
    if(-not(Test-Path -LiteralPath $entryPath -PathType Leaf)){throw 'Release package entry point does not exist.'}
    $manifest
}

function Write-WidFileAtomically {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Content,[ValidateSet('UTF8','ASCII')][string]$Encoding='UTF8')
    $directory=Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force|Out-Null
    $temporary=Join-Path $directory ('.tmp-'+[guid]::NewGuid().Guid)
    try{
        Set-Content -LiteralPath $temporary -Value $Content -Encoding $Encoding
        if(Test-Path -LiteralPath $Path -PathType Leaf){
            $backup=Join-Path $directory ('.bak-'+[guid]::NewGuid().Guid)
            try{[IO.File]::Replace($temporary,$Path,$backup,$true)}finally{Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue}
        }else{Move-Item -LiteralPath $temporary -Destination $Path}
    }finally{Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
}

function Write-WidLaunchers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallRoot)
    $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\','/')
    $bin=Join-Path $root 'bin'
    $escapedRoot=$root.Replace("'","''")
    $escapedPowerShell=(Get-WidWindowsPowerShell).Replace("'","''")
    $launcher=@"
`$ErrorActionPreference='Stop'
`$root='$escapedRoot'
`$state=Get-Content -LiteralPath (Join-Path `$root 'state\current.json') -Raw|ConvertFrom-Json
`$entry=Join-Path `$root ('versions\'+[string]`$state.CurrentVersion+'\scripts\Get-MassgraveMedia.ps1')
if(-not(Test-Path -LiteralPath `$entry -PathType Leaf)){throw "Active Windows ISO Downloader entry point is missing: `$entry"}
& '$escapedPowerShell' -NoLogo -NoProfile -STA -File `$entry @args
exit `$LASTEXITCODE
"@
    $uninstall=@"
`$ErrorActionPreference='Stop'
`$root='$escapedRoot'
`$state=Get-Content -LiteralPath (Join-Path `$root 'state\current.json') -Raw|ConvertFrom-Json
`$entry=Join-Path `$root ('versions\'+[string]`$state.CurrentVersion+'\scripts\Uninstall-WindowsIsoDownloader.ps1')
if(-not(Test-Path -LiteralPath `$entry -PathType Leaf)){throw "Windows ISO Downloader uninstaller is missing: `$entry"}
& '$escapedPowerShell' -NoLogo -NoProfile -STA -File `$entry -InstallRoot `$root @args
exit `$LASTEXITCODE
"@
    Write-WidFileAtomically -Path (Join-Path $bin 'get-windows-iso.ps1') -Content $launcher
    Write-WidFileAtomically -Path (Join-Path $bin 'uninstall-windows-iso-downloader.ps1') -Content $uninstall
    Write-WidFileAtomically -Path (Join-Path $bin 'get-windows-iso.cmd') -Content "@echo off`r`npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%~dp0get-windows-iso.ps1"" %*" -Encoding ASCII
    Write-WidFileAtomically -Path (Join-Path $bin 'uninstall-windows-iso-downloader.cmd') -Content "@echo off`r`npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%~dp0uninstall-windows-iso-downloader.ps1"" %*" -Encoding ASCII
    $bin
}

function Add-WidUserPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory)
    $target=[IO.Path]::GetFullPath($Directory).TrimEnd('\')
    $userPath=[string][Environment]::GetEnvironmentVariable('Path','User')
    $parts=New-Object System.Collections.Generic.List[string]
    foreach($part in @($userPath -split ';')){if(-not[string]::IsNullOrWhiteSpace($part) -and -not $part.Trim().TrimEnd('\').Equals($target,[StringComparison]::OrdinalIgnoreCase)){[void]$parts.Add($part.Trim())}}
    [void]$parts.Add($target)
    [Environment]::SetEnvironmentVariable('Path',($parts -join ';'),'User')
    if(-not(@($env:Path -split ';')|Where-Object {$_.TrimEnd('\').Equals($target,[StringComparison]::OrdinalIgnoreCase)})){$env:Path=$env:Path.TrimEnd(';')+';'+$target}
}

function Install-WidPackageFromArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][int64]$ExpectedLength,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$InstallRoot,
        [switch]$SkipPathUpdate
    )
    $archive=[IO.Path]::GetFullPath($ArchivePath)
    if(-not(Test-Path -LiteralPath $archive -PathType Leaf)){throw "Release archive was not found: $archive"}
    $item=Get-Item -LiteralPath $archive
    if($ExpectedLength -le 0 -or [int64]$item.Length -ne $ExpectedLength){throw "Release archive length mismatch. Expected $ExpectedLength bytes; received $($item.Length)."}
    $actualHash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if($actualHash -ne $ExpectedSha256){throw "Release archive SHA-256 mismatch. Expected $ExpectedSha256; received $actualHash."}
    $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\','/')
    if($root -eq [IO.Path]::GetPathRoot($root)){throw 'The installation root cannot be a drive root.'}
    $stagingRoot=Join-Path $root 'staging'
    $stage=Join-Path $stagingRoot ([guid]::NewGuid().Guid)
    $versionRoot=Join-Path $root ('versions\'+$Version)
    $backup=$null
    $movedNew=$false
    New-Item -ItemType Directory -Path $stage -Force|Out-Null
    try{
        Expand-WidArchiveSafely -ArchivePath $archive -Destination $stage
        [void](Assert-WidPackage -PackageRoot $stage -Version $Version)
        $reuse=$false
        if(Test-Path -LiteralPath $versionRoot -PathType Container){
            try{[void](Assert-WidPackage -PackageRoot $versionRoot -Version $Version);$reuse=$true}catch{$reuse=$false}
        }
        if(-not $reuse){
            New-Item -ItemType Directory -Path (Split-Path -Parent $versionRoot) -Force|Out-Null
            if(Test-Path -LiteralPath $versionRoot){$backup=$versionRoot+'.backup-'+[guid]::NewGuid().Guid;Move-Item -LiteralPath $versionRoot -Destination $backup}
            Move-Item -LiteralPath $stage -Destination $versionRoot
            $movedNew=$true
            [void](Assert-WidPackage -PackageRoot $versionRoot -Version $Version)
        }
        $bin=Write-WidLaunchers -InstallRoot $root
        $statePath=Join-Path $root 'state\current.json'
        $oldState=$null
        if(Test-Path -LiteralPath $statePath -PathType Leaf){$oldState=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json}
        $previous=$null
        if($oldState){
            if([string]$oldState.CurrentVersion -and [string]$oldState.CurrentVersion -ne $Version){$previous=[string]$oldState.CurrentVersion}else{$previous=[string]$oldState.PreviousVersion}
        }
        $state=[pscustomobject][ordered]@{SchemaVersion=1;CurrentVersion=$Version;PreviousVersion=$previous;InstalledAtUtc=[DateTime]::UtcNow.ToString('o')}
        Write-WidFileAtomically -Path $statePath -Content ($state|ConvertTo-Json -Depth 4)
        if(-not $SkipPathUpdate){try{Add-WidUserPath -Directory $bin}catch{Write-Warning "The command was installed but the current-user PATH could not be updated: $($_.Exception.Message)"}}
        if($backup){Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue;$backup=$null}
        [pscustomobject]@{Status='Installed';InstallRoot=$root;CurrentVersion=$Version;PreviousVersion=$previous;Sha256=$actualHash;Launcher=(Join-Path $bin 'get-windows-iso.cmd')}
    }catch{
        if($movedNew -and $backup -and (Test-Path -LiteralPath $backup)){
            Remove-Item -LiteralPath $versionRoot -Recurse -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $backup -Destination $versionRoot
            $backup=$null
        }elseif($movedNew -and (Test-Path -LiteralPath $versionRoot)){
            Remove-Item -LiteralPath $versionRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }finally{
        if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}
        if($backup -and (Test-Path -LiteralPath $backup)){Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue}
    }
}

function Start-WidDownloader {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallRoot,[string]$SaveDirectory)
    $launcher=Join-Path $InstallRoot 'bin\get-windows-iso.ps1'
    $arguments=@()
    if(-not[string]::IsNullOrWhiteSpace($SaveDirectory)){$arguments=@('-SaveDirectory',$SaveDirectory)}
    & (Get-WidWindowsPowerShell) -NoLogo -NoProfile -STA -File $launcher @arguments
}

function Invoke-WidBootstrap {
    [CmdletBinding()]
    param([string]$SaveDirectory,[switch]$InstallOnly,[string]$PackagePath)
    $version='0.5.0'
    $uri=[uri]'https://github.com/gilp456/windows-iso-downloader-dist/releases/download/v0.5.0/WindowsIsoDownloader-0.5.0.zip'
    $length=[int64]37701
    $sha256='13F32AA2E1AB4DFEB22541EB4C65CE76D02C8072996D28D4F214E5256813589D'
    $root=Get-WidDefaultInstallRoot
    $downloadRoot=Join-Path $root ('staging\download-'+[guid]::NewGuid().Guid)
    $archive=$PackagePath
    try{
        if([string]::IsNullOrWhiteSpace($archive)){
            New-Item -ItemType Directory -Path $downloadRoot -Force|Out-Null
            $archive=Join-Path $downloadRoot ("WindowsIsoDownloader-$version.zip")
            Write-Host "Downloading Windows ISO Downloader $version"
            Write-Host "Source: $uri"
            [void](Invoke-WidDownload -Uri $uri -Destination $archive)
        }
        Write-Host "Verifying SHA-256: $sha256"
        $result=Install-WidPackageFromArchive -ArchivePath $archive -ExpectedLength $length -ExpectedSha256 $sha256 -Version $version -InstallRoot $root
        Write-Host "Installed Windows ISO Downloader $version"
        Write-Host "Install location: $($result.InstallRoot)"
        Write-Host 'Command: get-windows-iso'
        if(-not $InstallOnly){Start-WidDownloader -InstallRoot $root -SaveDirectory $SaveDirectory}
        $result
    }finally{if(Test-Path -LiteralPath $downloadRoot){Remove-Item -LiteralPath $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue}}
}

if(-not $script:WindowsIsoDownloaderBootstrapNoRun){
    Invoke-WidBootstrap -SaveDirectory $SaveDirectory -InstallOnly:$InstallOnly -PackagePath $PackagePath
}

