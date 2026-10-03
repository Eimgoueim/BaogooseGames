# 🐾 Baogoose Games · 包鹅养成

> **Godot 迁移状态：原生游戏已接入主要玩法。** 养成、商店、抽卡、地牢、音频和存档已接入，可打开 `godot/project.godot` 按 F5 游玩；原 HTML 保留为对照和现有发布入口。全 UI 跨引擎视觉仍需最终人工验收。详见 [迁移状态](docs/GODOT_MIGRATION.md) 和 [启动说明](godot/README.md)。

一个 **单文件 HTML** 的中国风 / Blue Archive 风格宠物养成小游戏：像素房间 + 抽卡 + 多宠同养 + 肉鸽地牢。
不需要服务器、不需要安装任何依赖，双击 `宠物养成游戏.html` 就能玩，**完全离线**。

![单文件](https://img.shields.io/badge/single--file-HTML-4fc9a8) ![无依赖](https://img.shields.io/badge/dependencies-0-8b7bff) ![平台](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-ffb340)

---

## 🎮 游戏内容

| 系统 | 说明 |
|---|---|
| 🏠 像素房间 | 整个窗口就是一间房。宠物会四处走动、拖到高处松手会掉下来并叫一声、抚摸/喂食/洗澡/睡觉/打工 |
| 🐾 多宠同养 | **首次进游戏只能选 1 只**，之后**每升 1 级解锁 1 个栏位**（上限 10 只），每升一级送 **50 信用点** |
| 🎰 抽卡 | 4 个限定卡池（保底：50 抽小保底 / 100 抽大保底），限定宠物只能靠抽卡解锁 |
| 🏆 积分兑换 · 🛒 商店 | 玩地牢/互动攒积分，兑换道具、饰品、装饰与称号 |
| 🎨 界面风格 | 6 套主题（樱花/海洋/森林/陶土/薄荷/夜），会一起存进存档 |
| 🛋️ 家具摆放 | 家具与饰品可自己拖动摆放位置、缩放（10 种家具 + 饰品佩戴 4 个部位） |
| 💾 存档 | localStorage 自动保存，支持导出/导入 JSON、下载备份 |

### 🎲 肉鸽地牢「宠物地牢」（参考《以撒的结合》）

- **5 层地牢**：9~11 间随机生成的房间，**每层必有 1 个宝箱房 + 1 个商店 + 1 个 BOSS 房**，邻近房间还会随机多连几条门（环形通路）
- **出战宠物就是主角**，用它自己的像素配色
- **操作**：`WASD` 移动 · `方向键 / IJKL` 四向射击 · 鼠标点击也能打 · **手柄**：左摇杆移动 + 右摇杆 / ABXY 射击，Start 退出
- **全屏开打**，地牢内嵌以撒式小地图（只显示探索过的房间 + 门连线）
- **宝箱**：普通宝箱 60% 出现，开出 💰信用点 +10 / ❤️回血 +1 / 🪙金币 +1；**金宝箱**给技能
- **金币**：清光一间房的怪 60% 掉 1 金币（也可从宝箱得到），**商店用金币买技能**
- **技能 8 种**：💪攻击 · ⚡射速 · 🔱弹幕 · 📌穿透 · 👟弹速 · 🎽移速 · ❤️生命 · ⚫弹体（商店只显示**类型**，不剧透名称）
- **BOSS**：血量与弹幕随层数增强；打死 BOSS 出现陷阱门 → 下一层；打通第 5 层通关奖励 **100 信用点**
- 怪物不会堵在门口，进门有 0.8 秒保护；出战消耗 10 精力

### 💰 信用点怎么来

- **首次打开游戏送 1000 信用点**（一次性，存档里记标记）
- 升级 +50 / 羁绊提升 +10×等级 / 打工 / 地牢里的宝箱与通关奖励

---

## 🚀 怎么玩

**方式一：下载 Release 里的安装包**（推荐）

1. 下载 `release/宠物养成游戏_安装包.exe`
2. 双击安装（会装到当前用户目录并创建开始菜单/桌面快捷方式）
3. 卸载：开始菜单里的「卸载宠物养成游戏」

**方式二：绿色免安装**

下载 `release/宠物养成游戏_绿色免安装版.zip`，解压后双击 `启动游戏.cmd`。

**方式三：直接用源码**

双击根目录的 `宠物养成游戏.html` 即可（需要现代浏览器，推荐 Edge / Chrome）。

---

## 🛠️ 从源码构建安装包

只有 Windows 需要，依赖：**PowerShell 5.1**（系统自带）+ `iexpress.exe`（系统自带）+ 可选 Python（用来生成图标）。

```powershell
# 1) 生成安装包与便携版到 packaging\out\
powershell -NoProfile -ExecutionPolicy Bypass -File packaging\build.ps1 `
  -GamePath "宠物养成游戏.html"

# 2) 同步到 release\（安装包 / 绿色版 zip / 单文件 / 说明）
powershell -NoProfile -ExecutionPolicy Bypass -File packaging\deliver.ps1
```

打包流程：`iexpress.exe` 生成自解压安装包（`install.ps1` 负责复制文件 + 建快捷方式 + 注册卸载项）。

```
packaging/
├─ build.ps1        # 复制游戏 HTML → 生成图标 → 写 IExpress .sed → 打包 exe → 便携版
├─ deliver.ps1      # 把产物同步到 release\ 并校验 SHA256
├─ make_icon.py     # 生成 PetGame.ico（纯 Python，无第三方库）
└─ src/             # 安装器模板：install/uninstall 脚本、启动 cmd、说明、图标
```

---

## 📁 目录结构

```
baogoose_game/
├─ 宠物养成游戏.html        # 🎮 游戏本体：单文件，所有 HTML/CSS/JS 都在里面
├─ release/                 # 📦 构建产物（安装包 / 绿色版 / 单文件 / 使用说明）
├─ packaging/               # 🛠️ Windows 打包脚本与安装器模板
└─ README.md
```

游戏本体约 **240 KB**，零外部依赖：所有像素画都是代码里用矩形画出来的，音频用 Web Audio 现场合成，
没有任何官方素材，可以放心分发。

---

## 📝 说明

- 目标浏览器：Edge / Chrome / Firefox 等现代浏览器（用到 Canvas 2D、Web Audio、localStorage）
- 存档在浏览器 `localStorage`（键名 `dsh-pet-game-v2`），换浏览器/清缓存会丢，建议在游戏内「💾 存档」页导出备份
- 游戏内的宠物名称致敬 Blue Archive 角色，但**美术全部为原创像素画**，与官方无关

---

## 🤝 一起开发

欢迎一起来改这个游戏！最快的上手方式：

```bash
git clone https://github.com/Eimgoueim/BaogooseGames.git
cd BaogooseGames
# 直接用浏览器打开 宠物养成游戏.html 就能玩，改完刷新页面即可
```

- 详细的贡献流程、代码约定、自测清单见 **[CONTRIBUTING.md](CONTRIBUTING.md)**
- 有想法不想写代码也可以开 [Issue](https://github.com/Eimgoueim/BaogooseGames/issues)
- 想加入协作（直接推分支 / review PR）请找仓库维护者 @Eimgoueim 把你加为 **Collaborator**
