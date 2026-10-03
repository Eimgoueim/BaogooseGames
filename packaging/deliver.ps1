# 把打包产物同步到 D 盘（默认 D:\baogoose_game\release）
# 用法： powershell -File packaging\deliver.ps1 [-Target "D:\宠物养成游戏"]
param(
  [string]$Target = 'D:\baogoose_game\release',
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'out\PetGame_Setup.exe'
$srcHtml = Join-Path $PSScriptRoot 'src\PetGame.html'
$readme = Join-Path $PSScriptRoot 'src\README.txt'
$zipSource = Join-Path $PSScriptRoot '_zipstage'

foreach ($p in @($out, $srcHtml, $readme)) {
  if (-not (Test-Path $p)) { throw "缺少文件：$p（请先运行 build.ps1）" }
}

if (-not (Test-Path $Target)) { New-Item -ItemType Directory -Path $Target -Force | Out-Null }

# 1) 安装包
Copy-Item $out (Join-Path $Target '宠物养成游戏_安装包.exe') -Force
# 2) 绿色免安装版（现打包）
if (Test-Path $zipSource) { Remove-Item $zipSource -Recurse -Force }
New-Item -ItemType Directory -Path $zipSource -Force | Out-Null
Copy-Item $srcHtml (Join-Path $zipSource '宠物养成游戏.html') -Force
Copy-Item (Join-Path $PSScriptRoot 'src\Play.cmd') (Join-Path $zipSource '启动游戏.cmd') -Force
Copy-Item $readme (Join-Path $zipSource '使用说明.txt') -Force
Copy-Item (Join-Path $PSScriptRoot 'src\PetGame.ico') (Join-Path $zipSource 'PetGame.ico') -Force
Compress-Archive -Path (Join-Path $zipSource '*') -DestinationPath (Join-Path $Target '宠物养成游戏_绿色免安装版.zip') -Force
Remove-Item $zipSource -Recurse -Force
# 3) 单文件版 + 说明
Copy-Item $srcHtml (Join-Path $Target '宠物养成游戏.html') -Force
Copy-Item $readme (Join-Path $Target '使用说明.txt') -Force

# 校验（与打包源文件比对哈希）
$report = @()
foreach ($n in @('宠物养成游戏_安装包.exe', '宠物养成游戏_绿色免安装版.zip', '宠物养成游戏.html')) {
  $t = Join-Path $Target $n
  $s = if ($n -eq '宠物养成游戏_安装包.exe') { $out } elseif ($n -eq '宠物养成游戏.html') { $srcHtml } else { $null }
  $ok = if ($s) { (Get-FileHash $t -Algorithm SHA256).Hash -eq (Get-FileHash $s -Algorithm SHA256).Hash } else { $true }
  $report += [pscustomobject]@{ 文件 = $n; KB = [math]::Round((Get-Item $t).Length / 1KB, 1); 校验 = $ok }
}
$report | Format-Table -AutoSize
"已同步到：$Target"
