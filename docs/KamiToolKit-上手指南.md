# KamiToolKit 上手指南（本机学习记录）

> 来源：`https://github.com/Dalamud-DailyRoutines/KamiToolKit`（DailyRoutines 维护的二次开发版）
> 扩展包：`https://github.com/AtmoOmen/OmenTools.KamiToolKit`
> 本机位置：`E:\FF14Dev\KnowledgeBase\KamiToolKit`（1.6 MB / 248 文件）、`E:\FF14Dev\KnowledgeBase\OmenTools.KamiToolKit`（539 KB / 39 文件）
> 两者都是 MIT。

## 一句话

**它把「用 C# 画一块游戏原生界面」这件事封装成了「建窗口类 + 挂节点树」**，不用再自己算 `AtkResNode` 的父子链、九宫格和绘制名单。

## 三个仓库的关系（别搞混）

| 仓库 | 干什么 | 体积 |
|---|---|---|
| `KamiToolKit` | 本体：`NativeAddon`（自建窗口）、`NodeBase`（节点树）、上百个现成节点、控制器、布局 | 1.6 MB |
| `OmenTools.KamiToolKit` | 扩展：补一批常用节点（背景、按钮、进度条、分页、原生弹窗）+ **`AttachedAddon`（挂靠面板）** | 539 KB |
| `FFXIVClientStructs.Expansion` | 上面两个都依赖的结构体扩展 | 745 KB |

**硬约束（作者原话 + csproj 实测）**：

- 三个项目必须**放在同一个解决方案里**才能编；`OmenTools.KamiToolKit` 单独编不了。
- **不支持原版 KamiToolKit 和它官方那个 NuGet 包**（二次开发改过行为）。
- SDK 是 `Dalamud.CN.NET.Sdk/15.0.0`，`Use_DalamudPackager=false`（它是库不是插件）。
- `Assets/**/*.png` 要 `CopyToOutputDirectory=Always`，否则图标空白。

## 能做什么 / 不能做什么

| 能做 | 不能做 |
|---|---|
| 新建自己的原生窗口（有标题栏、可拖、可缩放、记住位置） | 改游戏**已有**窗口的内部布局（那是 `AtkUnitBase` 手工操作，我们塞价格文字走的就是那条路） |
| 用现成节点拼界面：文字、图片、按钮、列表、分页、进度条、颜色选择器 | 自动帮你处理「游戏重算覆盖你的高度」这类问题 |
| 调原生弹窗：数值输入 / 文字输入 / 是-否 确认 | 单独引用官方 NuGet 包（不兼容） |
| 做一个**挂靠在某个游戏窗口旁边**的面板，跟着它开/关/缩放 | 直接往 `ItemDetail` 内部插节点（它管的是「自己的窗口」） |

## 核心概念（对应到文件）

| 概念 | 文件 | 说明 |
|---|---|---|
| `NativeAddon` | `BaseTypes/NativeAddon/` | 一个自建窗口。`InternalName` / `Title` 必填；`Size`、`Position`、`DepthLayer`、`IsOpen`；`Open()` / `Close()` / `Toggle()`；`AddNode(...)` 加内容 |
| `NodeBase` | `BaseTypes/NodeBase/` | 所有节点的基类，内部就是一颗 `AtkResNode` 树；管链接、事件、颜色主题、布局、可见性 |
| `ComponentNode` | `BaseTypes/ComponentNode/` | 组合节点（多个节点拼一个控件） |
| 控制器 | `Controllers/` | `AddonController` / `NativeAddonController` / `DynamicAddonController`：管理窗口的生命周期与批量创建 |
| `AttachedAddon` | **扩展包** `Addons/AttachedAddon.cs` | 挂靠面板：`HostAddon` 是宿主窗口，按 `AttachPosition` 贴到宿主四周，可自动跟随开/关 |
| 现成节点 | `Nodes/` | `TextNode`、`ImageNode`、`ButtonNode`、`ListItemNode`、`TabBar`、`GaugeBar`、`ColorPicker`、`BackgroundNode`（九宫格底图）…… |

## 最小例子（示意，编译前以源码为准）

```csharp
public class MyAddon : NativeAddon
{
    public MyAddon()
    {
        InternalName = "MyAddon";          // 窗口内部名，唯一
        Title        = "我的面板";          // 标题栏文字
        Size         = new Vector2(320, 200);
    }

    protected override unsafe void OnSetup()
    {
        AddNode(new TextNode
        {
            Position = new Vector2(12, 12),
            Size     = new Vector2(280, 24),
            Text     = "价格：4,000",
        });
    }
}

// 初始化（插件加载时一次）
await KamiToolKitLibrary.InitializeAsync(pluginInterface);

// 使用
var addon = new MyAddon();
addon.Open();
// 插件卸载时
addon.Dispose();
KamiToolKitLibrary.Dispose();
```

要点：**`OnSetup` 里只摆节点，不要在里面读游戏状态**；窗口开/关交给 `Open()` / `Close()`，不用自己调 `UpdateDrawNodeList`。

## 挂靠面板（`AttachedAddon`，我们最可能用到的）

它的用法是「继承 `AttachedAddon`，重写两个属性」，剩下的跟着宿主走：

```csharp
public class PricePanel : AttachedAddon
{
    protected override AttachedAddonPosition AttachPosition => AttachedAddonPosition.RightTop; // 贴在宿主机右上
    protected override Vector2 PositionOffset => new(4, 0);                                    // 额外偏移
    protected override bool AutoOpenAddon => true;                                             // 宿主开就开
    protected override float ScaleMultiplier => 1f;                                            // 跟随宿主 UI 缩放
}
```

- `AttachPosition` 支持 12 个方位：`LeftTop / LeftCenter / LeftBottom / TopLeft / TopCenter / TopRight / RightTop / RightCenter / RightBottom / BottomLeft / BottomCenter / BottomRight`。
- **宿主关闭时一定跟着关**；`AutoOpenAddon=false` 时由你自己 `Open()` / `Close()` / `Toggle()`。
- 好处：**不用改游戏窗口的任何节点**，贴着它放就行 —— 与「往 `ItemDetail` 里塞文字并撑高窗口」是两条完全不同的路，前者不碰原窗口，后者必须碰。

## 坑（实测或源码确认）

1. **不在同一 solution 就编不过**，会报一堆「找不到类型」；这不是配置问题。
2. **不能用官方 KamiToolKit 的 NuGet 包**，行为被改过。
3. `NativeAddon.InternalName` 重复会互相顶掉；调试时用 `/kamidbg`（`Debug/` 目录，需开 debug mode）。
4. 节点的坐标是**相对父节点**的，`ContentStartPosition` 已经替你算了内边距，别再减一次。
5. 扩展包的 `AttachedAddon` 里改 `ScaleMultiplier` 会立刻对已打开的窗口生效（内部调 `SetScale(host.Scale * value / GlobalUIScale, true)`）。
6. 卸载插件时 `KamiToolKitLibrary.Dispose()` 必须调，否则控制器和节点不释放（退出游戏可能崩）。

## 对我们的用处

| 场景 | 用不用它 |
|---|---|
| 把 `PriceInsight` 的设置窗口从 ImGui 换成原生 | ✅ 合适：现成节点够用，省掉手写布局 |
| 做「价格面板贴在道具简介框旁边」的第二种形态 | ✅ 合适：`AttachedAddon` 天生干这个，且**不动原窗口** |
| 探针（`HoverProbe`）要显示实时数值 | ✅ 合适：一个 `NativeAddon` + 两个 `TextNode` 就够 |
| 往 `ItemDetail` **内部**追加价格文字并撑高 | ❌ 不要用它：那条路是 `AtkUnitBase` 手工操作，见 `docs\插件开发坑.md` 第 15 节 |

## 还没读透的部分（后续要用再挖）

- `Nodes/Layout/`（`LayoutListNode` 等）的自动排版规则
- `Timelines/`（动画/缓动）
- `MapOverlay/`、`UiOverlay/` 两个覆盖层
- `Controllers/DynamicAddonController`（按条件动态建/销毁窗口）
