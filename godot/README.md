# Godot 工程

本目录是当前游戏和后续开发的主线。新功能、修复及界面维护直接在 Godot 中进行；原 HTML 保留作历史与回归参考。历史提取工具不用于日常生成或覆盖已修改的原生配置。

原生主场景已接入养成、经济、抽卡、地牢、音频和存档，可直接游玩。迁移沿用原 HTML 的配置、像素矩形素材、文案和规则；原 HTML 保留为对照版本。字体、emoji、CSS 阴影和原生控件的跨引擎视觉仍需最终人工验收，不能把自动测试通过理解为全 UI 逐像素一致。

## 启动

用 Godot 4.7.2 打开本目录的 `project.godot`，按 **F5**。本机可从仓库根目录运行：

```powershell
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path godot
```

首次启动赠送原版 1000 信用点并打开领养面板。上方图标进入商店、背包、佩饰、房间、抽卡、积分、存档和主题；下方图标执行互动或进入地牢。地牢使用 WASD 移动、方向键/IJKL 或鼠标射击，也支持手柄；关闭返回房间。

`-- --preview` 使用临时状态，不读写正式存档。`-- --save="D:/saves/legacy.json"` 只读加载指定 JSON。普通运行使用 `user://godot-ui/save.json`，保留备份。原浏览器存档不会自动同步：先在 HTML 存档面板导出 JSON，再在 Godot 存档面板导入。

## 架构和对照

- `scripts/pet_gameplay.gd`：纯状态养成、互动、物品、经济、离线、生死和复活，向主场景发送展示/保存事件。
- `scripts/gacha.gd`：抽卡结算与保底；`ui/gacha_results.gd`：原生结果和动画。
- `scripts/dungeon.gd`：原生地牢地图、战斗、探索、商店、技能和奖励；奖励统一由主场景入账。
- `scripts/legacy_audio.gd`：按原版参数合成音乐、叫声和洗澡音效，首次操作开始音乐。
- `scripts/native_room.gd`：界面、房间输入、动画、模块整合及保存。
- `data/catalog.json` / `art.json` / `visual_fixtures.json`：由 `tools/extract_legacy.mjs` 确定性提取。
- `data/gameplay_fixtures.json`：由 `tools/extract_gameplay_fixtures.mjs` 直接执行原 JS 生成，测试比较完整状态与抽卡结果。

## 校验

从仓库根目录执行（Godot 未在 PATH 时换成完整路径）：

```powershell
node tools/extract_legacy.mjs --check
node tools/extract_gameplay_fixtures.mjs --check
godot --headless --editor --path godot --quit
godot --headless --path godot --script res://tests/test_saves.gd
godot --headless --path godot --script res://tests/test_catalog.gd
godot --headless --path godot --script res://tests/test_native_ui.gd
godot --headless --path godot --script res://tests/test_gameplay.gd
godot --headless --path godot --script res://tests/test_legacy_behavior.gd
godot --headless --path godot --script res://tests/test_dungeon.gd
godot --headless --path godot --script res://tests/test_audio.gd
godot --headless --path godot --script res://tests/test_full_game.gd
```

图形验证需要可用 GPU，不能使用 `--headless`：

```powershell
godot --path godot --script res://tests/test_pixels.gd -- --native
godot --path godot --script res://tests/render_fixture.gd -- --ui --action=games
godot --path godot --script res://tests/render_fixture.gd -- --ui --action=pull:1 --wait=1.6
```

像素测试覆盖固定尺寸、t=0 的 25 个场景和 5,621 个采样点。截图输出 `godot/.runtime/native_ui.png`；静态对照场景见 `scenes/parity_viewer.tscn`。测试不替代全流程人工游玩、真实手柄设备测试或全部动态 UI 视觉验收。旧 HTML 发布包仍保留，当前没有生成新的 Godot 安装包。
