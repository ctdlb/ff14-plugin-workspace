# MidoriKami（KamiToolKit 原版作者）调研笔记

调研时间 2026-10-25。全部结论来自源码；`.tmp/study/MidoriKami/` 下四个仓库 `--depth 1` 克隆（HEAD 见下表）。所有 `文件:行号` 相对各自仓库根。

## ① 一句话定位

KamiToolKit（KTK）是 FF14 原生 UI 的 C# 封装库：把 `AtkResNode`/`AtkUnitBase` 包成 `NodeBase`/`NativeAddon`，用「对象 + 属性」造节点、挂到游戏自带 addon、或整窗自建；MidoriKami 用「库（KTK）+ 示例（Demo）+ 大合集（VanillaPlus）+ 业务插件（DailyDuty）」四个仓库把这条路走完整了。

## ② 仓库清单

| 仓库 | 星数 | 最近提交（克隆时 HEAD） | 一句话作用 |
| --- | --- | --- | --- |
| KamiToolKit | 38 | 2026-10-14 22:11 `1eaccb5` "Remove Experimental code" | 库本体，228 个 `.cs`。节点封装、原生 addon 封装、控制器、布局节点、自绘组件 |
| KamiToolKitDemo | 11 | 2026-08-01 17:15 `5efc66c` "Update README.md" | **已归档**的官方示例；只演示「自建窗口 + 控件」，不演示挂原生 addon，且用的初始化 API 已被删（见 Q4） |
| VanillaPlus | 25 | 2026-10-24 08:26 `a401812` "Version 1.4.5.12" | 几十个「改原生 UI / 加原生元素」的小改动合集，KTK 的真实用法大全，**替代 Demo 看这个** |
| DailyDuty | 47 | 2026-10-16 06:45 `51f5eaf` "Update KTK" | 业务型插件（日常/周常追踪），模块组织与 KTK 原生配置窗的另一套写法 |

已有 `docs\框架学习\KamiToolKit-深读.md` 基于**国服分支**（`E:\FF14Dev\KnowledgeBase\KamiToolKit`，HEAD `138cc86`，2026-10-24），本笔记只补它没覆盖的部分，并在 Q6 列出两分支差异。

## ③ 六个问题

### Q1 接入方式：初始化、卸载、顺序要求

**初始化只有一个入口**：

```csharp
// KamiToolKit/KamiToolKitLibrary.cs:51
public static async Task InitializeAsync(IDalamudPluginInterface pluginInterface, string? defaultWindowSubtitle = null)
```

同文件 :47-50 的 XML 注释是作者自己写下的最重警告：

> required to be invoked before any KamiToolKit features are used. Failure to do so will not result in any direct warnings, but will result in undefined behavior.

即「忘了初始化」不会报错，会变成随机崩溃/随机失效——这是排查时第一个该排除的变量。

内部动作（`KamiToolKit/KamiToolKitLibrary.cs`）：:56 `PluginInterface.Create<Services>()`（后面所有 `IPluginLog.Get()`/`IFramework.Get()` 静态服务都靠它）；:57 `IGameInteropProvider.Get().InitializeFromAttributes(Experimental)`；:60 `AllocatedNodes = PluginInterface.GetOrCreateData(NodeDataShareKey, ...)` 建**全进程共享**的节点登记表（多个用 KTK 的插件共用同一份）；:63 `IPluginLog.Get().MinimumLogLevel = LogEventLevel.Verbose`（:62 注释说明是**故意**的：「Force enable Verbose so that users are able to get advanced logging information on request」）；:65 打一条初始化日志；:67 读 addon 配置；:69 `await IFramework.Get().Run(NativeAddon.InitializeCloseCallback)`；:71 `RegisterDebugHelpers()`（仅 DEBUG，定义在 :99，注册 `/ktkdebug_{InternalName}`）。

`SetResourceManager(ResourceManager)`（:77）用于窗口标题本地化，两个真实插件都紧跟初始化调用：`VanillaPlus/VanillaPlus/VanillaPlus.cs:27`、`DailyDuty/DailyDuty/DailyDutyPlugin.cs:20`。

**卸载有两条路，都必须主线程**：

- `public static void Dispose()`（`KamiToolKitLibrary.cs:124`）：:125-128 先判主线程，**不在主线程只打一条 Error 就 return，什么都不清理**；:138-144 才是 `WarnLeakedNodes` / `WarnLeakedAddons` / `DisposeAddons` / `DisposeNodes` / `RelinquishData`。
- `public static async Task DisposeAsync()`（:150）：内部全部 `await IFramework.Get().Run(...)`，:159-165 同样的清理，所以**非主线程也能安全调**。

**顺序要求（源码可证的两条硬约束）**：

1. `InitializeAsync` 必须是入口方法的第一件事：`VanillaPlus/VanillaPlus/VanillaPlus.cs:26` 在任何 `NativeAddon` 构造之前，`DailyDuty/DailyDuty/DailyDutyPlugin.cs:19` 甚至在本地化设置（:22）之前。
2. `KamiToolKitLibrary.DisposeAsync()` 必须是卸载的最后一步：`VanillaPlus.cs:85`（在配置浏览器窗口、赛季窗口、ModificationManager 各自 DisposeAsync 之后）、`DailyDutyPlugin.cs:69`（在配置窗、ModuleManager 之后）。
   - 原因在源码里：`DisposeAsync` 会 `DisposeAddons`（:162）+ `DisposeNodes`（:163）。你自己还活着的界面如果留到它之后再收，节点可能已经被它清理过；`NodeBase.Dispose` 有 double-dispose 与「节点已失效」两道兜底（见 Q6），但那是兜底，不是设计意图。

**入口类必须用 `IAsyncDalamudPlugin`**，因为初始化是异步的：`VanillaPlus.cs:17` `public sealed class VanillaPlus : IAsyncDalamudPlugin`；:20 `public async Task LoadAsync(CancellationToken cancellationToken)`；`DailyDutyPlugin.cs:15` 同。卸载对应 `public async ValueTask DisposeAsync()`（`VanillaPlus.cs:71`、`DailyDutyPlugin.cs:55`）。

**"顺序错了就崩"的三条实证/半实证**：

1. **主线程**：KTK 的节点构造第一行就是 `ThreadSafety.AssertMainThread()`（`KamiToolKit/BaseTypes/NodeBase/NodeBase.cs:31`），非主线程直接抛 `InvalidOperationException("Not on main thread!")`（`Dalamud/Dalamud/Utility/ThreadSafety.cs:25-31`）。所以「在 `Task.Run` 里 new 一个 TextNode」会立刻炸。
2. **初始化前用节点**：不报错（:47-50），表现为 undefined behavior。
3. **控制器没禁用就卸载插件**：`AddonController` 通过 `IAddonLifecycle.RegisterListener` 注册（`KamiToolKit/Controllers/AddonController.cs:64-83`），只在 `Disable()`/`DisableAsync()` 里 `UnregisterListener`（:136、:148）。插件卸载时若没调这两个，listener 仍留在 Dalamud 里指向已卸载程序集的委托（**推测**：下次 addon 事件会踩空崩溃；机制上「没注销」是源码事实）。

另一个易踩的时序点：**`EnableAsync` 会在 addon 已经开着时立即补调一次 `OnSetup`**（`AddonController.cs:94-128`，同步版 :86-88 `if (AddonPointer is not null) OnSetup?.Invoke(AddonPointer)`）。所以 `OnSetup` 必须是幂等的（重复进入不能重复造节点）。

### Q2 挂到游戏自带 addon

**`AttachNode` 的完整重载表**（`KamiToolKit/BaseTypes/NodeBase/NodeBase.Linking.cs`）：

| 行 | 目标类型 | 默认位置 |
| --- | --- | --- |
| :21 | `NativeAddon?` | `AsLastChild` |
| :25 | `AtkUnitBase*` | `AsLastChild`（内部转 `PerformNativeAttach(targetAddon->RootNode, ...)`） |
| :32 | `NodeBase?` | `AsLastChild` |
| :36 | `AtkResNode*` | `AsLastChild` |
| :40/:44/:48/:52/:56/:60 | `AtkImageNode*` / `AtkTextNode*` / `AtkNineGridNode*` / `AtkCounterNode*` / `AtkCollisionNode*` / `AtkClippingMaskNode*` | `AsLastChild` |
| :64 | `AtkComponentNode*` | **`AfterAllSiblings`**（组件不能当父节点，只能插到它旁边） |

`NodePosition` 的方向语义与直觉相反，注释写得很明确（`KamiToolKit/Enums/NodePosition.cs`）：

- `BeforeTarget`（:7-10）= 插成目标的 **NextSibling** → **渲染在目标下面**
- `AfterTarget`（:12-15）= 插成目标的 **PrevSibling** → **渲染在目标上面**
- `BeforeAllSiblings`（:17-20）= 目标父节点的第一个子节点 → 压在所有兄弟下面
- `AfterAllSiblings`（:22-25）= 最后一个子节点 → 压在所有兄弟上面
- `AsLastChild` / `AsFirstChild`（:27-35）= 目标自己的子节点首尾

底层由 `KamiToolKit/Internal/Classes/NodeLinker.cs:8-40` 执行，未知枚举 `throw new ArgumentOutOfRangeException`。挂载后 `UpdateNative()`（`NodeBase.Linking.cs:215-246`）负责：`MarkDirty()`（:220）→ `ParentUldManager->AddNodeToObjectList(this)`（:227）→ 子节点继承 UldManager（:229-231）→ `TextNode{TextId:not 0}` 时 `SetupText()`（:233-235）→ **`ParentAddon->UldManager.UpdateDrawNodeList(); ParentAddon->UpdateCollisionNodeList(false);`（:243-244）**。也就是说「挂上去」这一步 KTK 已经帮你重建了绘制名单，不需要自己再调。

**写法一：`AddonController` + 挂到 addon 根**（最常见）

`VanillaPlus/VanillaPlus/Features/ArmourySearchBar/ArmourySearchBar.cs`：

- :38-46 `OnEnableAsync` 里 `inventoryController = new AddonController { AddonName = "ArmouryBoard", OnSetup = OnArmourySetup, OnFinalize = OnArmouryFinalize, OnPreUpdate = OnArmouryUpdate }`（`new` 外面的 `unsafe { }` 是为了 `AtkUnitBase*` 委托）
- :57 `await inventoryController.EnableAsync();`
- :67-68 `OnDisableAsync` 里 `await inventoryController.DisposeAsyncSafe(); inventoryController = null;`
- :71-83 `OnArmourySetup(AtkUnitBase* addon)`：位置用 `addon->WindowHeaderCollisionNode->Width/Height` 算（:73），尺寸取 `addon->Size.X / 2`（:72），`:80 searchInputNode.AttachNode(addon);`（默认 `AsLastChild` → 挂到 addon 根节点末尾，压在最上层）
- :85-92 `OnArmouryFinalize(AtkUnitBase* addon)`：`searchInputNode?.Dispose(); searchInputNode = null;`——**这是全项目统一的收尾写法**

为什么位置这么算：它要把搜索框塞进窗口标题栏，所以直接用标题碰撞节点尺寸做锚（`ArmourySearchBar.cs:73-77`），而不是硬编码坐标。

**写法二：挂到某个具体原生节点旁边**（想压在某块 UI 上/下时必须这样）

- `VanillaPlus/VanillaPlus/Features/WindowBackground/WindowBackground.cs:107-111`：有 `addon->WindowNode` 时，先在它的组件里找九宫格（:191-200 遍历 `UldManager.Nodes` 找 `NodeType.NineGrid`），再 `newNode.AttachNode(targetNode, NodePosition.BeforeTarget)` → **垫在窗口背景下面**（放自绘图当背景）。没 WindowNode 的 addon 退回 `OverlayController`（:113-116）。
- `VanillaPlus/VanillaPlus/Features/AetherwellProgress/AetherwellProgress.cs:79`：`imageNode.AttachNode(existingImageNode, NodePosition.AfterTarget);` → 画在原图**之上**。
- `VanillaPlus/VanillaPlus/Features/BetterInterruptableCastBars/BetterInterruptableCastBars.cs:90`：`AttachNode(existingPulseNode, NodePosition.BeforeTarget)` → 垫在脉冲动画**下面**。
- `VanillaPlus/VanillaPlus/Features/ConfigSearchBar/TabEntry.cs:33`：`highlightNode.AttachNode(dropDownComponentNode, NodePosition.AfterTarget);` → 高亮压在组件上（组件节点只能旁挂）。
- 其它挂 addon 根的实例：`Features/ConfigSearchBar/SystemConfigSearchBar.cs:97`、`Features/CosmicExplorationProgressWindow/CosmicExplorationProgressWindow.cs:76`、`Features/AprilFools/IndecisiveFools.cs:74`（`AttachNode(&addon->AtkUnitBase)`，对 `AtkUnitBase` 结构体取址）、`Features/MacroLineNumbers/MacroLineNumbers.cs:62`。

**写法三：`NativeAddon`（自建窗口）+ `AddNode`**

- `VanillaPlus/VanillaPlus/Native/Addons/ConfigAddon.cs:13` `public class ConfigAddon : NativeAddon`；:23 `protected override unsafe void OnSetup(AtkUnitBase* addon, Span<AtkValue> atkValueSpan)`（注意有**两个参数的版本**）；:34 `configurationListNode.AttachNode(this)`（挂到 NativeAddon）。
- Demo 版（一参数）：`KamiToolKitDemo/KamiToolKitDemo/Demos/AddonWidgetDemo.cs:7` `: NativeAddon`；:25 `protected override unsafe void OnSetup(AtkUnitBase* addon)`；:39 `scrollingAreaNode.AttachNode(this);`。
- 便捷方法：`KamiToolKit/BaseTypes/NativeAddon/NativeAddon.Functions.cs:112-123` `AddNode(ICollection<NodeBase>)` / `AddNode(NodeBase?) => node?.AttachNode(this)`。
- 公开 `Enable()` 之外，`NativeAddon` 的 `WindowNode`（`KamiToolKit/BaseTypes/NativeAddon/NativeAddon.cs:38`）是 `protected`——外部插件改不了别人 addon 的 WindowNode，只能通过 `addon->WindowNode` 原生指针。

**一个反例（说明"能不能挂"的边界）**：`AddonController` 对 `"NamePlate"` 直接抛异常（`AddonController.cs:28-36`：`throw new Exception("Attaching to NamePlate is not supported. Use OverlayController Instead")`），`AttachNode` 自己只在 `UpdateNative` 里打 Warning（`NodeBase.Linking.cs:239-241`）。铭牌要用 `OverlayController`。

### Q3 撑高/改尺寸：所有入口，以及"内容变长就撑高"有没有人做

**能改 addon 尺寸的入口，一共 5 类**：

1. `addon.Size = v` / `addon.Resize(v)`（`KamiToolKit/Extensions/AtkUnitBaseExtensions.cs`）：:15-18 `Size` setter 转调 `Resize`；:43-58 实现 = 改 `WindowNode` 宽高（:47-48）→ 标题碰撞宽度 `newSize.X - 14.0f`（:50-52）→ `addon.SetSize((ushort)X, (ushort)Y)`（:54）→ `WindowNode->Component->UldManager.UpdateDrawNodeList()`（:56）→ `addon.UpdateCollisionNodeList(false)`（:57）。**`WindowNode` 为 null 时静默 return（:44-45），尺寸不会变也不报错**——没有 WindowNode 的 addon（HUD 类）根本不能这样改。
2. `addon->Size += delta`：走同一个 setter（`extension(ref AtkUnitBase)` 的属性）。**真实项目全部用这种写法**：`grep -rn "\.Resize("` 在 VanillaPlus / DailyDuty / Demo 三个仓库**零命中**。
3. `NativeAddon.SetWindowSize(Vector2)`（`NativeAddon.Functions.cs:139-146`）：`Size = windowSize; InternalAddon->SetSize(...); WindowNode?.Size = Size;`——只对自建 addon 有效。派生类在 `OnSetup` 末尾调它定初始尺寸（`ConfigAddon.cs:63`、`Addons/ColorPickerAddon.cs:73`）。
4. `NativeAddon.UpdateAnchoringLayout()`（`NativeAddon.cs:19-23`）：`=> SetWindowSize(Size)`，注释原话「Triggers a window update via AtkUnitBase.SetSize(...), to have the game recalculate NodeFlags.Anchor{Direction}」——**KTK 作者自己承认 Anchor 标记要靠一次 SetSize 才会重算**。
5. 节点级尺寸：`NodeBase.Properties.cs:76`/`:95` 等（`SetWidth`/`SetHeight`），加上布局节点的 `FitContents`（`Nodes/Layout/VerticalListNode.cs:50`，:96-98 `Height = NodeList.Sum(...)`；`TabbedVerticalListNode.cs:122` 默认 true；`ListBoxNode.cs:43/102/108`）。

**"内容变长就撑高"的唯一真实实现**（自建窗口，不是原生 addon）：

`VanillaPlus/VanillaPlus/Native/Addons/ConfigAddon.cs:51-73 RecalculateWindowSize()`：

```csharp
configurationListNode.RecalculateSizes();                                    // :54 先让内容算好
if (configurationListNode.ContentNode.Height < MaximumHeight)                // :56
    Size = new Vector2(Width, ContentNode.Height + ContentStartPosition.Y + 24.0f);  // :57
else
    Size = new Vector2(Width, MaximumHeight + ContentStartPosition.Y + 24.0f);       // :60
SetWindowSize(Size);                                                         // :63
configurationListNode.Size = ContentSize + new Vector2(0.0f, ContentPadding.Y);      // :65
configurationListNode.Position = ContentStartPosition - new Vector2(0.0f, ContentPadding.Y); // :66
configurationListNode.RecalculateSizes();                                    // :67 再让内容按新容器重排
```

常量在 :20-21（`MaximumHeight = 400f` / `Width = 400f`），`OnSetup` 末尾调用（:48）。**模式值得直接抄**：内容重算 → 读内容高度 → 加内容起点与底部留白 → 设窗口高 → 再重排容器（先定框再排内容，否则内容按旧尺寸算）。

**原生 addon 侧：全是固定增量 + 手工改子节点**（没有一个是内容驱动）：

- `VanillaPlus/VanillaPlus/Features/BiggerConfigWindows/SystemConfigController.cs:34-56`（最完整的一套）：
  - :35-39 **先判屏幕够不够**：`AtkStage.Instance()->ScreenSize.Height < addon->Size.Y + Config.SystemConfigAdditionalHeight` 就 `IChatGui.Get().PrintError(...)` + `IPluginLog.Get().Warning("Unable to resize config window, height would be too big.", "BiggerConfigWindow")` 然后不干——**这是防「撑出屏幕」的范本**
  - :41 `addon->Size += new Vector2(0.0f, delta);`
  - :44-49 遍历 `scrollBarIdList`（:15 `[17, 89, 286, 507]`）各 `GetComponentById<AtkComponentScrollBar>(id).ResizeHeight(delta)`；`ResizeHeight` 的实现很值得抄（`VanillaPlus/VanillaPlus/Extensions/AtkComponentScrollBarExtensions.cs:8-30`）：父容器、滚动条自身、内容父节点、内容碰撞节点四处 `Size +=`（:15-18），再改内部滚动数学 `EmptyLength` / `ScrollMaxPosition` / `ContentNodeOffScreenLength` / `ScrollbarLength`（:20-23），按 `ScrollMaxPosition > 0` 切可见性（:25），位置不在底部时 `SetScrollPosition(0)`（:27-29）
  - :52 **按钮容器 `addon->GetNodeById(588)->Position += new Vector2(0, delta)`**（注释："Default"/"Apply"/"Close"）
  - :55 **竖分隔线九宫格 `addon->GetNodeById(15)->Size += new Vector2(0, delta)`**（注释："vertical line ninegridnode"）
  - :58-74 `Finalize` 用负 delta 全部反向还原——**能开关的前提**，漏一个就会残留
- `VanillaPlus/VanillaPlus/Features/BiggerConfigWindows/CharacterConfigController.cs:63/69/73/79`：同法，改 `addon->GetNodeById(34)`。
- `VanillaPlus/VanillaPlus/Features/BetterEmoteWindow/BetterEmoteWindow.cs`：:52-55 隐藏描述面板 `GetNodeById(11)`；:58-63 把 4/16/21/41 号节点上移；:66-70 `GetComponentListById(4)->OwnerNode->AtkResNode.Size +=` 并 `SetVisibleRowCount(+3)`；**:73 `addon->Size += new Vector2(0.0f, 5.0f);` 上面注释就写着 `// Trigger layout update`**；:100 卸载时 `-=` 5f。
  这条最有信息量：改完一堆子节点后，**必须再触发一次尺寸写入**游戏才会重排。等价于 KTK 内部 `UpdateAnchoringLayout()` 的思路，但这里是 +5 再不动（作者用「比实际多 5px」当触发器）。
- `VanillaPlus/VanillaPlus/Features/GearSetReorderButtons/GearSetReorderButtons.cs:87/106`：列表组件 `Size += / -= (ExtraAddonWidth, 0)`（横向）。

**九宫格背景与提示行有没有人真的处理？——有，但只在"改一个自带输入框组件"这个尺度上。**

`VanillaPlus/VanillaPlus/Features/MacroLineNumbers/MacroLineNumbers.cs:83-114 RepositionNode(AtkComponentNode*, Vector2 offset)`：宏窗口的输入框要变高 150px（:25 `sizeOffset = new(20f, 150f)`），于是把组件里**六个部件一起改**：

- :84-88 取指针：`SearchNodeById<AtkCollisionNode>(20)`、`<AtkNineGridNode>(19)`（背景）、`<AtkNineGridNode>(18)`（边框）、`<AtkTextNode>(17)`（`remainingLineNode` = **剩余行数提示文字**）、`<AtkTextNode>(16)`（正文）
- :90 任一为 null 直接 return（**没有部件就整体放弃，避免半改**）
- :93-94 `GetPositionFloat` / `SetPositionFloat` 移动组件本身
- :96-97 组件 `SetWidth/SetHeight`
- :99-100 碰撞节点、:102-103 背景九宫格、:105-106 边框九宫格、:108-109 正文文本框
- :111-113 **`remainingLineNode` 上移并改宽**（这就是"提示行"：它不跟着变高就会浮在中间）

取窗口九宫格的通用方法：`WindowBackground.cs:191-200`——遍历 `windowNode->Component->UldManager.Nodes`，第一个 `NodeType.NineGrid` 就是背景。

**结论（对我们的「道具简介框自适应」）**：

- KTK **只保「框」**：`Resize` 会同步 `WindowNode` 与标题碰撞，并重建绘制名单；它**不改**九宫格背景纹理、不改各级 `RootNode`、不移动任何内部提示行。
- 真实项目里**没有**「原生 addon 内容变长 → 自动撑高 → 九宫格与提示行跟着改」的现成代码。距离最近的只有两段：`ConfigAddon.RecalculateWindowSize`（自建窗内容驱动撑高）和 `MacroLineNumbers.RepositionNode`（手工同步九宫格 + 提示行）。两者都得自己拼。
- 撑高原生窗的三件事因此是：① `addon->Size +=`（KTK 代劳 WindowNode + 名单）② 九宫格背景自己 `SetHeight`（或用 `WindowBackground` 那套找 NineGrid）③ 提示行/按钮/分隔线自己 `Position +=`；最后再补一次尺寸写入逼游戏重排（`BetterEmoteWindow.cs:73` 的 +5 技巧）。

### Q4 KamiToolKitDemo 最小骨架（以及它已经不能照抄的地方）

**Demo 已归档**：`KamiToolKitDemo/README.md:1-3` 全文就是「# This repository is archived / A better code reference on how to use KTK can be found in [VanillaPlus](...)」。

文件与行（`KamiToolKitDemo/KamiToolKitDemo/KamiToolKitDemo.cs`，69 行）：

- :11 `public sealed class KamiToolKitDemo : IDalamudPlugin`；:12 构造 `(IDalamudPluginInterface pluginInterface)`；:13 `pluginInterface.Create<Services>();`
- :15-16 注释：「Native Controller is required for injecting KamiToolKit elements into the native UI / It provides tracking and safety features that ensure the stability of the game when manipulating native elements」
- **:17 `KamiToolKitLibrary.Initialize(pluginInterface, "KamiToolKit Demo");` ← 这个 API 在上游已被删除**（`grep "static.*Initialize("` 零命中），所以 Demo **不能直接编译**，必须换成 `await KamiToolKitLibrary.InitializeAsync(...)` 并把入口改成 `IAsyncDalamudPlugin`
- :19-23 `new AddonWidgetDemo { InternalName = "AddonWidgetDemo", Title = "Widget Demo", Size = new Vector2(750f, 750f) }`
- :26 `Open()`；:29-31 注册 `/widget` 命令；:33-34 `UiBuilder.OpenConfigUi/OpenMainUi += Toggle`
- :45-54 `Dispose()`：先退两个事件 → :50 `System.AddonWidgetDemo.Dispose()`（注释「Disposing our Addon will close it and remove it from the game」）→ :53 `KamiToolKitLibrary.Dispose()`
- :61-65 `public class Services` 三个 `[PluginService] static` 属性

Demo 的内容层（`Demos/AddonWidgetDemo.cs`）：:7 `: NativeAddon`；:25 `OnSetup(AtkUnitBase* addon)`；:27-39 造 `ScrollingAreaNode<TreeListNode>`（`Position = ContentStartPosition`、`Size = ContentSize`、`ContentHeight = 2000f`）并 `AttachNode(this)`；:41 内容高度联动 `OnLayoutUpdate = newHeight => scrollingAreaNode.ContentHeight = newHeight`。

**Demo 缺的那一块**：15 个 `Demos/*.cs` 全是控件演示，**没有一行「往原生 addon 插节点」**。这块只能看 VanillaPlus（见 Q2），`MacroLineNumbers.cs` 是最短的完整样本（115 行）。

**文件数**：真正的最小可跑工程 = 3 个文件（`<Name>.csproj` + `Plugin.cs` + 一个功能类）。`csproj` 两个关键点：`Sdk="Dalamud.NET.Sdk/15.0.0"`（`DailyDuty/DailyDuty/DailyDuty.csproj:1`）与 KTK 的引用方式——**KTK 不在 NuGet**，两个真实项目都是 submodule + `ProjectReference`：`DailyDuty/DailyDuty/DailyDuty.csproj:7` `<ProjectReference Include="..\KamiToolKit\KamiToolKit.csproj" />`，`VanillaPlus/VanillaPlus/VanillaPlus.csproj:22-24` 同时引 `KamiToolKit.Components` + `KamiToolKit`（外加 `PackageReference LuminaSupplemental.Excel 5.1.5`）；子模块声明见 `VanillaPlus/.gitmodules:1-6`、`DailyDuty/.gitmodules`。

### Q5 VanillaPlus 的组织方式：几十个小改动怎么管

**一句话：反射扫描 + 基类契约 + 每模块一份配置 + 状态机 + 错误隔离。没有手写注册表。**

1. **零清单注册**：`VanillaPlus/VanillaPlus/Classes/ModificationManager.cs:201-209`

   ```csharp
   private static List<GameModification> GetGameModifications() => Assembly
       .GetCallingAssembly().GetTypes()
       .Where(type => type.IsSubclassOf(typeof(GameModification)))
       .Where(type => !type.IsAbstract)
       .Select(type => (GameModification?)Activator.CreateInstance(type))
       .Where(modification => modification?.ModificationInfo.Type is not ModificationType.Hidden)
       .OfType<GameModification>().ToList();
   ```

   新增一个功能 = 新增一个 `Features/<名字>/<名字>.cs : GameModification` 文件；删文件即下线。`ModificationType.Hidden` 用来放内部不展示的模块（:207）。模块**名字自动取类型名最后一段**：`Classes/GameModification.cs:30` `public string Name => LongName.Split(".").Last();`（:31 `LongName => GetType().ToString()`）。
   *（副作用坑：改类名 = 配置里的启用状态丢失，因为持久化按 Name 存，见 `ModificationManager.cs:141` `SystemConfig.EnabledModifications.Add(modification.Name)`。）*

2. **基类契约极薄**（`Classes/GameModification.cs`，32 行）：:8 `abstract ModificationInfo ModificationInfo`；:10-11 `abstract Task OnEnableAsync(); abstract Task OnDisableAsync();`；:13 `Action? OpenConfigAction`（给浏览器窗口点「设置」用）；:18 `IsExperimental`、:23 `WarningMessage`、:28 `ImageName`。

3. **元数据集中在一个 record**（`Classes/ModificationInfo.cs:8-32`）：required `DisplayName/Description/Authors/Type`，可选 `SubType/Tags/DisabledReason`，**:21 `CompatibilityModule`**（:17-20 注释：和别的插件功能重复时不加载），:23-31 `IsMatch(Regex)` 供搜索框用（DisplayName/Authors/Type/SubType/Tags 全匹配）。

4. **冲突与强制禁用**：`ModificationManager.cs:69-105 ReloadConflictedModules()` 订阅 `ActivePluginsChanged`（:40），插件列表一变就重评 `CompatibilityModule.ShouldLoadGameModification()`，可以把 Enabled 打成 `CompatError` 并记 `ErrorMessage`（:82-87），也可以反向恢复（:91-98）。启用前还有两道闸：`DisabledReason`（:116-123）与 `CompatibilityModule`（:125-134）。

5. **加载策略**：`LoadModulesAsync`（:18-41）只启用 `EnabledModifications` 里的模块；`SafeMode` 时串行 `.GetAwaiter().GetResult()`（:29-31），否则 `Task.Run` 并行（:33）+ `Task.WhenAll`（:38）。`SafeMode` 是排查崩溃用的开关（`VanillaPlus.cs:122-127` 的 `/plus safemode`）。

6. **错误隔离**：`TryEnableModification`（:107-161）整体 try/catch → 失败置 `LoadedState.Errored`，并**自动尝试 `OnDisableAsync()` 回滚**；回滚再失败记 `Error_CriticalUnloadFailed`（:156-159）。`TryDisableModification`（:163-187）同样保护。状态机 `LoadedState`（`Classes/LoadedModification.cs:5-11`：State + ErrorMessage）供 UI 显示。

7. **每模块一份配置分片**（`Classes/GameModificationConfig.cs`）：:12 `public abstract class GameModificationConfig<T> : ISavable where T : GameModificationConfig<T>, new()`；:13 `protected abstract string FileName` → 落盘 `<FileName>.config.json`；:14 `Version`；:16-46 `Load()`（读盘 + `TryMigrateConfig`，:34-35 注释明说**只支持单步迁移**）；:48-84 `Save()` 用 `SemaphoreSlim` + `Interlocked` 合并并发写（:62 拿不到锁就跳过、:70 `while` 处理排队），:75 注释提醒 `OnSave` 在非主线程执行；:94 `TryMigrateConfig` 默认 false。

8. **目录形态**：`Features/<Name>/` 下放 `<Name>.cs`（模块组装）+ `<Name>Config.cs` + `Nodes/`（自绘节点）+ 可选 `*Controller.cs`。最典型的 4 文件模块：`Features/BiggerConfigWindows/`（`BiggerConfigWindows.cs` / `BiggerConfigWindowsConfig.cs` / `SystemConfigController.cs` / `CharacterConfigController.cs`）。共享件放 `Classes/`（`NodeConfig` / `TextNodeConfig` / `ButtonConfig` 等）+ `Native/Addons/`（`ConfigAddon` / `AddonConfigAddon` / `KeybindConfigAddon` / `RenameAddon`）+ `Native/Nodes/`。

9. **单个模块的组装范式**（`Features/BiggerConfigWindows/BiggerConfigWindows.cs`）：:9-14 元数据（字符串走 `Strings` 资源）；:24-50 `OnEnableAsync` = 读配置 → 建 `ConfigAddon`（`InternalName`/`Title`/`Size`）→ `configAddon.AddCategory(...).AddInputFloat(label, 5, 4000, nameof(config.SystemConfigAdditionalHeight))` → `OpenConfigAction = configAddon.Toggle` → 建 controller 并 `EnableAsync()`；:52-63 `OnDisableAsync` 逆序 Dispose。

**DailyDuty 的差异（同一作者的另一套）**：同样是反射 + `LoadedState`（`DailyDuty/DailyDuty/Classes/ModuleManager.cs:44-46` `GetAllModules().OrderBy(Type).ThenBy(Name)`），但**模块在登录后才加载、登出即卸载**（`DailyDutyPlugin.cs:44-49` 与 :103-108 `OnLogin` → `SystemConfig.Load()` + `ModuleManager.LoadModules()`；:110-115 `OnLogout` → `UnloadModules()`）；且分两段：先全体 `LoadAsync` 再 enable（`ModuleManager.cs:54-55` 注释：「Load all modules before enabling any of them, so timers and others don't have to rebuild once load is done」）。业务型插件抄 DailyDuty 的时序，纯 UI 插件抄 VanillaPlus。

### Q6 坑

**1. 国服分支 ≠ 上游，别混用行号**

| 项 | 上游（本笔记） | 国服分支（`E:\FF14Dev\KnowledgeBase\KamiToolKit` HEAD `138cc86`） |
| --- | --- | --- |
| `.cs` 数量 | 228 | 232 |
| SDK | `Dalamud.NET.Sdk/15.0.0`（`KamiToolKit.csproj:1`） | `Dalamud.CN.NET.Sdk/15.0.0`（`KamiToolKit.csproj:1`） |
| 外部依赖 | 无 | **硬依赖同目录的 `..\FFXIVClientStructs.Expansion`**（`KamiToolKit.csproj` 末尾 `ProjectReference`） |
| 多出来的文件 | — | `BaseTypes/NativeAddon/NativeAddon.ColorTheme.cs`、`NativeAddon.ParentRelations.cs`、`NativeChildAddon.cs`、`Controllers/NativeAddonController.cs`、`AGENTS.md` |
| 上游独有 | `ContextMenu/ContextMenu.cs`、`Experimental.cs`、`KamiToolKit/ContextMenu*` | 无 |

所以：① 旧笔记里 `AttachNode` 在 `NodeBase.Linking.cs:31-43`、`Resize` 在 `AtkUnitBaseExtensions.cs:48-66`、`KamiToolKitLibrary.cs:49-71` 都是**国服行号**，在上游分别是 `:21-64`、`:15-58`、`:51`——**行号不能跨分支引用**；② 旧笔记说的「ExpansionInterop 隐藏依赖」只对国服分支成立，上游 KTK 不引 `FFXIVClientStructs.Expansion`（`grep -r "Expansion"` 零命中）；③ 国服分支的 `NativeChildAddon`/`NativeAddonController`（子 addon）在上游没有，看到相关 API 先确认是哪一份。

**2. 主线程的三种失败方式不同**

- 节点构造：`ThreadSafety.AssertMainThread()` **抛异常**（`NodeBase.cs:31`）→ 立刻可见。
- 节点 `Dispose()`：非主线程**只写一条 verbose 日志然后 return**（`NodeBase.Dispose.cs:61-64`），**静默泄漏**。
- `KamiToolKitLibrary.Dispose()`：非主线程打 `Error` 并 return（`KamiToolKitLibrary.cs:125-128`），**看起来正常退出，实际什么都没清**。

排查「卸载后游戏崩」时，先确认这三处都在主线程；`DisposeAsync` 系列（`NodeBase` 无，`AddonController.DisposeAsync`/`KamiToolKitLibrary.DisposeAsync` 有）内部会 `IFramework.Run` 回主线程，**所以卸载路径优先用 Async 版本**。VanillaPlus/DailyDuty 全用 `await x.DisposeAsyncSafe()`（扩展在 `KamiToolKit/Internal/Extensions/AsyncDisposableExtensions.cs:16`，VanillaPlus 有同款副本 `VanillaPlus/VanillaPlus/Extensions/AsyncDisposableExtensions.cs:16`）。

**3. 还挂在原生 addon 上的节点，KTK 不会替你清**

`KamiToolKitLibrary.DisposeAsync` 最后调的 `NodeBase.DisposeNodes()`（`KamiToolKitLibrary.cs:163`）实现是（`NodeBase.Dispose.cs:143-151`）：

```csharp
foreach (var node in CreatedNodes.ToArray()) {
    if (node.ResNode is null) continue;
    if (node.ResNode->ParentNode is not null) continue;   // ← 还挂着的，跳过
    if (node.IsAddonRootNode) continue;
    node.Dispose();
}
```

**只清孤儿（`ParentNode == null`）**。所以插件卸载时如果节点还挂在活着的 addon 上，KTK 不会动它 → 游戏之后关窗/重开时那块内存被释放，C# 对象还指着它 → 崩。**正确做法是在 `OnFinalize` 里自己 Dispose**（`ArmourySearchBar.cs:85-92`、`MacroLineNumbers.cs:67-81` 都是这个写法）。`WarnLeakedNodes()`（:123-137）只负责在日志里喊「There were N node(s) that were not disposed safely.」和「Forcing disposal of: X」，不会救你。

**4. Dispose 本身其实做了「摘链 + 重建名单」，比手写安全**

`NodeBase.Dispose()`（`NodeBase.Dispose.cs:50-102`）的顺序：double-dispose 守卫（:56-59）→ 主线程守卫（:61-64）→ **`IsNodeValid()` 守卫（:66-69，节点已失效就打 "Invalid node, dispose aborted." 退出）** → 递归 Dispose 子节点并 `suppressAddonUpdate = true`（:72-75，避免每个子节点都重建一次名单）→ `UnregisterTooltipEvents()`（:80）→ `AtkStage.Instance()->ClearNodeFocus(ResNode)`（:83）→ `DetachNode()`（:86）→ `Timeline?.Dispose()`（:89-90）→ `Dispose(false)`（:93）。

`DetachNode` 那条链（`NodeBase.Linking.cs`）：:180-183 `NodeLinker.DetachNode(ResNode)` + 清 `ParentNode/NextSiblingNode/PrevSiblingNode`；`RemoveUldManagerObjectReferences()`（:186-191，`RemoveNodeFromObjectList`）；`RemoveParentAddonReferences()`（:193-206，**非 `suppressAddonUpdate` 时 `UpdateDrawNodeList()` + `UpdateCollisionNodeList(false)`**，:196-199）。

也就是说：**`node.Dispose()` 会自己摘链并重建绘制名单**，不需要我们像老项目那样手写 `UldManager.UpdateDrawNodeList()`。这也是 `NodeBase.Dispose.cs:140-142` 注释「Ensure you have detached nodes safely from native ui before disposing.」的另一面——它其实帮你摘，只是别指望它清还挂着的。

`IsNodeValid()`（:176-182）判三种无效：`ResNode is null`、`VirtualTable is null`、`VirtualTable == AtkEventTarget.StaticVirtualTablePointer`（游戏已把节点还原/释放）。**这解释了「addon 关了之后再 Dispose 不崩」**：游戏先销毁节点时，KTK 换过的虚表（:187-202 `BuildVirtualTable`，把 dtor 换成托管函数 `Destroy`）会先被回调（:207-220），`IsDisposed = true` 并 `CreatedNodes.Remove(this)`；之后你再 Dispose 就是 no-op。

**5. 泄漏的最后一层「保护」是假的**

`~NodeBase()`（:156-159）：`IPluginLog.Get().Warning($"Leaked node detected via finalizer, disposing {GetType()}"); Dispose();`——finalizer 跑在 GC 线程，`Dispose()` 的主线程守卫直接 return（:61-64）。**所以 finalizer 唯一的作用是留一条日志，节点照样漏**。

**6. `NodeId` 冲突：KTK 自己规避了，但自建 addon 内仍要注意**

`NodeBase.Dispose.cs:104-105`：`internal const uint NodeIdBase = 100_000_000;`、`internal static uint CurrentOffset;`，分配在 `NodeBase.cs:45` `ResNode->NodeId = NodeIdBase + CurrentOffset++;`。这是**进程级静态计数器**（不是每插件一份）→ 同一进程内所有 KTK 节点 ID 唯一且单调递增、**永不回收**。和游戏原生节点（小数值）不冲突，也天然避开「两个插件硬编码同一个 NodeId」的问题。

需要注意的反而是**自建 addon 里手写的 NodeId**：`NativeAddon.cs:76-80` `RootNode = new ResNode { NodeId = 1, ... }`、:83 `WindowNode { NodeId = 2 }`——这类小数值是给根/窗口节点用的固定值；别在自己的 addon 里再手写一串小 NodeId 与 KTK 节点混用（KTK 的都是 1e8+，实际不会撞，但**规则要一致**：要么全用 KTK 分配，要么全手写并自己保证唯一）。

**7. 自建 addon 是有配额的**

`NativeAddon.cs:56-64`：当前 addon 数 ≥200 打 Warning「Current Addon Count is approaching hard limits ({n}/250)」，≥225 打 Error 并**放弃分配**。:66-68 `InternalName` 为空直接 `throw new NullReferenceException`。:72 `IMemorySpace.GetUISpace()->Create<AtkUnitBase>()`，:97 `AtkStage.Instance()->RaptureAtkUnitManager->InitializeAddon(...)`，:99-102 初始化失败会 `Dispose(); throw new Exception("Failed to initialize addon!")`。→ **不要拿自建 addon 当悬浮窗**（KTK 源码里那句 Warning 就是这么写的），悬浮用 `OverlayController`。

**8. 全局日志级别被 KTK 调成 Verbose**

`KamiToolKitLibrary.cs:63` `IPluginLog.Get().MinimumLogLevel = LogEventLevel.Verbose;`。所有插件的日志都会变多，排查性能/日志噪音时这是变量之一（关闭插件后对比一次即可确认）。

**9. 卸载顺序的自检清单**（按 VanillaPlus / DailyDuty 归纳）

1. 反注册自己的事件 / 命令 / 键位（`VanillaPlus.cs:72-80`、`DailyDutyPlugin.cs:56-63`）
2. `await` 每个界面窗口 Dispose（`VanillaPlus.cs:82-83`、`DailyDutyPlugin.cs:67`）
3. `await` 管理器 Dispose（`VanillaPlus.cs:84`、`DailyDutyPlugin.cs:68`）
4. 最后 `await KamiToolKitLibrary.DisposeAsync()`（`VanillaPlus.cs:85`、`DailyDutyPlugin.cs:69`）
任何顺序颠倒 + 主线程问题都会变成「关插件时不报错、几秒后崩」这种最难查的形态。

## ④ 可以直接抄进下一个插件的代码骨架

### A. 最小插件：挂一个自绘节点到游戏自带 addon

**文件 1：`<Name>.csproj`**（照 `DailyDuty/DailyDuty/DailyDuty.csproj:1-4` + KTK 仓库的七个属性）

```xml
<Project Sdk="Dalamud.NET.Sdk/15.0.0">
  <PropertyGroup>
    <Version>0.0.0.1</Version>
    <Author>…</Author>
    <Name>…</Name>
    <Punchline>…</Punchline>
    <Description>…</Description>
    <RepoUrl>…</RepoUrl>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\KamiToolKit\KamiToolKit.csproj" />
  </ItemGroup>
</Project>
```

（KTK 必须先 `git submodule add https://github.com/MidoriKami/KamiToolKit`，参考 `VanillaPlus/.gitmodules:1-6`；KTK 的 `csproj` 自带 `Use_DalamudPackager=false`，`KamiToolKit/KamiToolKit.csproj:11`。）

**文件 2：`Plugin.cs`**（骨架照 `VanillaPlus/VanillaPlus/VanillaPlus.cs:17-27, 71-86`）

```csharp
using System;
using System.Threading;
using System.Threading.Tasks;
using Dalamud.IoC;
using Dalamud.Plugin;
using Dalamud.Plugin.Services;
using KamiToolKit;

namespace MyPlugin;

public sealed class MyPlugin : IAsyncDalamudPlugin {
    [PluginService] internal static IDalamudPluginInterface PluginInterface { get; set; } = null!;

    private ItemDetailHint? feature;

    public async Task LoadAsync(CancellationToken cancellationToken) {
        await KamiToolKitLibrary.InitializeAsync(PluginInterface, "MyPlugin");  // 必须第一件事
        // KamiToolKitLibrary.SetResourceManager(Strings.ResourceManager);     // 有本地化才需要 :27

        feature = new ItemDetailHint();
        await feature.EnableAsync();
    }

    public async ValueTask DisposeAsync() {
        if (feature is not null) {
            await feature.DisableAsync();          // 先收自己的控制器/节点
            feature = null;
        }

        await KamiToolKitLibrary.DisposeAsync();   // 必须最后一步
    }
}
```

**文件 3：功能类**（骨架照 `ArmourySearchBar.cs:38-92`，节点属性照 `MacroLineNumbers.cs:54-63`）

```csharp
using System.Numerics;
using FFXIVClientStructs.FFXIV.Component.GUI;
using KamiToolKit.Controllers;
using KamiToolKit.Nodes;

namespace MyPlugin;

public unsafe class ItemDetailHint {
    private AddonController? controller;
    private TextNode? hintNode;

    public async Task EnableAsync() {
        controller = new AddonController {
            AddonName = "ItemDetail",       // 目标 addon 名
            OnSetup = OnSetup,              // addon 出现/已存在时都会来（EnableAsync 会补调一次）
            OnFinalize = OnFinalize,        // addon 关闭前，必须在这里 Dispose 自己的节点
        };

        await controller.EnableAsync();
    }

    public async Task DisableAsync() {
        await controller.DisposeAsyncSafe();   // 内部会 Unregister + OnFinalize
        controller = null;
    }

    private void OnSetup(AtkUnitBase* addon) {
        hintNode = new TextNode {
            Position = new Vector2(10.0f, addon->Size.Y - 24.0f),
            Size = new Vector2(addon->Size.X - 20.0f, 20.0f),
            String = "示例提示",
            FontType = FontType.Axis,
            FontSize = 12,
            AlignmentType = AlignmentType.TopLeft,
        };

        hintNode.AttachNode(addon);       // 默认 AsLastChild：挂到 addon 根节点末尾，最上层
    }

    private void OnFinalize(AtkUnitBase* addon) {
        hintNode?.Dispose();              // Dispose 会自己摘链并重建绘制名单
        hintNode = null;
    }
}
```

要点：`OnSetup` 里别做耗时/异步操作（它在 addon 事件里同步调用）；`OnSetup` 必须幂等（可能被补调两次）；`OnFinalize` 一定把节点置 null。

### B. 撑高原生 addon（三段拼起来，KTK 只代劳第一段）

```csharp
private static unsafe void GrowAddon(AtkUnitBase* addon, float delta, AtkResNode* backgroundNineGrid, AtkTextNode* hintLine) {
    // ① 屏幕保护：照 VanillaPlus/Features/BiggerConfigWindows/SystemConfigController.cs:35-39
    if (AtkStage.Instance()->ScreenSize.Height < addon->Size.Y + delta) {
        IPluginLog.Get().Warning("窗口会超出屏幕，放弃撑高。", "MyPlugin");
        return;
    }

    // ② 撑框：走 KTK 的 Size setter（AtkUnitBaseExtensions.cs:43-58），
    //    内部自动：WindowNode 宽高 + 标题碰撞 + SetSize + UpdateDrawNodeList + UpdateCollisionNodeList
    //    注意 addon->WindowNode 为 null 时它静默 return（:44-45）
    addon->Size += new Vector2(0.0f, delta);

    // ③ KTK 不管的部分，自己补：
    //    九宫格背景（照 MacroLineNumbers.cs:102-106）
    if (backgroundNineGrid is not null)
        backgroundNineGrid->SetHeight((ushort)(backgroundNineGrid->GetHeight() + delta));

    //    提示行/按钮行/分隔线（照 MacroLineNumbers.cs:111-113 与 SystemConfigController.cs:52/55）
    if (hintLine is not null) {
        var pos = Vector2.Zero;
        hintLine->GetPositionFloat(&pos.X, &pos.Y);
        hintLine->SetPositionFloat(pos.X, pos.Y + delta);
    }

    // ④ 逼游戏重排一次（照 BetterEmoteWindow.cs:73 的 "// Trigger layout update"）
    addon->Size += new Vector2(0.0f, 5.0f);
    addon->Size -= new Vector2(0.0f, 5.0f);
}
```

时机：这类改动放在 `AddonController.OnRefresh`（映射到 `PostRefresh`/`PostRequestedUpdate`，`AddonController.cs:70-71` 注册、:184-186 分发）或 `OnUpdate`（映射 `PostUpdate`，:75 注册、:192-194 分发）里，**别放在 `OnSetup`**——`OnSetup` 只有一次，换物品/刷新不会重来。整张事件映射表在 `AddonController.cs:167-198`：`PostSetup`→OnSetup（:171-173）、`PreFinalize`→OnFinalize（:176-178）、`PreRefresh/PreRequestedUpdate`→OnPreRefresh（:180-182）、`PostRefresh/PostRequestedUpdate`→OnRefresh（:184-186）、`PreUpdate`→OnPreUpdate（:188-190）、`PostUpdate`→OnUpdate（:192-194）、`PreDraw`→OnDraw（:196-198），除 Setup/Finalize 外全部带 `args.Addon.IsReady` 守卫。

### C. 「内容变长就撑高」的自建窗口版

直接照 `VanillaPlus/VanillaPlus/Native/Addons/ConfigAddon.cs:51-73` 的 `RecalculateWindowSize()`：`RecalculateSizes()` → 读 `ContentNode.Height` → 夹到 `MaximumHeight` → `Size = new Vector2(Width, contentHeight + ContentStartPosition.Y + 24f)` → `SetWindowSize(Size)` → 再 `RecalculateSizes()`。触发点放在内容变化处（如 `VerticalListNode.OnRecalculateLayout` 之后 / `OnLayoutUpdate` 回调里，参考 `AddonWidgetDemo.cs:41`）。

## ⑤ 结论可信度

| 结论类别 | 依据 | 可信度 |
| --- | --- | --- |
| 初始化/卸载 API、顺序、主线程约束 | KTK 源码 + 两个真实插件入口 | 源码实证 |
| `AttachNode` 重载与 `NodePosition` 方向 | KTK 枚举注释 + `NodeLinker` 实现 | 源码实证 |
| 真实调用范式（控制器、挂载点选择） | VanillaPlus 具体文件与行 | 源码实证 |
| `Resize` 只动 WindowNode/标题碰撞、不动九宫格 | `AtkUnitBaseExtensions.cs:43-58` 完整实现；全仓库无第二处 | 源码实证（KTK 侧）；**未在游戏里验证「九宫格会不会被游戏自身跟着拉长」** |
| 内容驱动撑高只有自建窗口版 | `grep SetWindowSize`/`Size +=`/`RecalculateWindowSize` 全仓库结果 | 源码实证 |
| 「九宫格 + 提示行」有人处理，但只在输入框组件尺度 | `MacroLineNumbers.cs:83-114` | 源码实证 |
| Dispose 的摘链/名单重建/失效守卫 | `NodeBase.Dispose.cs` + `NodeBase.Linking.cs` | 源码实证 |
| 节点还挂着时 KTK 不清、会留悬空指针 | `DisposeNodes` 只处理 `ParentNode == null` | 源码实证（崩溃表现为**推测**，未实测） |
| KTK 与国服分支的差异 | 两个本地仓库文件清单 + csproj 对比 | 源码实证（CN 分支为 `KnowledgeBase` 里那份，非上游） |
| `AnchorBottom` 会不会跟随底边 / `Resize` 后九宫格是否自动长 | 源码中无相关逻辑 | **未确认**（旧笔记遗留待验证项，本次未做游戏内实测；KTK 无代码支持，推断"不会"，但按规矩标未确认） |
| DailyDuty 配置界面（`ModuleBrowserWindow`）细节 | 只看了入口与 ModuleManager | **未确认**（未读 `Windows/` 目录） |
| KTK.Components 仓库（`KamiToolKit.Components`） | 未 clone | **未确认** |

### 复现命令

```
E:/FF14Dev/git/cmd/git.exe -c http.proxy=http://127.0.0.1:7897 clone --depth 1 \
  https://github.com/MidoriKami/<KamiToolKit|KamiToolKitDemo|VanillaPlus|DailyDuty> \
  "E:/DeepSeek Harness/.tmp/study/MidoriKami/<同名>"
```

（README 里的星数为调研时 GitHub 页面显示值；最近提交取自 `git log -1`。）
