# CriticalCommonLib 学习笔记（源码静态分析）

> 调研对象：`.tmp\study\CriticalCommonLib`（`git clone --depth 1`，只能看到 1 条提交）。只读调研（`git log`/`grep`/`wc`/`sed`），**未编译、未运行**。凡是推断都写「推测」，没读到的写「未确认」。

## 一句话定位

Critical-Impact 把自家插件 Allagan Tools（采集/背包/市场查询）攒了多年的「游戏数据层」抽成的公共库：背包与角色快照、Lumina 表包装、物品可获取性计算、悬停物品 Tooltip 钩子、Universalis 价格缓存。

- 仓库：<https://github.com/Critical-Impact/CriticalCommonLib>
- LICENSE 文件：`LICENSE`，正文是 **GNU GPL v3** 原文；`CriticalCommonLib.csproj` 无 `PackageLicenseExpression`、无 "or later" 字样（GPL-3.0-only 还是 or-later **未确认**）
- 规模：**152 个 `.cs` / 22,202 行**（不含 obj/bin）
- 最近提交：`34d364e` · `2026-09-13 19:41:05 +1000` · "Bump deps + fix cancellation"

## 目录地图

| 目录 | 文件 / 行数 | 干什么 |
| --- | --- | --- |
| `Services/` | 52 / 9,612 | 背包扫描、Tooltip 钩子、UI 窗口/节点、解锁跟踪、ODR 扫描 |
| `Crafting/` | 27 / 4,912 | 制作计算、物品清单、可获取性需求（最大一块业务逻辑） |
| `Models/` | 14 / 3,373 | `Inventory`（各容器槽位）、`InventoryItem`、`Character`、`CraftItem` |
| `MarketBoard/` | 9 / 1,375 | Universalis 抓取、价格缓存、后台队列 |
| `Addons/` | 10 / 186 | 原生 addon 封装（读节点做背包高亮） |
| 其余 | `Extensions/`16、`Agents/`4、`GameStructs/`5、`Enums/`4、`Interfaces/`3、`Resolvers/`2、`Helpers/`2、`Comparer/`1、`EventHandlers/`1、`Ipc/`1 | 零碎 |

依赖（`.csproj`）：`AllaganLib.GameSheets 2.2.9`、`AllaganLib.Monitors 2.2.9`、`AllaganLib.Shared 2.2.0`、`DalaMock.Host 6.1.9`、`Humanizer.Core`、`NaturalSort.Extension`、`SerialQueue`、`Sylvan.Data.Csv`、`System.Reactive 7.0.0`、`SonarAnalyzer.CSharp`；SDK `Dalamud.NET.Sdk/15.0.0`，`Use_DalamudPackager=false`，开了 `RestorePackagesWithLockFile`。

## 核心 API

### 1. Tooltip 钩子：全库唯一与 `ItemDetail` 直接相关的入口

```csharp
// Services/TooltipService.cs:96
public TooltipService(IGameInteropProvider gameInteropProvider, ILogger<TooltipService> logger, IFramework framework)
// Services/TooltipService.cs:24
public void AddTooltipTweak(TooltipTweak tooltipTweak)
// Services/TooltipService.cs:52-53
public virtual unsafe void OnGenerateItemTooltip(NumberArrayData* numberArrayData,
    StringArrayData* stringArrayData)
// Services/TooltipService.cs:74
protected unsafe void SetTooltipString(StringArrayData* stringArrayData, ItemTooltipField field, SeString seString)
// Services/TooltipService.cs:85 / :111
protected InventoryItem Item => HoveredItem;
public static InventoryItem HoveredItem { get; private set; }
```

钩的是 `AgentItemDetail` 的生成函数 —— `Services/TooltipService.cs:93` `[Signature("48 89 5C 24 ?? 55 56 57 41 54 41 55 41 56 41 57 48 83 EC ?? 48 8B 42 ?? 4C 8B EA", DetourName = nameof(GenerateItemTooltipDetour), UseFlags = SignatureUseFlags.Hook)]`；另有一条悬停物品钩子（`:89`，`"E8 ?? ?? ?? ?? 84 C0 0F 84 ..."`）用来填 `HoveredItem`。写字符串的实现（`:74-80`）值得抄，就三行：`var bytes = seString.Encode().ToList();` → `bytes.Add(0);` → `stringArrayData->SetValue((int)field, bytes.ToArray(), false, true, false);`

> 这里**显式补了 `\0`**，和我们实测的「`Encode()` 已是完整字节、别再补 `\0`」不矛盾——写的是不同容器（此处走 `AtkValues.SetValue` 槽位，我们那次直接写节点缓冲区）。为何 `SetValue` 需要终结符 **推测**：它按 C 字符串长度拷贝（**未确认**）。

### 2. 字段枚举：能改哪些字符串槽 + 哪些格子当前显示

```csharp
// Services/TooltipService.cs:156-
public enum ItemTooltipField : byte { ItemName, GlamourName, ItemUiCategory, ItemDescription = 13,
  Effects = 16, ClassJobCategory = 22, Levels = 23, DurabilityPercent = 28, SpiritbondPercent = 30,
  Param0 = 37, ... Param5 = 42, ShopSellingPrice = 63, ControlsDisplay = 64 }
// Enums/ItemTooltipFieldVisibility.cs:9 —— [Flags] 判当前显示的格子
```

可见性读法见 `Services/TooltipService.cs:43`（`GetNumberArrayData(30)->IntArray[5]` 取 flag）与 `:49`（单格判断：`IntArray[(int)tooltipField] == 0`）。

### 3. 悬停物品快照

```csharp
// Models/InventoryItem.cs:26
public class InventoryItem : IEquatable<InventoryItem>, ICsv, IItem   // Container/Slot/Quantity/Flags/Materia0-4/Stain/GlamourId…
// Models/InventoryItem.cs:129
public void FromGameItem(FFXIVClientStructs.FFXIV.Client.Game.InventoryItem inventoryItem)
// Models/InventoryItem.cs:359
public ItemRow Item => _itemSheet.GetRowOrDefault(ItemId) ?? _itemSheet.GetRow(1);
```

`TooltipService.HoveredItem` 就是一个填好的实例（含 HQ、容器、槽位），比自己去钩 `AgentItemDetail` 省事。

### 4. 背包快照

```csharp
// Services/IInventoryMonitor.cs:11-15
IEnumerable<InventoryItem> AllItems { get; }
Dictionary<(uint, ItemFlags), int> ItemCounts { get; }
event InventoryMonitor.InventoryChangedDelegate? OnInventoryChanged;
// Services/InventoryMonitor.cs:30
public InventoryMonitor(ICharacterMonitor characterMonitor, IInventoryScanner inventoryScanner, IFramework framework, IPluginLog pluginLog, Inventory.Factory inventoryFactory)
```

`Models/Inventory.cs` 有 **72 个** `InventoryItem?[]?` 属性（`CharacterBag1-4`、`Armoury*`、`RetainerBag1-5`、`HousingInteriorStoreroom1-11`、`FreeCompanyBag1-5`…），`:101` `public delegate Inventory Factory(CharacterType ownerType, ulong characterId);`。

### 5. 采集/制作日志跳转 + 只读 UI 接口

```csharp
// Services/IGameInterface.cs:11-17
public bool? IsItemGathered(uint itemId);
unsafe void OpenGatheringLog(uint itemId);
unsafe void OpenFishingLog(uint itemId, bool isSpearFishing);
unsafe bool IsInArmoire(uint itemId);
unsafe bool OpenCraftingLog(uint itemId);
// Services/Ui/IGameUiManager.cs:15-16
public unsafe bool TryGetAddonByName<T>(string Addon, out T* AddonPtr) where T : unmanaged;
unsafe T* GetNodeByID<T>(AtkUldManager uldManager, uint nodeId, NodeType? type = null) where T : unmanaged;
```

### 6. Universalis 价格缓存

```csharp
// MarketBoard/IMarketCache.cs:12-13
MarketPricing? GetPricing(uint itemId, uint worldId, bool forceCheck);
MarketCachePricingResult GetPricing(uint itemId, uint worldId, bool ignoreCache, bool forceCheck, out MarketPricing? pricing);
```

`MarketPricing` 带 `AveragePriceNq/Hq`、`MinPriceNq/Hq`、`SevenDaySellCount`、`LastUpdate`、`listings`；`HostedUniversalis : BackgroundService` 负责抓。另有 `Services/IUnlockTrackerService.cs`（`bool? IsUnlocked(ItemRow item, bool notify = true)`）与 `Crafting/IItemObtainabilityService.cs`（`IReadOnlyList<ObtainabilityRequirement> GetRequirements(ItemRow item, IngredientPreferenceType source, RecipeRow? recipe = null)`）。

## 它解决什么问题

一句话：**「我知道玩家的东西在哪、值多少、能不能拿到」**。

- **背包层**：扫描全部容器（含雇员、部队、房屋），产出 `InventoryItem` 快照 + 变更事件，免去每个插件自己算 slot 偏移。
- **数据层**：用 AllaganLib 的 `ItemSheet` 把裸 Lumina 行包成 `ItemRow`，再加「可获取性需求」「采集点/钓场/NPC 位置」这类跨表推导。
- **市场层**：接 Universalis 拿价格、落盘缓存。**UI 层**只剩两件事：把简介框的字读写、给背包格子打高亮。

## 对我们的用处

**结论：没有能直接用的东西。** 我们干的是「往 `ItemDetail` 插自己的文本节点 + 撑高窗口（`WindowNode`＋九宫格背景＋各级 `RootNode`、`PostUpdate` 改、新节点挂链头）」，而这套库里：

- 全库 `AddNode|CreateNode|LoadUld|Alloc` **0 命中**，`WindowNode|SetWindowSize|WindowHeight` **0 命中**；`Addons/`、`Services/Ui/` 只用 `UldManager.SearchNodeById(...)` 读节点做高亮（如 `Services/Ui/AtkArmouryBoard.cs:159`）。**它一行撑高/插节点的代码都没有。**
- 它走另一条路：改 `StringArrayData` / `NumberArrayData`。`TooltipTweak.OnGenerateItemTooltip` 两个数组都拿得到，所以「往简介框追加文本」对它是既有能力——但能否靠改 `numberArrayData` 让框自己变高 **未确认**（**推测**：框高由游戏内部 ATK 布局重算决定，只改数组不改节点属性大概率被覆盖，这正是 OmenTools 要 `TriggerItemDetailUpdate` 的原因）。

可以单独借的小零件（不值得为它们拉整个库）：

| 想要的东西 | 出处 | 说明 |
| --- | --- | --- |
| 简介框生成函数的 sig | `Services/TooltipService.cs:93` | 走「写字符串数组」路线时现成可用 |
| 悬停物品（含 HQ/容器/槽位） | `Services/TooltipService.cs:111` + `Models/InventoryItem.cs:129` | 不必自己钩 `AgentItemDetail` |
| 哪些格子当前显示 | `Services/TooltipService.cs:43` | 条件化显示的逻辑 |
| 物品富数据（可获取性/采集点） | `AllaganLib.GameSheets` 的 `ItemRow` | 只有做「这物品怎么获得」才需要 |

## 坑 / 限制

- **许可证：GPL-3.0（强 copyleft）**。抄任何一段进我们的插件，我们的插件也得是 GPL 并在分发时提供源码。**只能读思路、自己重写，不能复制粘贴。**
- **初始化复杂度高**：库内**没有** `IServiceCollection`/`AddSingleton`（0 命中），装配全丢给调用方（Allagan Tools 用 Autofac + `Resolvers/AutofacResolver.cs` + DalaMock.Host）。要自己注册 6 个 `.Factory` 委托（`CraftItem.Factory`、`CraftList.Factory`、`Character.Factory`、`Inventory.Factory`、`InventoryItem.Factory`、`CraftCalculator.Factory`），3 个 `BackgroundService` 子类（`HostedUniversalis`、`MarketCache`、`MarketRefreshService`）还得有 host 或手动 `StartAsync`。
- **构造链很深**：`Services/InventoryScanner.cs:63` 的 ctor 有 **14 个**参数（含 `CabinetSheet`、`ExcelSheet<MirageStoreSetItem>`、`ItemSheet`、`IAddonLifecycle`）；`CharacterMonitor` 8 个、`GameInterface` 8 个——意味着得先把 AllaganLib 的 sheet 集合搭起来；依赖也重（AllaganLib 三个包 + DalaMock.Host + Rx + Sylvan.Data.Csv + Humanizer）。
- **会抢同一个钩子**：它自己 hook 了 `AgentItemDetail` 生成函数，且 `TooltipService` 一 new 就 `InitializeFromAttributes` + `Enable`（`:96` 之后），没有「只建不装钩子」的选项；若我们也 hook 同一处（走节点路线通常不必），两个 detour 的先后与「谁最后写谁生效」需实测（**未确认**）。
- 版本绑定面**小**：全库只有 **3 个 `[Signature]`**（`Services/InventoryScanner.cs:430`、`Services/TooltipService.cs:89`、`:93`），这部分比大插件稳。
- 我们场景里它绝大部分（背包扫描、制作计算、价格缓存）都用不上。

## 还没读透的部分

- `Crafting/`（27 文件 / 4,912 行）：`CraftCalculator`、`CraftList`、可获取性推导链只看过接口；`MarketBoard/` 的缓存落盘格式与 `BackgroundTaskQueue` 细节也没读。
- `Services/OdrScanner.cs` + `MemorySortScanner`（ODR 排序解析）、`Addons/` 10 个文件（读了哪些节点、高亮怎么打）、`Models/Character.cs`、`Resolvers/MinifyResolver`、`Utils.cs`。
- GPL 是 v3-only 还是 or-later：`LICENSE` 是 stock 文本、`csproj` 无声明，**未确认**（真要引用必须先问作者）。
