# 宠物养成游戏 · 安装脚本
# 由 IExpress 自解压安装包调用（install.cmd -> 本脚本）
# 默认安装到 %LOCALAPPDATA%\PetGame，创建桌面与开始菜单快捷方式，并登记卸载项。

param(
  [string]$SourceDir = '',
  [string]$TargetDir = '',
  [switch]$NoShortcuts,
  [switch]$Silent,
  [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$AppName = '宠物养成游戏'
$Version = '1.0'

if (-not $SourceDir) { $SourceDir = (Get-Location).Path }
$SourceDir = ([string]$SourceDir).Trim('"')
if ($SourceDir) { $SourceDir = [System.IO.Path]::GetFullPath($SourceDir) }
if (-not $TargetDir -and $env:PETGAME_DIR) { $TargetDir = $env:PETGAME_DIR }
$TargetDir = ([string]$TargetDir).Trim('"')
if (-not $TargetDir) { $TargetDir = Join-Path $env:LOCALAPPDATA 'PetGame' }
$TargetDir = [System.IO.Path]::GetFullPath($TargetDir)

# 无人值守 / 自动化测试用（各项可单独开启）：
#   PETGAME_TEST=1     等价于同时打开下面三个
#   PETGAME_SILENT     不弹窗
#   PETGAME_NOSHORTCUTS 不创建快捷方式、不写注册表
#   PETGAME_NOLAUNCH   安装后不询问启动
#   PETGAME_LOG=<路径> 把过程写进日志
if ($env:PETGAME_TEST) { $Silent = $true; $NoShortcuts = $true; $NoLaunch = $true }
if ($env:PETGAME_SILENT) { $Silent = $true }
if ($env:PETGAME_NOSHORTCUTS) { $NoShortcuts = $true }
if ($env:PETGAME_NOLAUNCH) { $NoLaunch = $true }
function Write-Log([string]$text) {
  if (-not $env:PETGAME_LOG) { return }
  try { Add-Content -LiteralPath $env:PETGAME_LOG -Value ("[" + (Get-Date -Format 'HH:mm:ss') + "] " + $text) -Encoding UTF8 } catch { }
}
Write-Log ("install.ps1 started; SourceDir=" + $SourceDir + " TargetDir=" + $TargetDir + " NoShortcuts=" + [bool]$NoShortcuts)

$ok = $false
$msg = ''
try {
  if (-not (Test-Path -LiteralPath $TargetDir)) {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
  }

  $files = @('PetGame.html', 'Play.cmd', 'README.txt', 'Uninstall.cmd', 'uninstall.ps1', 'PetGame.ico')
  $copied = 0
  foreach ($f in $files) {
    $src = Join-Path $SourceDir $f
    if (Test-Path -LiteralPath $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $TargetDir $f) -Force
      $copied++
    }
  }
  if ($copied -eq 0) { throw "安装源文件缺失：$SourceDir" }
  if (-not (Test-Path -LiteralPath (Join-Path $TargetDir 'PetGame.html'))) { throw '主程序 PetGame.html 复制失败' }

  if (-not $NoShortcuts) {
    $icon = Join-Path $TargetDir 'PetGame.ico'
    $play = Join-Path $TargetDir 'Play.cmd'
    $unin = Join-Path $TargetDir 'Uninstall.cmd'
    $ws = New-Object -ComObject WScript.Shell

    # 测试/自定义用：PETGAME_LNK_DIR 可把快捷方式重定向到指定目录
    $lnkDir = $env:PETGAME_LNK_DIR
    $desktopDir = if ($lnkDir) { $lnkDir } else { [Environment]::GetFolderPath('Desktop') }
    $startMenuDir = if ($lnkDir) { $lnkDir } else { Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs' }
    $uninLnkDir = if ($lnkDir) { $lnkDir } else { [Environment]::GetFolderPath('Programs') }
    if (-not (Test-Path -LiteralPath $desktopDir)) { New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null }

    $lnkTargets = @()
    $lnkTargets += (Join-Path $desktopDir ($AppName + '.lnk'))
    $lnkTargets += (Join-Path $startMenuDir ($AppName + '.lnk'))
    foreach ($lnkPath in $lnkTargets) {
      try {
        $sc = $ws.CreateShortcut($lnkPath)
        $sc.TargetPath = $play
        $sc.WorkingDirectory = $TargetDir
        $sc.IconLocation = $icon
        $sc.Description = $AppName
        $sc.Save()
      } catch { }
    }
    try {
      $sc = $ws.CreateShortcut((Join-Path $uninLnkDir ($AppName + ' 卸载.lnk')))
      $sc.TargetPath = $unin
      $sc.WorkingDirectory = $TargetDir
      $sc.IconLocation = $icon
      $sc.Description = '卸载 ' + $AppName
      $sc.Save()
    } catch { }

    # 登记到「设置 → 应用 → 已安装的应用」
    try {
      $key = $env:PETGAME_REG_KEY
      if (-not $key) { $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PetGame' }
      if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
      $size = 0
      $sum = (Get-ChildItem -LiteralPath $TargetDir -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
      if ($sum) { $size = [int]($sum / 1KB) }
      Set-ItemProperty -Path $key -Name DisplayName -Value $AppName
      Set-ItemProperty -Path $key -Name DisplayVersion -Value $Version
      Set-ItemProperty -Path $key -Name Publisher -Value '本地单机小游戏'
      Set-ItemProperty -Path $key -Name InstallLocation -Value $TargetDir
      Set-ItemProperty -Path $key -Name DisplayIcon -Value $icon
      Set-ItemProperty -Path $key -Name UninstallString -Value ('"' + $unin + '"')
      Set-ItemProperty -Path $key -Name NoModify -Value 1 -Type DWord
      Set-ItemProperty -Path $key -Name NoRepair -Value 1 -Type DWord
      Set-ItemProperty -Path $key -Name EstimatedSize -Value $size -Type DWord
    } catch { }
  }

  $ok = $true
  $tail = '桌面和开始菜单已经放好快捷方式，双击即可游戏。'
  if ($NoShortcuts) { $tail = '（本次未创建快捷方式）' }
  $msg = "「$AppName」安装完成！`n`n安装位置：`n$TargetDir`n`n$tail"
} catch {
  $msg = "安装失败：`n" + $_.Exception.Message
}

if ($Silent) {
  Write-Log $msg
  Write-Output $msg
  if (-not $ok) { exit 1 }
  exit 0
}
Write-Log $msg

try {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  if ($ok -and -not $NoLaunch) {
    $r = [System.Windows.Forms.MessageBox]::Show($msg + "`n`n现在启动游戏吗？（会用独立窗口打开，像个小程序）", $AppName, 'YesNo', 'Information')
    if ($r -eq 'Yes') { Start-Process -FilePath (Join-Path $TargetDir 'Play.cmd') }
  } else {
    $icon2 = 'Information'
    if (-not $ok) { $icon2 = 'Error' }
    [System.Windows.Forms.MessageBox]::Show($msg, $AppName, 'OK', $icon2) | Out-Null
  }
} catch {
  Write-Output $msg
}

if (-not $ok) { exit 1 }
exit 0
