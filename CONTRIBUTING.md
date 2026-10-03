# 🤝 参与开发 / Contributing

感谢愿意一起来改这个游戏！这个项目非常轻量：**一个 HTML 文件就是整个游戏**，没有构建步骤、没有依赖。

---

## 一、最快上手（3 分钟）

```bash
git clone https://github.com/Eimgoueim/BaogooseGames.git
cd BaogooseGames
```

然后**直接用浏览器打开 `宠物养成游戏.html`**（推荐 Edge / Chrome / Firefox）就能玩。
改完代码保存 → 刷新页面 → 立刻看到效果，不需要编译、不需要装 Node/Python。

> 唯一需要 Windows 的场景：打 Windows 安装包（见 `packaging/`）。改游戏本身在 mac / Linux 上也能做。

---

## 二、提交改动的流程（推荐 Pull Request）

如果你**不是**仓库协作者：

1. 点仓库右上角 **Fork**，把仓库复制到你自己的账号下
2. clone 你的 fork，开个分支改代码：
   ```bash
   git checkout -b feat/小地图图标
   git commit -m "feat: 小地图加上宝箱房图标"
   git push origin feat/小地图图标
   ```
3. 回到 GitHub 点 **Compare & pull request**，写清楚：**改了什么 / 怎么测的 / 截图或 GIF（有更好）**
4. 等维护者 review，通过后合并

如果你是**协作者（Collaborator）**：可以直接在仓库里开分支推送，但**请不要直接推 `main`** —— 一样走 PR，方便回退和 review。

### 分支命名建议

| 前缀 | 用途 | 例子 |
|---|---|---|
| `feat/` | 新功能 | `feat/宠物进化` |
| `fix/` | 修 bug | `fix/领养面板误关` |
| `tweak/` | 数值 / 手感 / 文案调整 | `tweak/地牢怪更少` |
| `docs/` | 只改文档 | `docs/补充构建说明` |

---

## 三、这个项目的代码约定（重要）

`宠物养成游戏.html` 里所有东西都是内联的，请遵守这些约定，否则容易把游戏改坏：

1. **零外部依赖**：不要引入 CDN、外部图片、外部字体、npm 包。所有像素画都是代码里用 `pxFill` / 矩形画出来的 ❌ 不要放官方素材或来路不明的图片
2. **一个界面同时只开一个**：新开面板要调 `closeOtherPanels('xxxOverlay')`，面板切换用 toggle（再点一次关闭）
3. **按钮统一走事件委托**：HTML 里写 `data-action="动作名"` 或 `data-action="动作名:参数"`，然后在 `handle(action, arg)` 的 `switch` 里加 `case`
4. **存档要能平滑升级**：`state` 加新字段时，改 `defaultState()` 之外，**必须**在 `normalizeSave()` 里给老存档兜底（判断字段不存在时给默认值），否则老玩家存档会坏
5. **游戏循环不能死**：`requestAnimationFrame` 的循环里，任何可能抛错的代码都要 `try/catch`（项目里用 `pxSoftError`），并且**先续期下一帧再干活** —— 否则一次异常就让画面永久定格（历史上真出过这个卡死 bug）
6. **地牢（肉鸽）相关**：常量都在 `RL_*` 前缀里（概率、奖励、层数），改数值优先改常量，不要散落在逻辑里
7. **主题**：新颜色请用 CSS 变量（`--warm` / `--card` / `--bg2` 等），让 6 套主题都能正常显示
8. **注释写中文**，和现有代码保持一致

### Godot 迁移约定

Godot 工程位于 `godot/`，迁移目标是只替换底层架构，保留原版 UI、美术、文案、数值和玩法。新增 Godot 代码时遵循 [迁移说明](docs/GODOT_MIGRATION.md) 和 [Godot 工程说明](godot/README.md)：先以原 HTML 为准，按功能逐项核对视觉与行为；不得借迁移悄悄修复旧版 bug，修 bug 应单独提出并记录。Godot 页面成为主要入口前，必须完成全功能迁移与对照验证。

原版 HTML 的约定仍适用于 HTML 改动。若 Godot 迁移要求与本节前述单 HTML 约定冲突，**Godot 改动以 Godot 迁移文档为准**；这不改变 HTML 原版的发布与贡献流程。

本机已验证环境为 Godot 4.7.2（`D:/godot`）；其他环境建议使用 Godot 4.7.2。阶段一可用以下命令校验工程与存档 codec：

```powershell
godot --headless --editor --path godot --quit
godot --headless --path godot --script res://tests/test_saves.gd
```

`F5` 启动原生游戏主场景，已接入养成、抽卡、地牢、音频及存档；固定 Canvas 基准请运行 `parity_viewer.tscn`。完整 UI 视觉仍需人工验收，验证命令见 Godot README。

---

## 四、动手改之前先自测

项目没有自动化测试，请至少人工检查：

- [ ] 打开页面无报错（F12 控制台干净）
- [ ] 房间能正常显示、宠物能走动，**不会被卡住**
- [ ] 你改的功能在 6 套主题下都正常（🎨 界面风格逐个切一遍）
- [ ] 地牢（🎮）能进能出，`Esc` 和「关闭」都能退出，帧循环没有定格
- [ ] 刷新页面后存档还在、数值正常（存档坏了是最高优先级的 bug）
- [ ] 顺手确认宠物栏、抽卡、商店、积分这些**没被你的改动影响**

## 五、打安装包（只有维护者需要）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File packaging\build.ps1 -GamePath "宠物养成游戏.html"
powershell -NoProfile -ExecutionPolicy Bypass -File packaging\deliver.ps1
```

产物会同步到 `release\`（安装包 / 绿色版 zip / 单文件 / 说明），然后把 `release\` 一起提交即可。

---

## 六、几点提醒

- 游戏本体是**一个很大的单文件**，两个人同时改容易冲突。建议：**一次 PR 只做一件事**，改动尽量集中；冲突了用 `git rebase origin/main` 解决，或直接在 PR 里喊维护者帮忙
- 涉及宠物名字/角色的新增内容，请保持原创像素画，不要直接搬官方素材
- 有想法但不打算写代码也欢迎 → 开个 [Issue](https://github.com/Eimgoueim/BaogooseGames/issues) 描述你想要的玩法/数值调整
- 大家友善交流，不欢迎针对个人、角色或群体的攻击性内容
