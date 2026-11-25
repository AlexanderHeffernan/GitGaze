# Installs the latest GitGaze release for this Windows user. No administrator access needed.
#   irm https://raw.githubusercontent.com/AlexanderHeffernan/GitGaze/main/install.ps1 | iex
$ErrorActionPreference = 'Stop'
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'x64' }
$name = "GitGaze-windows-$arch-setup.exe"
$base = 'https://github.com/AlexanderHeffernan/GitGaze/releases/latest/download'
$stage = Join-Path ([IO.Path]::GetTempPath()) ("gitgaze-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    $installer = Join-Path $stage $name
    Invoke-WebRequest -UseBasicParsing "$base/$name" -OutFile $installer
    $sums = (Invoke-WebRequest -UseBasicParsing "$base/SHA256SUMS").Content -split "`n"
    $expected = ($sums | Where-Object { $_ -match "^([0-9a-f]{64})\s+$([regex]::Escape($name))$" } | ForEach-Object { $Matches[1] })
    if (-not $expected) { throw "No checksum published for $name" }
    $actual = (Get-FileHash -Algorithm SHA256 $installer).Hash.ToLower()
    if ($actual -ne $expected) { throw "Checksum mismatch for $name" }
    Start-Process -FilePath $installer -ArgumentList '/S' -Wait
    $app = Join-Path $env:LOCALAPPDATA 'GitGaze\GitGaze.exe'
    if (Test-Path $app) { Start-Process $app }
    Write-Host 'Installed GitGaze. Look for it in the notification area; updates install from Settings → Updates.'
} finally {
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
}
