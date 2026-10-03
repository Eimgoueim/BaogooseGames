# Build the Windows installer (IExpress self-extracting exe) + portable zip.
# ASCII only on purpose: this script is executed by PowerShell 5.1 which would
# misread non-ASCII bytes in a BOM-less .ps1 file.
param(
  [Parameter(Mandatory = $true)][string]$GamePath,
  [string]$Python = 'python'
)

$ErrorActionPreference = 'Stop'
$pkg = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $pkg 'src'
$out = Join-Path $pkg 'out'
if (-not (Test-Path $out)) { New-Item -ItemType Directory -Path $out | Out-Null }

function Write-Utf8Bom([string]$path) {
  $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($true)))
}

Write-Host '[1/6] normalise encoding (UTF-8 with BOM for PowerShell/Notepad files)'
foreach ($f in @('install.ps1', 'uninstall.ps1', 'README.txt')) {
  $p = Join-Path $src $f
  if (Test-Path $p) { Write-Utf8Bom $p; Write-Host ("      BOM -> " + $f) }
}

Write-Host '[2/6] copy game html'
if (-not (Test-Path -LiteralPath $GamePath)) { throw ('game html not found: ' + $GamePath) }
Copy-Item -LiteralPath $GamePath -Destination (Join-Path $src 'PetGame.html') -Force
$gameSize = (Get-Item (Join-Path $src 'PetGame.html')).Length
Write-Host ("      PetGame.html = " + [math]::Round($gameSize / 1KB, 1) + ' KB')

Write-Host '[3/6] generate icon'
Push-Location $pkg
try { & $Python (Join-Path $pkg 'make_icon.py') } finally { Pop-Location }
$icoTmp = Join-Path $pkg 'PetGame.ico'
if (Test-Path $icoTmp) {
  Move-Item -LiteralPath $icoTmp -Destination (Join-Path $src 'PetGame.ico') -Force
  Write-Host '      PetGame.ico ok'
} else {
  Write-Warning 'icon generation failed - continuing without .ico'
}

Write-Host '[4/6] write IExpress .sed'
$files = @('PetGame.html', 'Play.cmd', 'install.cmd', 'install.ps1', 'Uninstall.cmd', 'uninstall.ps1', 'README.txt', 'PetGame.ico')
$target = Join-Path $out 'PetGame_Setup.exe'
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('[Version]')
[void]$sb.AppendLine('Class=IEXPRESS')
[void]$sb.AppendLine('SEDVersion=3')
[void]$sb.AppendLine('[Options]')
[void]$sb.AppendLine('PackagePurpose=InstallApp')
[void]$sb.AppendLine('ShowInstallProgramWindow=0')
[void]$sb.AppendLine('HideExtractAnimation=1')
[void]$sb.AppendLine('UseLongFileName=1')
[void]$sb.AppendLine('InsideCompressed=0')
[void]$sb.AppendLine('CAB_FixedSize=0')
[void]$sb.AppendLine('CAB_ResvCodeSigning=0')
[void]$sb.AppendLine('RebootMode=N')
[void]$sb.AppendLine('InstallPrompt=')
[void]$sb.AppendLine('DisplayLicense=')
[void]$sb.AppendLine('FinishMessage=')
[void]$sb.AppendLine('TargetName=' + $target)
[void]$sb.AppendLine('FriendlyName=PetGame')
[void]$sb.AppendLine('AppLaunched=cmd /c install.cmd')
[void]$sb.AppendLine('PostInstallCmd=')
[void]$sb.AppendLine('AdminQuietInstCmd=')
[void]$sb.AppendLine('UserQuietInstCmd=')
[void]$sb.AppendLine('SourceFiles=SourceFiles')
[void]$sb.AppendLine('[Strings]')
for ($i = 0; $i -lt $files.Count; $i++) {
  [void]$sb.AppendLine('FILE' + $i + '="' + $files[$i] + '"')
}
[void]$sb.AppendLine('[SourceFiles]')
[void]$sb.AppendLine('SourceFiles0=' + $src + '\')
[void]$sb.AppendLine('[SourceFiles0]')
for ($i = 0; $i -lt $files.Count; $i++) {
  $p = Join-Path $src $files[$i]
  if (-not (Test-Path $p)) { throw ('missing package file: ' + $files[$i]) }
  # IExpress expects just the token here; the file name comes from [Strings].
  [void]$sb.AppendLine('%FILE' + $i + '%=')
}
$sedPath = Join-Path $out 'PetGame.sed'
[System.IO.File]::WriteAllText($sedPath, $sb.ToString(), (New-Object System.Text.ASCIIEncoding))
Write-Host ('      ' + $sedPath)

Write-Host '[5/6] run iexpress (built-in, no extra tooling needed)'
$ie = Join-Path $env:SystemRoot 'System32\iexpress.exe'
if (-not (Test-Path $ie)) { throw 'iexpress.exe not found' }
if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
$proc = Start-Process -FilePath $ie -ArgumentList @('/N', '/Q', $sedPath) -PassThru
$proc.WaitForExit(120000) | Out-Null
$waited = 0
while (-not (Test-Path -LiteralPath $target) -and $waited -lt 90) { Start-Sleep -Seconds 1; $waited++ }
if (-not (Test-Path -LiteralPath $target)) { throw ('iexpress did not produce ' + $target) }
$exeItem = Get-Item -LiteralPath $target
Write-Host ('      ' + $exeItem.Name + ' = ' + [math]::Round($exeItem.Length / 1KB, 1) + ' KB')

Write-Host '[6/6] portable zip staging'
$stage = Join-Path $out 'portable'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item (Join-Path $src 'Play.cmd') $stage -Force
Copy-Item (Join-Path $src 'README.txt') $stage -Force
Copy-Item (Join-Path $src 'PetGame.html') $stage -Force
Copy-Item (Join-Path $src 'PetGame.ico') $stage -Force -ErrorAction SilentlyContinue

$summary = [ordered]@{
  game_kb    = [math]::Round($gameSize / 1KB, 1)
  setup_kb   = [math]::Round($exeItem.Length / 1KB, 1)
  setup_path = $target
  sed_path   = $sedPath
  stage_path = $stage
}
$summary | ConvertTo-Json -Compress | Write-Output
