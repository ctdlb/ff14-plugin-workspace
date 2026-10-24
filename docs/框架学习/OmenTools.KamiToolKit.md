# OmenTools.KamiToolKit 学习笔记

> 调研对象：`E:\FF14Dev\KnowledgeBase\OmenTools.KamiToolKit`（本机知识库克隆，`--depth 1`，只读）。
> 下文路径均相对该仓库根。推断写「推测」，没读到的写「未确认」。

## 1. 一句话定位

**OmenTools 给 KamiToolKit 做的功能扩展库**：不是适配层，而是拿 KTK 的节点类派生出一批「OmenTools 风格」的控件（带背景的列表项、分页条、仪表条、圆形按钮…），再加两个自造弹窗（文本输入 / 数字输入）和一个「贴边面板」基类。

- 仓库：<https://github.com/AtmoOmen/OmenTools.KamiToolKit>
- LICENSE：`LICENSE`（根目录），**MIT**，`Copyright (c) 2025 AtmoOmen`
- 规模：**29 个 `.cs` / 2,938 行**（`Nodes/` 16 个 1,465 行，`Addons/` 13 个 1,473 行）
- 最近提交：**2026-10-21** `67ce79f` `修正缺少过度动画`
- 工程（`OmenTools.KamiToolKit.csproj`）：`Dalamud.CN.NET.Sdk/15.0.0`、`LangVersion preview`、`Use_DalamudPackager=false`、`UseWindowsForms=true`、`PackageReference DailyRoutines.CodeAnalysis 2.6.0`、**`ProjectReference ..\KamiToolKit\KamiToolKit.csproj` + `..\OmenTools\OmenTools.csproj`**

**三者关系（从 csproj 与代码确认，不是从 README 猜）**：

- 它是 **KTK 的扩展库**：`Nodes/*.cs` 全部是 KTK 类型的子类（`BackgroundNode : NineGridNode`、`PaginationNode : SimpleComponentNode`、`GaugeBarNode : ComponentNode<AtkComponentGaugeBar, AtkUldComponentDataGaugeBar>`、`ItemListItemNode : ListItemNode<Item>, IListItemNode`、`TextMultiLineInputNode : TextInputNode`…），不改写、不包装 KTK 的 API；
- 它同时**消费 OmenTools**：`using OmenTools.Extensions;` + `IGameGui.Instance()` / `IFramework.Instance()` / `IAddonLifecycle.Instance()` 这套静态实例，以及 `OmenTools.Interop.Game.Models.AddonPosition`；
- 因此三者是**依赖链 KTK ← OmenTools.KamiToolKit → OmenTools**，不是「KTK 与 OmenTools 之间的适配层」。README 原话：「本项目不支持原版 KamiToolKit 与其提供的 NuGet 包」——它要的是**打了 CN 分支补丁的 KTK**。

## 2. 核心 API / 目录地图

| 目录 | 文件 / 行数 | 内容 |
| --- | --- | --- |
| `Nodes/` | 16 / 1,465 | 派生控件 + `Background/` 九宫格背景族 |
| `Addons/` | 13 / 1,473 | `AttachedAddon.cs`（贴边面板基类）、`InputString/`、`InputNumeric/`、`SelectYesno/` |
| `Misc/Preview/Nodes/` | 4 张 PNG | 只有图 |

关键签名：

```csharp
// Addons/AttachedAddon.cs:14
public abstract class AttachedAddon : NativeAddon          // :16 AttachPosition => AttachedAddonPosition.LeftTop
// Addons/AttachedAddon.cs:79
protected AttachedAddon(string hostAddon, params AddonEvent[] hostAddonEvents)
// Addons/AttachedAddon.cs:65
protected unsafe AtkUnitBase* HostAddon
    => (AtkUnitBase*)IGameGui.Instance().GetAddonByName(hostAddonName).Address;
// Addons/AttachedAddon.cs:388
public enum AttachedAddonPosition   // LeftTop, TopLeft, TopCenter, TopRight, RightTop … 共 12 值

// Nodes/Background/BackgroundNode.cs:13
public sealed unsafe class BackgroundNode : NineGridNode     // ui/uld/BgParts.tex 九宫格分块
// Nodes/Background/BackgroundType.cs:6
public enum BackgroundType   // GoldFrame, InsetFrame, GoldOutline, SplitPanel, LightFrame, SolidPanel …
// Nodes/ItemListItemNode.cs:9
public class ItemListItemNode : ListItemNode<Item>, IListItemNode
// Nodes/GaugeBarNode.cs:13   public class GaugeBarNode : ComponentNode<AtkComponentGaugeBar, AtkUldComponentDataGaugeBar>
// Nodes/ButtonListNode.cs:12 public class ButtonListNode : SimpleComponentNode
// Nodes/PaginationNode.cs:10 public class PaginationNode : SimpleComponentNode
// Nodes/CircleButton/CircleButtonNode.cs:9      public class CircleButtonNode : ButtonBase
// Nodes/InfoMarkerNode.cs:5  public class InfoMarkerNode : SimpleNineGridNode   // ui/uld/img04/CircleButtons_hr1.tex
// Nodes/HorizontalDashedLineNode.cs:6  public class HorizontalDashedLineNode : SimpleImageNode  // ui/uld/Lines.tex
// Nodes/TextMultiLineInputNode.cs:5    public class TextMultiLineInputNode : TextInputNode

// Addons/InputString/InputStringAddon.cs:15
public sealed class InputStringAddon : NativeAddon
// Addons/InputString/InputStringAddon.cs:17
public static InputStringAddon Open(InputStringAddonOptions options)   // :20-58 建窗，InternalName="DRInputString"
// Addons/InputString/InputStringAddonOptions.cs:7
public sealed record InputStringAddonOptions
```

**重点问题一：`Addons/AttachedAddon.cs` 是「贴边面板」还是「往宿主 addon 里插入」？→ 是贴边面板，完全不插入宿主。**

- `Addons/AttachedAddon.cs:14` 它自己就是 `NativeAddon` 的子类 → 它是一个**独立的 addon 窗口**；
- 它只是**读**宿主的尺寸/位置/可见性，然后把**自己**挪到宿主旁边：`Addons/AttachedAddon.cs:215-216`
  ```csharp
  var hostSize = new Vector2(host->GetScaledWidth(true), host->GetScaledHeight(true)) / addon->Scale;
  ```
  （`host` 即 `:65-66` 的 `HostAddon`；`:218-233` 按 `AttachPosition` 12 方位算偏移；`:235-238` `SetWindowPosition(hostPosition + (position * addon->Scale) + PositionOffset)`）
- `Addons/AttachedAddon.cs:164-175` 逐帧把宿主的 `UiFlags`/`IgnoreUIDisplayMode`/`DepthLayer`/`Scale`/`Alpha` 抄到自己身上（缩放靠 `InternalAddon->SetScale(HostAddon->Scale * value / AtkUnitBase.GetGlobalUIScale(), true)`，`:25-34`）；
- `Addons/AttachedAddon.cs:177-185` 跟随宿主可见性；`:132-152` 把宿主的 InputReceived/InputNavigation 转发给自己；`:86-91` 明确 `HasWindowNode=false`、`RememberClosePosition=false`、`OpenInBounds=false`；
- **整个 `OnUpdate`（`:155-243`）里没有一次 `AttachNode`**，宿主只被读，不被改。

**重点问题二：`Nodes/` 里有没有「原生 addon 内插入」的封装？→ 没有。**

- 无 `AttachNode(AtkUnitBase*)` 重载、无 `PerformNativeAttach` 调用；
- 全库 `AtkUnitBase*` 只出现在 `Nodes/ButtonListNode.cs:72/84`（`SetFocusable`/`ClearFocusable` 改 `addon->AdditionalFocusableNodes`）和 `Addons/AttachedAddon.cs:65`；
- 真正能往宿主 `RootNode` 插节点的是 **KTK 自己的 API**，不在这个库里：
  ```csharp
  // E:\FF14Dev\KnowledgeBase\KamiToolKit\BaseTypes\NodeBase\NodeBase.Linking.cs:32
  public void AttachNode(AtkUnitBase* targetAddon, NodePosition targetPosition = NodePosition.AsLastChild)
      => PerformNativeAttach(targetAddon is not null ? targetAddon->RootNode : null, targetPosition);
  ```
  同文件另有 `:24` `AttachNode(NativeAddon?, NodePosition)`、`:128` `DetachNode()`，以及 `:49/57/65/73/81/89/97/105/113` 一串 `NodeBase`/`AtkResNode`/`AtkTextNode`… 重载。
- 结论：这个库提供的是**内容**（好看的节点），不提供**挂载通路**。

## 3. 它解决什么问题

直接写 KTK 有两个重复劳动：① 每个插件都要手搓列表背景九宫格、高亮、分页条、仪表的样板；② 想做个「挂在某个面板旁边的设置抽屉」得自己处理跟随缩放/可见性/输入焦点。这个库把这两块沉淀成基类和派生控件，作者自己（Omni / DailyRoutines）在多个插件里复用（推测：这是它不对外的真实原因，README 未写明发布形态）。

## 4. 对我们的用处

**结论：对「往 `ItemDetail` 插文本节点 + 撑高窗口」这件事，它帮不上忙；只当「控件图鉴」看，不建议引入。**

- 硬需求「插进别人 addon」：它没有（见上「重点问题二」），我们得走 KTK 的 `NodeBase.Linking.cs:32` 或干脆继续手写原生节点——后者是我们现在的做法，且已验证可行。
- 「撑高窗口」：它全无涉及。`AttachedAddon` 是搬家不是撑高；`Nodes/` 里改尺寸的都只影响自己（如 `Nodes/ItemListItemNode.cs:59-74` 的 `OnSizeChanged`）。
- 真正值钱的东西在 **OmenTools 已有的 ItemDetail 重排链路**（不是这个库）：
  `OmenTools\OmenService\Implementations\Managers\Tooltip\TooltipManager.cs:396-428` 的 `OnItemDetailPostUpdate` 给了完整示范——改 `DescriptionText->Width` → `MaterializeText->TextFlags |= MultiLine|WordWrap` → `ApplyTextFlow()` → `GetTextDrawSize` → `SetHeight` → `CraftingAndRepairsGroup->SetHeight` → `UpdateGroupPositions`；`:900-911` 的 `RecalculateItemDetailLayout` 是同一个函数的薄封装。我们要的「撑高」照这条链做即可。
  原生两函数的签名（`FFXIVClientStructs\FFXIVClientStructs\FFXIV\Client\UI\AddonItemDetail.cs:145` / `:149`）：`UpdateGroupPositions(NumberArrayData*, StringArrayData*)`、`GenerateItemTooltip(NumberArrayData*, StringArrayData*)`，都是 `[MemberFunction]`。
- 唯一可能借的：`Nodes/Background/BackgroundNode.cs:13` + `Nodes/Background/BackgroundType.cs:6` 的九宫格背景枚举（`GoldFrame`/`InsetFrame`/`GoldOutline`…），如果以后要给我们自己撑高的框补背景或画分隔线，可以照抄它选贴图与分块参数的那几行（`ui/uld/BgParts.tex`、`ui/uld/Lines.tex`）。属于「看一眼就够」，不必引库。

## 5. 坑 / 限制

- **必须三者同解决方案**：csproj 里两个 `ProjectReference`（`..\KamiToolKit`、`..\OmenTools`）。这正是我们踩过的坑——`ProjectReference` 会互相污染 Dalamud SDK 属性、报上千个「找不到 `Action`/`Func`」；我们只能引编好的 dll。引这个库因此**基本不可行**。
- **只认改过的 KTK**：README 明说「不支持原版 KamiToolKit 与其提供的 NuGet 包」。上游 KTK 加节点/改 API 后，这个 fork 得跟着改；我们跟着它走＝绑死 OmenTools 的维护节奏（推测：这是它最大的长期风险）。
- `UseWindowsForms=true`：为一个节点库引入 WinForms 依赖。
- 复用 OmenTools 的静态实例（`IGameGui.Instance()` 等）→ 进程内必须已由 OmenTools 初始化，不能单独用。
- `AGENTS.md` 要求所有 public 成员写完整简体中文 XML 注释——与我们「文档写机制、不写猜测」的习惯一致，可参考其写法。
- MIT，可抄代码（保留版权声明）。作者与 OmenTools 同一人，许可证一致。

## 6. 还没读透的部分

- `Nodes/ItemListItemNode.cs` 只读了 `:18-87`（展示节点构造 + `OnSizeChanged` + `SetNodeData`），高亮/选中态怎么切**未确认**。
- `Nodes/ListBaseNodes/` 与 `Addons/` 下 `InputNumeric/`(282)、`SelectYesno/`(298) 只看了类声明与文件行数。
- `AttachedAddon` 的 `:272-316` `OnHostAddonLifecycle` 只扫了 PostDraw 分支，其余事件分支未逐行读。
- 它依赖的 KTK **CN fork 与上游 KTK 的具体差异未确认**（README 只说「二次开发带来的差异」）；`KamiToolKit` 克隆上游代码未使用。
