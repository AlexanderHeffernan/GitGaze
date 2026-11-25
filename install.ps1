# Installs the latest Stoke release for this Windows user. No administrator access needed.
#   irm https://raw.githubusercontent.com/AlexanderHeffernan/GitGaze/main/install.ps1 | iex
# Stoke was called GitGaze until 1.1.7; on first launch Stoke removes an installed GitGaze.
$ErrorActionPreference = 'Stop'
$repo = 'AlexanderHeffernan/GitGaze'
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'x64' }
# Asset names follow the product name, so read them from the release rather than hard-coding one.
$release = Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/$repo/releases/latest"
$name = $release.assets.name | Where-Object { $_ -match "^[A-Za-z]+-windows-$arch-setup\.exe$" } | Select-Object -First 1
if (-not $name) { throw "No $arch installer in the latest release" }
$product = $name -replace '-windows-.*$', ''
$base = "https://github.com/$repo/releases/latest/download"
$stage = Join-Path ([IO.Path]::GetTempPath()) ("stoke-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    $installer = Join-Path $stage $name
    Invoke-WebRequest -UseBasicParsing "$base/$name" -OutFile $installer
    # GitHub serves release files as application/octet-stream, which .Content returns as bytes,
    # so the checksums are saved and read as text.
    $sumsFile = Join-Path $stage 'SHA256SUMS'
    Invoke-WebRequest -UseBasicParsing "$base/SHA256SUMS" -OutFile $sumsFile
    $expected = Get-Content $sumsFile | ForEach-Object {
        $hash, $file = $_.Trim() -split '\s+', 2
        if ($file -eq $name -and $hash -match '^[0-9a-f]{64}$') { $hash }
    } | Select-Object -First 1
    if (-not $expected) { throw "No checksum published for $name" }
    $actual = (Get-FileHash -Algorithm SHA256 $installer).Hash.ToLower()
    if ($actual -ne $expected) { throw "Checksum mismatch for $name" }
    Start-Process -FilePath $installer -ArgumentList '/S' -Wait
    $app = Join-Path $env:LOCALAPPDATA "$product\$product.exe"
    if (Test-Path $app) { Start-Process $app }
    Write-Host "Installed $product. Look for it in the notification area; updates install from Settings > Updates."
} finally {
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
}
