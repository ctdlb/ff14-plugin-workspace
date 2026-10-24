# KamiToolKit 深读：能不能往别人的 addon 里插节点

> 调研对象：`E:\FF14Dev\KnowledgeBase\KamiToolKit`（`--depth 1`，HEAD `138cc86`，2026-10-24 13:39）。
> 方法：只读源码 + 我自己抽查关键处；**未编译、未运行游戏**。凡是运行时行为都标「推测 / 待实测」。
> 相关旧笔记：`docs\KamiToolKit-上手指南.md`、`docs\kamitoolkit-原生界面.md`（其中两条结论已被当前源码推翻，见文末）。

## 一句话结论

**能插。** KTK 提供 `AttachNode(AtkUnitBase*)`、`TextNode`、`addon->Resize()` 三件套，且**不要求 addon 是它自己创建的**；但「撑高后框体外观完整」「插入节点跟随窗口高度」「换物品时重排」这三件事它没有现成实现，仍要自己写。

- 仓库：<https://github.com/MidoriKami/KamiToolKit>
- 许可：**MIT**
- 作者：MidoriKami（另有 DailyDuty、VanillaPlus、SortaKinda、NoTankYou、ChillFrames 等插件）

## 1. 挂节点：`AttachNode` 有原生重载

`BaseTypes/NodeBase/NodeBase.Linking.cs:31-43`（已抽查，逐字确认）：

```csharp
public void AttachNode
(
    AtkUnitBase* targetAddon,
    NodePosition targetPosition = NodePosition.AsLastChild
)
    => PerformNativeAttach
    (
        targetAddon is not null ? targetAddon->RootNode : null,
        targetPosition
    );
```

- `PerformNativeAttach`（:190-240）只有三类拦：自挂自、目标为 null、Component 目标重定向；**没有「必须自建 addon」的校验**。
- 挂上后自己重建绘制名单：`UpdateNative`（:337-367）里 `ParentAddon->UldManager.UpdateDrawNodeList(); ParentAddon->UpdateCollisionNodeList(false);`
- 摘链也自动：`NodeBase.Dispose.cs:94-95` → `DetachNode()`；`NodeBase.Linking.cs:317-321` 同样重建名单。
- 唯一按名字拦的是 `NamePlate`：`Controllers/AddonController.cs:28-37` 抛 `"Attaching to NamePlate is not supported. Use OverlayController Instead"`。

**旁证**（不是校验，只是类型限制）：`Controllers/NativeAddonController.cs` 只服务 KTK 自建的 `NativeAddon`，因为参数类型是 `NativeAddon`（:81 `GetOrCreate(NativeAddon parent)`）。

## 2. 造一行字：`TextNode`

`Nodes/TextNode.cs:14` `public unsafe partial class TextNode : NodeBase<AtkTextNode>, ITextNode`

- 构造默认（:23-36）：`FontSize = 12; FontType = FontType.Axis; LineSpacing = 12; AlignmentType = AlignmentType.TopLeft;`
- 属性 setter **自动刷新文字**：`String`（:178-187）→ `UpdateText()`（:269-273，内部 `Node->SetText(...)`）；**没有公开的 `Refresh()`**。
- 尺寸**不自动**：要自己给 `Size`，或用 `GetTextDrawSize()`（:238-267）算；原生还有 `TextFlags.AutoAdjustNodeSize`（`AtkTextNode.cs:120` `1 << 0`），但本工作区实测建议别用（`docs\插件开发坑.md:87`：游戏每次换文本会重算宽高，反而抖）。
- NodeId 不会撞：`NodeBase.cs:15` `NODE_ID_BASE = 100_000_000`，`:34` 自增分配。
- **单独 `new TextNode()` 就能用**，不必包在自建窗口里（构造里自己 `Create<T>()` + 建虚表）。

## 3. 撑高：有 `Resize`，但不完整

`Extensions/AtkUnitBaseExtensions.cs:48-66`（已抽查，逐字确认）：

```csharp
public void Resize(Vector2 newSize)
{
    var windowNode = addon.WindowNode;
    if (windowNode is null) return;          // ← WindowNode 为空时静默什么都不做

    windowNode->SetWidth((ushort)newSize.X);
    windowNode->SetHeight((ushort)newSize.Y);

    if (addon.WindowHeaderCollisionNode is not null)
        addon.WindowHeaderCollisionNode->SetWidth((ushort)(newSize.X - 14.0f));

    addon.SetSize((ushort)newSize.X, (ushort)newSize.Y);

    windowNode->Component->UldManager.UpdateDrawNodeList();
    addon.UpdateCollisionNodeList(false);
}
```

**它只处理三样**：`WindowNode` 宽高、窗口头顶碰撞条宽度、调一次原生 `SetSize`。
**它不碰**：九宫格背景、`Component->UldManager.RootNode`、`RootNode->PrevSiblingNode`、`addon->RootNode`。

而本工作区的实测结论是「只改 `WindowNode` 时背景不跟着长，字会露在框外」（`docs\插件开发坑.md:330-336`）。所以**「`Resize` 够不够」必须实测**——多调的那次 `SetSize` 有可能让游戏自己把九宫格重算好（推测，无源码证据）。

## 4. 布局：没有「跟随父节点底边」的机制

- `Nodes/Layout/` 13 个文件（`VerticalListNode`、`HorizontalListNode`、`GridNode`、`ListBoxNode`…），全部**按自身宽高**排版。
- `VerticalListNode.cs:63-108` 的 `FitContents` 是「子 → 父」方向：按子节点算自己的高，不是父 → 子。
- 全库**没有任何节点读 `ParentNode.Height/Width` 或 `ParentAddon.Size`**（grep 无命中）。
- 想要「插进去的行跟着窗口底边走」，只有两条自写路：
  - **A（推测）** 设 `NodeFlags.AnchorBottom`（`AtkResNode.cs:389` `= 0x04`）+ 触发一次 `SetSize`；注意同文件 :383-384 注释说这些 flag「rely on other stuff to happen」。
  - **B（库内有先例）** `PostUpdate` 里每帧同步：`MapOverlay/MapOverlayController.cs:204-210` 就是把容器尺寸/位置每帧对齐到宿主节点。

## 5. 生命周期

`KamiToolKitLibrary.cs:49-71` `InitializeAsync`：注入服务 → `Create<Services>()` → 读磁盘配置 `AddonConfigFile` → `await IFramework.Get().Run(NativeAddon.InitializeCloseCallback)` → 注册 debug 命令。

- **硬前置**：没调 `InitializeAsync` 就 `new` 任何节点会直接抛——`NodeBase.cs:23` 构造第一行就是 `IPluginLog.Get()`，而 `Internal/Classes/Services.cs:22` 在取不到服务时 `throw new InvalidOperationException(...)`。
- **隐藏前置（现有文档没写）**：KTK 依赖 `FFXIVClientStructs.Expansion`，但**自己从不调 `ExpansionInterop.Initialize`**（全库无命中）；全仓唯一调用点是 `OmenTools/DService.cs:56`。→ **推测**：不引 OmenTools 时，凡走 expansion 成员的路径（原生子窗口、`SetScaleWithoutConfiguration`）会拿到 0 地址。纯 `TextNode + AttachNode + Resize` 不走它，但要验证。
- **卸载**：同步 `Dispose()`（`KamiToolKitLibrary.cs:138-159`）逐个关控制器、`DisposeNodes`、`RelinquishData`；异步 `DisposeAsync()`（:164-221）分帧跑，**不要在主线程 `.GetAwaiter().GetResult()` 等它**（`IFramework.Run` 要主线程下一帧 → 死锁，推测但机制清楚）。
- `NodeBase.Dispose.cs:63-67`：`IsFrameworkUnloading` 时直接 return（游戏退出不手动拆，这是设计）。

## 6. 有没有 ItemDetail 的现成实现

**没有。** 全库 `ItemDetail` 零命中；`Tooltip` 命中全是「给自绘节点加悬浮提示」（`NodeBase.Tooltips.cs`），与此无关。

**唯一可当模板的「往原生 addon 插节点」范例**是 `MapOverlay/MapOverlayController.cs`：

- :40-46 `new AddonController<AddonAreaMap> { AddonName = "AreaMap", OnSetup = OnAttach, OnPreUpdate = OnUpdate, OnFinalize = OnDetach }`
- :154-180 `OnAttach` 里 `addon->GetNodeById(53)` → `clippingContainerNode.AttachNode(mapComponentNode, NodePosition.AfterTarget)`，再逐层挂子节点
- :204-210 每帧把容器尺寸/位置对齐到原生组件

另一种是 `OmenTools.KamiToolKit` 的 `Addons/AttachedAddon.cs`——那是**贴边面板**（读宿主宽高后 `SetWindowPosition`），不是往宿主里插内容。

## 7. 与我们需求对照

| 需求 | KTK 有现成 API？ | 出处 |
| --- | --- | --- |
| 绑 `ItemDetail` 收生命周期 | 有 | `AddonController.cs:28-96`（`OnUpdate` = `PostUpdate`，:80-81 / :207-209） |
| 造一行字 | 有 | `Nodes/TextNode.cs` |
| 插进原生 addon | 有 | `NodeBase.Linking.cs:32-43` |
| 重建绘制名单 | 有（自动） | `NodeBase.Linking.cs:337-367` |
| 撑高窗口 | 部分 | `AtkUnitBaseExtensions.cs:48-66`（不覆盖九宫格/各级 RootNode） |
| 行跟着窗口底边 | **没有** | 见第 4 节，A/B 自写 |
| 换物品时的重排时机 | **没有** | 要按 `docs\插件开发坑.md:377-384` 的「锁目标值」自己写 |

## 8. 上手前必须实测的 4 件事

1. `ItemDetail` 的 `addon->WindowNode` 是否为 null（为 null → `Resize` 完全无效，HaselDebug 一眼可看）。
2. `Resize` 之后九宫格背景 / 框内布局是否跟着长。
3. `NodeFlags.AnchorBottom` + `SetSize` 是否真能让插入节点跟随底边。
4. 不装 OmenTools 时 KTK 的纯 `TextNode` 路径是否正常（验证 `ExpansionInterop` 这条隐藏依赖的范围）。

## 9. 与旧文档的冲突（待更正）

| 旧结论 | 位置 | 当前源码 |
| --- | --- | --- |
| 「`AttachNode` 只能挂在自己这套自建窗口上，插不进别人的 addon」 | `docs\kamitoolkit-原生界面.md:190`、`docs\KamiToolKit-上手指南.md:117` | **推翻**：`NodeBase.Linking.cs:31-43` 就有 `AtkUnitBase*` 重载 |

推测原结论来自旧版本（只看了 `NativeAddon` 那个重载）。两份文档择机更正；本次只记录，不改。
