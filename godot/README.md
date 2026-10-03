# Godot 工程

这是 Baogoose Games 的 Godot 迁移工程。当前为阶段二界面与输入迁移预览，不是完整游戏。根目录的正式游玩入口仍是 `宠物养成游戏.html`。

## 环境与启动

建议 Godot 4.7.2；本机阶段二验证使用 `D:/godot` 下的 Godot 4.7.2。打开本目录的 `project.godot`，F5 运行原生房间预览。若 Godot 未加入 PATH，请将下方 `godot` 命令替换为 Godot 可执行文件的完整路径。主场景 `native_room.tscn` 绘制动态房间并显示 HUD 与原版六页面；静态 Canvas 基准可通过 `--scene res://scenes/parity_viewer.tscn` 单独打开。

静态 Canvas 夹具默认使用 `theme_sakura`。切换夹具时需显式选择 `parity_viewer.tscn`，例如 `godot --path godot --scene res://scenes/parity_viewer.tscn -- --fixture=night_sakura`。视觉数据共 25 个基准：六主题日/夜共 12 个、八宠物，以及家具确认、床上睡觉、洗澡、佩戴饰品、排泄五个场景。它们仅用于原 Canvas 绘制基准，不包含动态房间、DOM 页面或完整玩法。

例如从仓库根目录运行：

```powershell
godot --path godot
godot --path godot -- --preview
godot --path godot --scene res://scenes/parity_viewer.tscn -- --fixture=night_sakura
godot --path godot -- --save="D:/saves/legacy.json"
```

阶段二支持 HUD 和六页面导航、主题及 accent、宠物切换/改名、已有佩饰穿戴与家具摆放/拖拽/缩放/收回，以及宠物自主移动/拖拽/掉落。商店购买、抽卡结算、领养、道具使用、养成、生死复活、地牢和音频仍待迁移；部分按钮当前只表达操作意图。文案和数据沿用 HTML，但字号、emoji、阴影等尚未完成跨引擎视觉验收。

## 数据与存档

- `data/catalog.json`：从原版游戏配置提取的配置数据。
- `data/art.json`：原版 Canvas 像素矩形绘制指令。
- `data/visual_fixtures.json`：原版画面的静态视觉基准输入。
- 普通运行使用 `user://godot-ui/save.json`，并保留备份；`--preview` 不读取或写入原生存档。
- `-- --save=绝对路径` 只读导入旧 JSON 并绘制预览，不会写回来源文件。
- 不自动读取浏览器 `localStorage`。存档面板提供原生导入/导出预览，但旧浏览器存档不会自动同步。

`tools/extract_legacy.mjs` 从现有 HTML 确定性提取上述生成数据，不需要 npm 依赖。运行 `node tools/extract_legacy.mjs` 生成/更新文件；运行 `node tools/extract_legacy.mjs --check` 只检查是否匹配，不会生成或更新。

## 校验

在仓库根目录执行：

```powershell
godot --headless --editor --path godot --quit
godot --headless --path godot --script res://tests/test_saves.gd
godot --headless --path godot --script res://tests/test_catalog.gd
godot --headless --path godot --script res://tests/test_native_ui.gd
node tools/extract_legacy.mjs --check
```

在可用图形驱动的环境运行像素对照与画面导出（不要添加 `--headless`）：

```powershell
godot --path godot --script res://tests/test_pixels.gd -- --native
godot --path godot --script res://tests/render_fixture.gd
godot --path godot --script res://tests/render_fixture.gd -- --ui --action=page:shop
```

画面导出到 `godot/.runtime/parity_preview.png`；带 `--ui` 时输出 `godot/.runtime/native_ui.png`。native 像素对照检查动态 RoomRenderer 当前固定尺寸、`t=0` 的 25 个场景和 5,621 个采样点，不验证动画、窗口尺寸变化、全 UI 逐像素一致或玩法完整性。

若 Godot 不在 PATH，请将命令中的 `godot` 替换为可执行文件完整路径。导入校验检查 Godot 项目资源可载入；存档测试检查 codec 与仓库行为；原生 UI 测试检查当前已迁移的路由；提取检查只验证生成文件是否匹配当前 HTML。这些检查都不等同于完整游戏或全功能视觉/行为一致性验证。

完整阶段安排与逐项清单见 [`docs/GODOT_MIGRATION.md`](../docs/GODOT_MIGRATION.md)。
