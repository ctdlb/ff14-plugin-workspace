# 框架学习总索引（Dalamud 生态）

> 建立于 2026-10-25。所有数据来自**本机实读源码**（clone 到 `.tmp\study\`，或本机知识库 `E:\FF14Dev\KnowledgeBase\`）+ `api.github.com` 核实。
> 星数、许可、规模都是当天实测；标「未核实」的是没查到的。**许可（license）一条最重要**——决定我们能不能把代码抄进自己的插件。
>
> **下一件事不是道具简介框？先看 [选型速查.md](选型速查.md)** —— 那份按「你要做什么」查库，这份索引按「有哪些库」查。

## 结论可信度分级（抄之前先看这一条）

本目录每条结论都标了来源，分三级，**用之前必须认这三级**：

1. **源码实证**：写了 `文件:行号`，且是打开源码读到的原文 → 可以直接用，但**用前最好照着行号再确认一次**（库会更新）。
2. **本机实测**：有日志原文 / 时间戳 / 产物大小 → 只对「本机 + 当时的版本」成立。
3. **推测 / 未核实**：正文里明写「推测」「未验证」「未核实」→ **不许当结论用**，用前必须自己验一次。

> 定这条是因为：一条「推测 KTK 的 `AnchorBottom` 能跟随父底边」如果被当成事实抄进下一个插件，会在游戏里花掉一整天。**标了「推测」的地方，就是留给下一任去验证的地方，不是可以省掉的步骤。**

## 一、先看清层次

「框架」在 Dalamud 生态里是四层不同的东西，混在一起比没意义：

| 层 | 解决的问题 | 代表 |
| --- | --- | --- |
| 0 运行时与构建 | 插件怎么被加载、怎么打包、怎么读游戏结构 | Dalamud、Dalamud.NET.Sdk、FFXIVClientStructs、Lumina |
| 1 原生 UI（ATK） | 往游戏自己的窗口里塞东西 / 自己造原生窗口 | **KamiToolKit**、OmenTools、Reatkact |
| 2 ImGui 界面 | 插件自己的设置窗口、表格、列表 | OtterGui、ImComponents、CkCommons、ImGuiOm（OmenTools 自带） |
| 3 通用工具 | 任务、Excel 数据、聊天、异步、3D 覆盖 | ECommons、CriticalCommonLib、Luna、pictomancy |

我们要做的事（往 `ItemDetail` 里插一行字并撑高）**只跟第 1 层有关**。

## 二、总表（按对我们的价值排序）

| 库 | 许可 | 规模（.cs / 行） | 能碰原生节点？ | 判定 |
| --- | --- | --- | --- | --- |
| **KamiToolKit** | **MIT** | 见 `KamiToolKit-深读.md` | ✅ 有 `AttachNode(AtkUnitBase*)`、`TextNode`、`Resize` | **值得**（唯一能干活的） |
| **OmenTools** | **MIT** | 581 / 60,432 | ⚠️ 只能取 addon、改扩展；**不能插节点** | **值得**（我们已在用，服务层 + `UpdateGroupPositions` 用法） |
| ECommons | **MIT** | 417 / 38,098 | ❌ `UpdateDrawNodeList` 零命中 | 值得当依赖省样板代码；不解决插节点 |
| OtterGui | **Apache-2.0** | 236 / 24,073 | ❌ 全库 `AtkUnitBase` 零命中 | 只抄设置窗口的几段 |
| CkCommons | **MIT** | 145 / 19,464 | ❌ `ItemDetail` 零命中 | 不值得（19k 行换 1 个判定函数） |
| CriticalCommonLib | **GPL** | 152 / 22,202 | ❌ `AddNode`/`CreateNode` 零命中 | 不值得（改文本数组路线 + GPL） |
| OmenTools.KamiToolKit | MIT | 29 / 2,938 | ❌ 贴边面板，不插入 | 不值得（三者必须同解决方案） |
| ImComponents | **GPL-3.0** | 5 / 344 | ❌ | 不值得（GPL + CN 路径不兼容） |
| Luna | **AGPL-3.0** | 368 / 44,585 | ❌ `Atk` 零命中 | **不要**（许可传染 + 子模块空编不过） |
| pictomancy | **AGPL-3.0** | 51 / 6,523 | ❌ 世界空间 3D，层级不对 | **不要** |
| Reatkact | **无 LICENSE** | 11 / 442 | 只能挂自己造 addon | **不要** |

## 三、结论：这一次（道具简介框）该用哪套

> 这一节只服务「往 ItemDetail 插一行字」这一个需求。**别的插件任务看 [选型速查.md](选型速查.md)。**

1. **UI 层只用 KamiToolKit**（MIT）：`AddonController` 绑 `ItemDetail`、`TextNode` 写文字、`AttachNode((AtkUnitBase*)addon)` 挂链——绘制名单它自己重建，不用我们手动调 `UpdateDrawNodeList`。
2. **撑高不要手搓**：`AddonItemDetail.UpdateGroupPositions(NumberArrayData*, StringArrayData*)`（`FFXIVClientStructs\...\Client\UI\AddonItemDetail.cs:136`）就是游戏自己的排版函数；OmenTools 已经在用它的完整链条（`OmenTools\OmenService\...\Tooltip\TooltipManager.cs:396-428`：设宽 → 开 `WordWrap` → `ApplyTextFlow` → `GetTextDrawSize` → `SetHeight` → `UpdateGroupPositions`）。
3. **其余库一律不引入**：ECommons 可以当「省样板」的可选依赖；OtterGui 只按文件抄几段设置窗口控件；AGPL / GPL / 无许可的三个（Luna、pictomancy、CriticalCommonLib、Reatkact）连抄代码都不行。
4. **不用 ProjectReference 引别人的库**——本工作区已有硬约束（两套 Dalamud SDK 属性互污染），统一走「引用编好的 dll」或 NuGet。

## 四、每个库的笔记

| 文件 | 内容 |
| --- | --- |
| [OmenTools.md](OmenTools.md) | 我们的底座：`DService` 生命周期、27 个 Manager、`AddonItemDetail` 与 `UpdateGroupPositions` 发现 |
| [KamiToolKit-深读.md](KamiToolKit-深读.md) | 能不能往别人的 addon 插节点、`Resize` 的能力边界、待实测 4 项 |
| [OtterGui.md](OtterGui.md) | Apache-2.0，纯 ImGui；可抄 `Raii/`、`ImGuiFramedGroup`、`Table<T>` |
| [ImComponents.md](ImComponents.md) | GPL-3.0，5 个文件，CN 环境编不过 |
| [ECommons.md](ECommons.md) | MIT，119 个 addon 封装（无 ItemDetail），`EzThrottler`/`Svc` 可抄 |
| [Luna.md](Luna.md) | AGPL-3.0，纯 ImGui 侧，`ImSharp` 子模块空 |
| [CriticalCommonLib.md](CriticalCommonLib.md) | GPL，数据层，走「改文本数组」路线 |
| [pictomancy.md](pictomancy.md) | AGPL，世界空间 3D 绘制 |
| [Reatkact.md](Reatkact.md) | 无许可，React→ATK，作者自己劝退 |
| [CkCommons.md](CkCommons.md) | MIT，纯 ImGui 工具箱 |
| [OmenTools.KamiToolKit.md](OmenTools.KamiToolKit.md) | MIT，KTK 的扩展库（贴边面板 + 控件图鉴） |

### 人物档案（按作者读，2026-10-25 起）

按「人」读，而不是按库读：同一个人维护的一堆库往往共享同一套做法与同一个坑。每条结论都带 `文件:行号`，可信度标注见各文件末节。

| 作者 | 笔记 | 学什么 | 许可提醒 |
| --- | --- | --- | --- |
| AtmoOmen | [人物/AtmoOmen.md](人物/AtmoOmen.md) | DailyRoutines 的模块生命周期与卸载时序、国服 SDK 与官方的差异、改原生 UI 的四种手法 | `DailyRoutines.Common` / `ModulesPublic` 是 **AGPL**（读得、抄不得）；CN SDK 是 MIT |
| MidoriKami | [人物/MidoriKami.md](人物/MidoriKami.md) | KTK 原版的接入顺序与「忘了调不报错」的坑、`AttachNode` 的真实用法、撑高能做到什么程度 | KTK 是 **MIT**；VanillaPlus / DailyDuty 未逐一核许可，抄前自己查 |
| Yarukon | [人物/Yarukon.md](人物/Yarukon.md) | opcode 表怎么用、收发双 hook、共享纹理把外部画面搬进游戏、包结构字典 | opcode 仓库**无 LICENSE**（数字是事实可用，整文件不要抄）；Browsingway GPL、Kawari AGPL |
| ocornut | [人物/ocornut-imgui.md](人物/ocornut-imgui.md) | ImGui 的 ID 机制、立即模式陷阱、表格/Child 布局、本机绑定比上游旧这件事 | 上游 **MIT** |

这轮读出来的三条跨作者结论（比单个库的结论更重要）：

1. **不用为了「国服」特意换 CN SDK**：与官方 `15.0.0` 只差 `Use_Dalamud_CN` 默认值、`DalamudLibPath` 的 Windows 分支拆成 `XIVLauncherCN\…` / `XIVLauncher\…` 两条、注释排版三处，包源仍是 nuget.org。真正的国服差异在 `<dev>` 目录那份 DLL 里（`人物/AtmoOmen.md`）。
2. **KTK 替我们做掉了两个坑**：挂链后自动 `UpdateDrawNodeList()` + `UpdateCollisionNodeList(false)`；`Dispose` 里先判 `IsFrameworkUnloading`、再带双 Dispose 守卫。但它**只清已经从 addon 摘下来的孤儿节点**，还挂着的不归它管（`人物/MidoriKami.md`）。
3. **原生 addon 没有「按内容自动撑高」的现成实现**：连 VanillaPlus 改原生窗也是「固定增量 + 手工搬滚动条/按钮/九宫格，再逐项还原」。再遇到撑高问题，不要以为有个库能一行解决（`人物/MidoriKami.md`）。

## 五、还没做的验证（下次动手前）

1. `ItemDetail` 的 `addon->WindowNode` 是否非 null（为 null 则 KTK 的 `Resize` 静默无效）——HaselDebug 一眼可看。
2. `UpdateGroupPositions` 能不能在我们插入自己的节点之后调用、会不会把我们的节点位置冲掉。
3. KTK 的 `TextNode` + `AddonController` 在 `ItemDetail` 上是否按预期工作（`OnUpdate` = `PostUpdate`）。
4. 不引 OmenTools 的纯 KTK 插件是否会在 `ExpansionInterop` 那步拿到 0 地址（`KamiToolKit` 自己不调 `ExpansionInterop.Initialize`）。

> 2026-10-25 补充：原来还有两项「未确认」，已离线查实，不再算待验证——① 本机 ImGui 绑定落在 **1.89.0～1.89.6**（`cimgui.dll` 有 `BeginTable`、无 `SeparatorText`/`ImGuiChildFlags`；上游 clone 是 1.93.1 WIP）；② 窗口布局持久化在 `%APPDATA%\XIVLauncherCN\dalamudUI.ini`（`Dalamud/Interface/Internal/InterfaceManager.cs:699`、`:724`）。细节见 [人物/ocornut-imgui.md](人物/ocornut-imgui.md)。

## 六、许可速查（抄代码前看一眼）

- 可以抄、只需保留声明：**MIT**（KamiToolKit、OmenTools、ECommons、CkCommons）、**Apache-2.0**（OtterGui，注意 NOTICE）。
- 抄了就传染：**GPL**（CriticalCommonLib、ImComponents）、**AGPL**（Luna、pictomancy，网络服务也算）。
- 完全不能抄：**无 LICENSE**（Reatkact）。
- **引用 NuGet / 编好的 dll** 与「抄源码」是两件不同的事：GPL/AGPL 的库即使是引用，分发时也要满足其条款（这一点属于法律问题，不是技术问题，真要用于发布前建议单独确认）。
