# HaselDebug 上手指南

> 版本核对：v1.75.5.0，作者 Haselnussbomber。
> 上游源码（原始作者仓库）：<https://github.com/Haselnussbomber/HaselDebug>。
> 安装来源：本机从第三方插件库 <https://raw.githubusercontent.com/AtmoOmen/DalamudPlugins/main/pluginmaster.json> 安装，该库内是 **AtmoOmen 的 fork 镜像**（镜像仓库 <https://github.com/AtmoOmen/HaselDebug>，下载包 <https://github.com/AtmoOmen/HaselDebug/releases/download/1.75.5/latest.zip>），版本 1.75.5.0 与上游一致。换机找不到下载地址时，把这条插件库地址加进 Dalamud 的「插件库」设置，即可搜到 HaselDebug；想追原始代码则看上游仓库。
> 本文结论均指得到源码文件与行号；推测已标注「推测」。

## 它是什么

**只读观测工具**。游戏 UI 的内部结构（ClientStructs 定义的那些结构体）在内存里是一棵棵树，HaselDebug 把这些树按字段展开给你看，还能点地址跳转、看网络包、看数据表。

- 它**不能**改任何值。
- 它**不能**告诉你「某个节点是哪个插件加的」——遇到多个插件同时改同一个 addon，必须一次只开一个。

## 打开方式

| 方式 | 操作 |
|---|---|
| 命令 | 游戏里输入 `/haseldebug`（命令说明：Show/hide the HaselDebug window） |
| 插件列表 | 插件卡片上点「打开」 |
| 开发菜单 | 默认已加进 `/xldev` 菜单栏（配置项 `Config.ShowInDevMenu`） |

**界面只有英文和德文**（`HaselDebug/Translations.json` 里只有 `en` / `de`，无 zh-CN）。找功能要认英文名。

## 界面骨架

```
┌─────────────┬────────────────────────────┐
│ 左边：标签树 │ 右边：内容（表格 / 结构体树） │
└─────────────┴────────────────────────────┘
```

右侧凡是**可点的地址**都能点：点地址 → 开一个跟着这个指针走的新窗口；点结构体字段 → 展开更深一层。这是它的核心交互。

## 标签分类（`HaselDebug/Tabs/`）

| 类别 | 标签 | 用途 |
|---|---|---|
| UI / ATK | `Addon Inspector` | **最常用**：列所有已加载 addon，点进去看 RootNode 树与 Node List |
| | `Addon Names` | addon 的 id ↔ 名字对照 |
| | `Addon Factories` | 各 addon 的创建工厂 |
| | `Atk Events` | addon 注册的事件与触发情况 |
| | `Atk Handler Calls` | 游戏内部调用记录 |
| | `Atk Array Data` | Atk 数组数据 |
| | `Layout Inspector` | 场景布局引擎，**与 UI addon 无关** |
| | `Address Inspector` | 手输地址看内存 |
| 对象表 | `Object Tables` + 8 个子表（GameObject / Character / ClientObject / EventObject / StandObject / ReactionEventObject / CharaSelectCharacterList / ClientObjectManager） | 游戏对象 |
| 数据表 | `Excel` | 游戏数据表（物品、任务、天气…） |
| 解锁 | `Unlocks` + 20 多个子表（成就、坐骑、宠物、鱼、任务、乐曲…） | 解锁状态 |
| 网络 | `Packet Logs` + 15 个子表 | 收发记录 |
| 杂项 | `Inventory` `Item Action` `Input` `Chat` `Conditions` `Currency Manager` `Fate` `Housing` `Local Player` `Target` `Sound Manager` `UI Color` `Toast` `Permissions` `Config` `Instances` `Agents` 等 | 各自领域状态 |

## 三个核心操作

### ① Addon Inspector —— 看「里面有什么」

左侧搜索框输 `ItemDetail`（或任意 addon 名）→ 点它 → 右侧出现两块：

| 块 | 内容 |
|---|---|
| **RootNode 树** | 从根节点往下展开，可看父子与兄弟链 |
| **`Node List`**（标题偏红） | 按 `UldManager.Nodes` 顺序列出所有节点，前缀 `[0] [1] [2] …` |

源码依据：`Services/AtkDebugRenderer.cs:241-278` —— 遍历 `unitBase->UldManager.Nodes`，每项打印 `[{j}]`。**这是唯一能直接看到绘制名单顺序的地方。**

节点太多时，Node List 上方还有独立搜索框可过滤（如输 `32615` 找指定 NodeId）。

### ② Node Picker —— 鼠标点游戏里的东西

Addon Inspector 搜索框右侧的**拾取图标**（提示 `Pick Addon/Node`）。点亮后：

1. 进入全屏拾取模式，鼠标指到哪，就列出底下所有层级的节点
2. 按 `Depth Layer` 分组，从最上层开始列
3. **滚轮**切换选中项，点一下 → 打开 `Node Inspector` 看该节点全部字段

源码：`Services/AtkNodePicker.cs`（遍历 `RaptureAtkUnitManager->AllLoadedUnitsList`，用 `GetWindowBounds` 判光标命中）。

### ③ Node Inspector —— 看单个节点的全部字段

给一个节点的完整结构体：坐标、大小、颜色、`NodeId`、`NodeFlags`、可见性，以及 `ParentNode` / `ChildNode` / `PrevSiblingNode` / `NextSiblingNode` 指针。

源码：`Windows/NodeInspectorWindow.cs` → `AtkDebugRenderer.DrawNode()`（800×600 窗口，`NoSavedSettings`）。

**这是判断「节点挂在链的哪个位置」最可靠的途径**——比看编号推顺序更直接。

## 相关的观察窗口

| 窗口 | 用途 |
|---|---|
| `NodeInspectorWindow` | 选中节点的结构体树 |
| `AddonInspectorWindow` | 从 addon 列表独立开窗 |
| `AddonEventsObserverWindow` | 观察某 addon 的事件触发 |
| `AddonAtkValuesObserverWindow` | 观察某 addon 的 AtkValues |
| `EntityInspectorWindow` | 实体（对象）字段 |
| `PointerTypeWindow` | 跟随指针读类型 |

## 能给 / 不能给

| 能 | 不能 |
|---|---|
| addon 是否加载、尺寸多少 | 改任何值（只读） |
| 每个节点的坐标 / 大小 / 颜色 / NodeId / 可见性 | 读插件源码 |
| 父、子、兄弟链的完整指针 | 标注「这个节点是哪个插件加的」 |
| 绘制名单顺序 `[i]` | 解释作者的意图 |
| 事件是否触发、AtkValues 是多少 | |

> 注：多个插件同时修改同一个 addon 时，它不标注节点来源，需一次只开一个插件；`[编号]` 与绘制先后的对应关系尚未实测确认（推测：编号小＝先画，可用 Node Picker 点一个已知在上的节点比对）。

## 常用操作备忘

| 想做的事 | 步骤 |
|---|---|
| 查某 addon 在不在 | 命令 → `Addon Inspector` → 搜名字 |
| 看某节点的坐标大小 | 拾取图标 → 悬停该元素 → 滚轮选层 → 点击 |
| 看绘制名单顺序 | `Addon Inspector` → 选 addon → 展开 `Node List` |
| 看某节点挂在哪条链上 | `Node Inspector` 里点 `ParentNode` / `PrevSiblingNode` 地址 |
| 看事件有没有触发 | `Atk Events` → 选 addon → 看条目 |
