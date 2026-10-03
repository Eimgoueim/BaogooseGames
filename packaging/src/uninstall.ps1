# 宠物养成游戏 · 卸载脚本
# 由安装目录里的 Uninstall.cmd 调用。

param(
  [string]$InstallDir = '',
  [switch]$Silent
)

$AppName = '宠物养成游戏'
$ErrorActionPreference = 'SilentlyContinue'
if (-not $InstallDir) { $InstallDir = $PSScriptRoot }
$InstallDir = ([string]$InstallDir).Trim('"')
if ($InstallDir) { $InstallDir = [System.IO.Path]::GetFullPath($InstallDir) }

$confirmed = $true
if ($env:PETGAME_SILENT) { $Silent = $true }
if (-not $Silent) {
  try {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $text = "确定要卸载「$AppName」吗？`n`n提示：游戏存档保存在安装目录里（浏览器数据文件夹），`n卸载会一并删除。如果还想保留进度，请先打开游戏，`n在「💾 存档」里导出备份。"
    $r = [System.Windows.Forms.MessageBox]::Show($text, '卸载 ' + $AppName, 'YesNo', 'Warning')
    if ($r -ne 'Yes') { $confirmed = $false }
  } catch { }
}
if (-not $confirmed) { exit 0 }

# 快捷方式（安装时若用 PETGAME_LNK_DIR 重定向过，这里同步）
$lnkDir = $env:PETGAME_LNK_DIR
$desktopDir = if ($lnkDir) { $lnkDir } else { [Environment]::GetFolderPath('Desktop') }
$startMenuDir = if ($lnkDir) { $lnkDir } else { Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs' }
$uninLnkDir = if ($lnkDir) { $lnkDir } else { [Environment]::GetFolderPath('Programs') }
Remove-Item -LiteralPath (Join-Path $desktopDir ($AppName + '.lnk')) -Force
Remove-Item -LiteralPath (Join-Path $startMenuDir ($AppName + '.lnk')) -Force
Remove-Item -LiteralPath (Join-Path $uninLnkDir ($AppName + ' 卸载.lnk')) -Force
# 注册表卸载项
$regKey = $env:PETGAME_REG_KEY
if (-not $regKey) { $regKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PetGame' }
Remove-Item -Path $regKey -Recurse -Force

# 安装目录（脚本自己也在里面，删不掉时交给 cmd 延迟删除）
$failed = $false
if ($InstallDir -and (Test-Path -LiteralPath $InstallDir)) {
  try {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction Stop
  } catch {
    $failed = $true
    Start-Process -WindowStyle Hidden -FilePath 'cmd.exe' -ArgumentList '/c', ('timeout /t 2 >nul & rmdir /s /q "' + $InstallDir + '"')
  }
}

if (-not $Silent) {
  try {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $done = "「$AppName」已卸载完毕。"
    if ($failed) { $done += "`n（安装目录将在几秒后自动删除）" }
    [System.Windows.Forms.MessageBox]::Show($done, '卸载完成', 'OK', 'Information') | Out-Null
  } catch { }
}
exit 0
