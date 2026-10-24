# OmenTools 学习笔记（本机实测 + 源码）

> 调研对象：`E:\FF14Dev\KnowledgeBase\OmenTools`，Clone（`--depth 1`）。
> 本文件由三代目 2026-10-25 整理。凡是推断都写「推测」，没读到的写「未确认」。

## 一句话定位

AtmoOmen（DailyRoutines / Omni 作者）抽出来的**公共运行时库**：一个静态初始化入口 `DService` + 一批常驻服务（Manager）+ 一堆原生扩展方法。它**不是 UI 框架**，也不提供「往别人 addon 里插节点」的封装。

- 仓库：<https://github.com/AtmoOmen/OmenTools>（MIT，见仓库根 `LICENSE`）
- 规模：**581 个 `.cs`，60,432 行**
- 依赖：`FFXIVClientStructs.Expansion`（必须，`ExpansionInterop.Initialize` 由它调）、若干 NuGet（`Microsoft.Extensions.DependencyInjection` 10.0、`TinyPinyin`、`Markdig`、`AngleSharp`、`GuerrillaNtp`、`Jeffijoe.MessageFormat`）

## 目录地图

| 目录 | 文件 / 行数 | 干什么 |
| --- | --- | --- |
| `DService.cs` | 1 个 | **唯一入口**：初始化、反初始化、静态单例 |
| `OmenService/` | 74 / 16,969 | 服务层：`Abstractions`（`OmenServiceBase`）+ `Implementations`（27 个 Manager） |
| `Interop/` | 113 / 7,098 | 原生调用封装、Sig 扫描、`Helpers`（Addon/GameView/Position/Raycast…） |
| `Info/` | 103 / 12,715 | 数据与常量：`Game/Data/Addons.cs`、`Lumina`、`DTOs`、`Algorithms` |
| `Extensions/` | 50 / 6,632 | `Atk*` / `Agent*` / 枚举 / 集合 / Dalamud 服务扩展 |
| `ImGuiOm/` | 50 / 6,105 | ImGui 控件（表格、组合框、颜色、树…） |
| `Dalamud/` | 45 / 4,028 | 与 Dalamud 服务对接的薄封装 |
| `Threading/` | 8 / 1,467 | `FrameworkWorkScheduler`、`Throttler`、`CountdownTimer`、`TaskHelper` |
| `Localization/`、`Utils/`、`Global/` | 少量 | 本地化、杂项、全局静态 |

## 生命周期（我们踩过坑的地方）

```csharp
// DService.cs:30
public static async Task InitAsync(
    IDalamudPluginInterface pluginInterface,
    IReadOnlyCollection<Type>? disabledServices = null,
    CancellationToken cancellationToken = default)

// DService.cs:37
if (IsInitialized || IsDisposed) return;      // ← 静态单例，只初始化一次
// DService.cs:56
ExpansionInterop.Initialize(instance.SigScanner.SearchBase);   // 顺带初始化扩展结构的地址表
// DService.cs:68
IsInitialized = true;

// DService.cs:85
public static async Task UninitAsync()        // 逐服务、逐 TaskHelper、逐 Hook 反初始化
// DService.cs:141-143
await IFramework.Instance().Run(ExpansionInterop.Uninitialize);
IsInitialized = false;
IsDisposed    = true;                          // ← 之后整个进程内不可再初始化

// DService.cs:151
public static DService Instance();
```

**两个必须记住的后果**：

1. **禁止在 `UninitAsync` 之后再初始化**：`IsDisposed` 一旦为真就永久挡住了（:37）。所以「禁用插件再启用」这种热重载，必须等上一次 `UninitAsync` 彻底跑完再 `InitAsync`（我们的 `ThanksGen2/OmenBootstrap.cs` 就是靠 `pendingUninit` + `Task.WhenAny(…, Task.Delay(5000))` 兜这个）。
2. **`UninitAsync` 内部大量走 `IFramework.Run`（下一帧调度）**，所以它是异步完成的，**不能在主线程阻塞等它**（会死锁）。同样地，游戏退出（`IsFrameworkUnloading`）时不要调它。

## 服务清单（`OmenService/Implementations/Managers/`）

27 个 Manager，`Tooltip`、`Command`、`ContextMenu`、`Window`、`Localization`、`Movement` 是子目录。常用的几个：

| 服务 | 文件 | 用途 |
| --- | --- | --- |
| `TooltipManager` | `OmenService/Implementations/Managers/Tooltip/TooltipManager.cs` | **改道具简介框的文字数组**（`StringArrayData[27]`），不是插节点：`RegItem`(:110)、`Unreg`(:124/:130)、`TriggerItemDetailUpdate()`(:52) |
| `AtkEventManager` | 同目录 | 给任意 addon 挂 Atk 事件监听 |
| `FrameworkManager` | 同目录 | 每帧回调分发 |
| `IPCManager` | 同目录 | 插件间 IPC |
| `CommandManager`/`ExecuteCommandManager` | `Command/` | 聊天命令注册与执行 |
| `GameResourceManager` | 同目录 | 图标 / 材质 |
| `FontManager` | 同目录 | 字体与文字尺寸 |

写服务：继承 `OmenServiceBase<T>`（`OmenService/Abstractions/OmenServiceBase.cs:6`），静态 `Instance()`（:8）即可取用；`IStaticOmenService` 是接口（`OmenService/Abstractions/IStaticOmenService.cs`）。

## 对我们这件事（原生 ItemDetail 插一行字）有用的部分

| 能力 | 出处 | 说明 |
| --- | --- | --- |
| 取 addon 指针 | `Info/Game/Data/Addons.cs:127` `public static AtkUnitBase* ItemDetail => AddonHelper.GetByName("ItemDetail");` | 一行拿到 |
| 按名取任意 addon | `Interop/Game/Helpers/AddonHelper.cs:42` `GetByName<T>(string)`、`:14 TryGetByName`、`:50 GetByName(string)` | 内部走 `IGameGui` |
| 节点尺寸 / 位置 | `Extensions/AtkResNodeExtension.cs:10-12`（`extension(scoped ref AtkResNode node)`） | `SetSize/SetWidth/SetHeight/SetPosition/GetOwnerAddon` |
| addon 就绪判断 | `Extensions/AtkUnitBaseExtension.cs:9-11` | `IsAddonAndNodesReady()`、`SetPosition` |
| 文字绘制尺寸 | `Extensions/AtkExtension.cs`（`extension(scoped ref AtkTextNode node)`） | `GetTextDrawSize(bool considerScale = false)` |

**它没有的东西**（这点很关键，别指望）：

- 没有任何「节点插入 / 挂链」封装（全库 `AddNode`/`CreateNode` 零命中）——挂节点得自己照 Dalamud `DtrBar.cs` 或原生写法手搓；
- 没有撑高窗口的 helper（`WindowNode` + 九宫格 + 各级 RootNode 三处同步，全要自己写）；
- `TooltipManager` 走的是**改文本数组**的路子，和「我们的节点」是两条路，混用会互相打架（推测：文本数组被多行撑高后，坐标计算会跟着变）。

## 坑

1. **`DService.InitAsync` 之后才能用它的任何东西**——`AddonHelper`、`Addons`、扩展方法内部都依赖它注入的 Dalamud 服务，早调就是空引用（我们实测过 NRE，栈在 `DalamudPluginInterface.GetService`）。
2. `DService` 是**进程级静态单例**，一个进程里只能有一个插件初始化它（推测：两个插件都调 `InitAsync`，第二个会因 `IsInitialized` 直接返回，但反初始化会互相拆台）。
3. 它会**往磁盘写配置**（`AddonConfigFile` 之类，见 KTK 那条同样的模式），换机或清配置时要留意。
4. 日志走 `IPluginLog`，但 `dalamud.log` 只收 Warning 及以上（本机实测 `LogLevel = 3`），Info 级的看不到。

## 重要发现：`AddonItemDetail` 结构体与「原生重排」链

`FFXIVClientStructs` 里本来就有 **ItemDetail 的完整结构体**（我们之前一直在 `UldManager.NodeList` 里瞎扫，属于绕远路）：

`E:\FF14Dev\KnowledgeBase\FFXIVClientStructs\FFXIVClientStructs\FFXIV\Client\UI\AddonItemDetail.cs`

```csharp
// :9-13
[Addon("ItemDetail")]
[GenerateInterop]
[Inherits<AddonItemDetailBase>]
[StructLayout(LayoutKind.Explicit, Size = 0x7C0)]
public unsafe partial struct AddonItemDetail {

// :54-55
[FieldOffset(0x428)] public AtkResNode* DescriptionGroup;
[FieldOffset(0x430)] public AtkTextNode* DescriptionText;      // 「效果」那段描述

// :33-34  ← 我们反复撞到的「Ctrl键 显示普通品质详细信息」那一行！
[FieldOffset(0x380)] public AtkResNode* ControlHints;
[FieldOffset(0x388)] public AtkComponentTextNineGrid* ControlHintsTextNineGrid;

// :104
[FieldOffset(0x598)] public AtkTextNode* MaterializeText;

// :136-140  ← 游戏自己的排版函数
[MemberFunction("E8 ?? ?? ?? ?? 41 8D 45 ?? 83 F8 ?? 77 ?? 48 8B 07 48 8B CF FF 50 ?? B2 ?? 48 8B CF 44 0F BF F0")]
public partial void UpdateGroupPositions(NumberArrayData* numberArray, StringArrayData* stringArray);

[MemberFunction("E8 ?? ?? ?? ?? 48 8B 45 ?? 48 8B 8F ?? ?? ?? ?? F7 40 ?? ?? ?? ?? ?? 75 ?? 33 D2 E8 ?? ?? ?? ?? E9 ?? ?? ?? ?? B2 ?? E8")]
public partial void GenerateItemTooltip(NumberArrayData* numberArray, StringArrayData* stringArray);
```

**OmenTools 用这条链把物料那一段改成自动换行 + 自动撑高**（`OmenService/Implementations/Managers/Tooltip/TooltipManager.cs:396-428`，方法名 `OnItemDetailPostUpdate`）：

```csharp
addon->MaterializeText->Width       = 350;
addon->MaterializeText->TextFlags  |= TextFlags.MultiLine | TextFlags.WordWrap;
addon->MaterializeText->LineSpacing = Math.Max(addon->MaterializeText->FontSize, (byte)14);
addon->MaterializeText->ApplyTextFlow();

addon->MaterializeText->GetTextDrawSize(&width, &height);
addon->MaterializeText->SetHeight(height);
addon->CraftingAndRepairsGroup->SetHeight((ushort)(addon->MaterializeText->Y + addon->MaterializeText->Height));

addon->UpdateGroupPositions(
    AtkStage.Instance()->GetNumberArrayData(NumberArrayType.ItemDetail),
    AtkStage.Instance()->GetStringArrayData(StringArrayType.ItemDetail));
```

**对我们的意义**（这条比库里所有别的都好用）：

1. 「撑高」这件事，游戏自己有 `UpdateGroupPositions` 会按各行内容重排整块布局——我们之前手搓「WindowNode + 九宫格 + 各级 RootNode + 提示行」四处，其实是在复刻它（而且必然复刻不全）。
2 想插一行**文本**，最稳的路线可能是「往 `StringArrayType.ItemDetail` 文本数组里加一行 → 再调 `UpdateGroupPositions`」，让游戏自己排版；这条路线 OmenTools 已经验证可行（它改的是 `MaterializeText` 那一段）。
3. 但用户要的是**我们自己的节点**（不是改游戏文本数组）。两种做法能不能混（先加文本数组让游戏排版，再把我们的节点 Align 到那一行）——**未验证**，属于下一阶段实验的事。
4. `ControlHints`（:380）+ `ControlHintsTextNineGrid`（:388）说明「Ctrl键 显示普通品质详细信息」那一行有**类型化字段**，不用再 `GetNodeById(2)` 猜。

## 还没读透的部分

- `ImGuiOm/` 50 个文件的控件清单（只确认它是 ImGui 组件库，没有细读）；
- `OmenService/Implementations/Managers/Tooltip/` 整个目录（只读了 `TooltipManager` 的公开方法签名）；
- `Interop/` 的 Sig 扫描机制（113 个文件，只看了 `Interop/Game/Helpers/`）。
