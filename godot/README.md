# Godot 工程

这是 Baogoose Games 的 Godot 迁移工程。阶段一提供原版像素画的静态预览和存档格式基础设施，不是可游玩的完整游戏。日常游玩仍使用仓库根目录的 `宠物养成游戏.html`。

## 环境与启动

建议 Godot 4.7.2；本机阶段一验证使用 `D:/godot` 下的 Godot 4.7.2。打开本目录的 `project.godot`，F5 运行项目，F6 运行当前场景。若 Godot 未加入 PATH，请将下方 `godot` 命令替换为 Godot 可执行文件的完整路径。当前场景由 `scripts/parity_viewer.gd` 使用 Godot 原生 `draw_rect` 绘制原版 HTML Canvas 的静态指令，供基准视觉检查。

默认显示 `theme_sakura`。可用 Godot 命令行用户参数选择基准：`-- --fixture=theme_sakura`、`--fixture=night_sakura`、`--fixture=pet_goose`、`--fixture=furniture_confirm`、`--fixture=sleep_bed`、`--fixture=bath`、`--fixture=wear_goose`、`--fixture=poop`。视觉数据共 25 个基准：六主题日/夜共 12 个、八宠物，以及家具确认、床上睡觉、洗澡、佩戴饰品、排泄五个场景。它们是静态视觉夹具，不包含 DOM 面板交互、宠物模拟或完整玩法。

例如从仓库根目录指定场景运行：

```powershell
godot --path godot -- --fixture=night_sakura
godot --path godot -- --save="D:/saves/legacy.json"
```

这是原 HTML Canvas 画布内容的静态基准，不是完整 UI 复刻：原版 DOM 状态栏、头像/宠物槽和浮层面板均未显示。

## 数据与存档

- `data/catalog.json`：从原版游戏配置提取的配置数据。
- `data/art.json`：原版 Canvas 像素矩形绘制指令。
- `data/visual_fixtures.json`：原版画面的静态视觉基准输入。
- 存档 codec 可保留未知 JSON 字段和墓地碎片；`SaveRepository` 提供原生文件存储的临时文件与备份机制。这些目前只是基础设施，尚未接入游戏流程。
- 不会自动读取浏览器 `localStorage`。可用 CLI 参数 `-- --save=绝对路径` 只读解析、校验旧版 JSON 并输出宠物数量；它不会据此绘制房间，也不会写回该文件。

`tools/extract_legacy.mjs` 从现有 HTML 确定性提取上述生成数据，不需要 npm 依赖。运行 `node tools/extract_legacy.mjs` 生成/更新文件；运行 `node tools/extract_legacy.mjs --check` 只检查是否匹配，不会生成或更新。

## 校验

在仓库根目录执行：

```powershell
godot --headless --editor --path godot --quit
godot --headless --path godot --script res://tests/test_saves.gd
godot --headless --path godot --script res://tests/test_catalog.gd
node tools/extract_legacy.mjs --check
```

在可用图形驱动的环境运行像素对照与画面导出（不要添加 `--headless`）：

```powershell
godot --path godot --script res://tests/test_pixels.gd
godot --path godot --script res://tests/render_fixture.gd
```

画面导出到 `godot/.runtime/parity_preview.png`。像素对照以原 Canvas 指令的最终合成颜色为基准，检查 25 个场景的 5,621 个采样点；透明混合允许最多两个色阶的舍入差异。当前已在 Godot 4.7.2 / Windows 原生 OpenGL 下通过。它只验证这些静态 Canvas 基准，不验证 DOM UI、动态动画或玩法。

若 Godot 不在 PATH，请将前两条命令中的 `godot` 替换为可执行文件完整路径。导入校验检查 Godot 项目资源可载入；存档测试检查 codec 与仓库行为；提取检查只验证生成文件是否匹配当前 HTML。存档功能尚未接入游戏。三者都不等同于完整游戏或全功能视觉/行为一致性验证。

完整阶段安排与逐项清单见 [`docs/GODOT_MIGRATION.md`](../docs/GODOT_MIGRATION.md)。
