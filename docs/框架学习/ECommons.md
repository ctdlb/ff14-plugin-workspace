# ECommons 学习笔记

## 一句话定位

NightmareXIV 写的「Dalamud 插件全家桶」：把插件开发里所有样板活（服务注入、加号节流、任务队列、addon 读写、Excel 查询、ImGui 控件）打包成一个静态类库，一行 `ECommonsMain.Init` 全接管。

| 项 | 值 |
| --- | --- |
| 仓库 | https://github.com/NightmareXIV/ECommons |
| LICENSE 文件 | 根目录 `LICENSE.md` |
| 实际许可 | **MIT**，`Copyright (c) 2023 NightmareXIV`（`LICENSE.md:1-3`），全文无附加条款 |
| 版本 | `BaseVersion` = 3.2.1.26（`ECommons/ECommons.csproj:5`） |
| 规模 | **417 个 `.cs`，38,098 行**（`find . -name '*.cs' -not -path './.git/*'`） |
| 最近提交 | **2026-10-20 16:04:53 +0300**（`3ebb7c7`，Merge PR #185） |
| 分发 | NuGet 包 `ECommons`（`README.md:19` 的 `dotnet add package ECommons`） |

## 目录地图

一级子目录约 40 个，按职责归类（`.` 均指 `ECommons/`）：

- **初始化与服务**：`DalamudServices/`（`Svc.cs` 是全局服务门面）、`Loader/`（`ILoadable`、`MicroServices`、`PluginLoader`）、`Singletons/`、根目录 `Module.cs`
- **游戏数据**：`ExcelServices/`（`ExcelItemHelper`、`ExcelJobHelper`、`Enums/`）、`GameHelpers/`（`Player`、`Content`、`Map`）、`GameFunctions/`、`LazyDataHelpers/`、`LanguageHelpers/`、`TerritoryName.cs`
- **原生 / 交互**：`Hooks/`（各类 hook 结构体）、`EzHookManager/`、`Interop/`（`NativeFunctions`、`OpenFileDialog`）、`ObjectLifeTracker/`、`Reflection/`、`CSExtensions/`、`SplatoonAPI/`（画地面标记）
- **原生 UI**：`UIHelpers/`（142 个文件，`AddonMasterImplementations/` 119 个 addon 封装 + `AtkReader` + `AddonFinder`）、`EzContextMenu/`、`EzDTR/`
- **异步 / 调度**：`Schedulers/`（`TickScheduler`、`Sequential/TaskQueue`、`ThreadPool`）、`Throttlers/`、`Collections/`、`CircularBuffers/`
- **自动化**：`Automation/`（`Callback`、`Chat`、`Macro`、`LegacyTaskManager/`、`UIInput/`）、`Commands/` + `EzCmd.cs`、`Opcodes/`
- **绘制**：`ImGuiMethods/`（6,051 行，`ImGuiEx/` 14 文件 + 各种 Overlay 窗口）、`SimpleGui/`（`ConfigWindow`、`EzConfigGui`）
- **杂项**：`Configuration/`、`Logging/` + `SimpleLogger.cs`、`Events/` + `EzEventManager/`、`EzIpcManager/`、`EzSharedDataManager/`、`Networking/`、`MathHelpers/`、`Numeric/`、`StringHelpers/`、`GenericHelpers/`、`Gamepad/`、`WindowsFormsReflector/`、`Funding/`

代码量前四：`ImGuiMethods` 6,051 行 / `UIHelpers` 5,730 行 / `GenericHelpers` 3,058 行 / `Automation` 2,785 行。

## 核心 API

1. `ECommons/ECommonsMain.cs:59`
   ```csharp
   public unsafe static void Init(IDalamudPluginInterface pluginInterface, object instance, params Module[] modules)
   ```
   `Module` 枚举只有 6 个值：`All, DalamudReflector, ObjectFunctions, ObjectLife, SplatoonAPI, VfxTracking`（`ECommons/Module.cs`）。

2. `ECommons/DalamudServices/Svc.cs:16` —— 全局服务门面，44 个 `[PluginService]` 静态属性，用 `Svc.Framework`、`Svc.GameGui` 之类取代构造函数注入：
   ```csharp
   [PluginService] public static IAddonLifecycle AddonLifecycle { get; private set; }
   ```

3. `ECommons/GenericHelpers/AddonHelpers.cs:35` 与 `:146` —— 原生节点导航与取 addon 指针：
   ```csharp
   public static unsafe AtkResNode* GetNodeByIDChain(AtkResNode* node, params int[] ids)
   public static bool TryGetAddonByName<T>(string Addon, out T* AddonPtr) where T : unmanaged
   ```

4. `ECommons/UIHelpers/AtkReader.cs:12` —— 把 `AtkUnitBase` 的 `AtkValue` 数组结构化读出来（按偏移 + 数量循环解析）：
   ```csharp
   public abstract unsafe class AtkReader(AtkUnitBase* UnitBase, int BeginOffset = 0)
   ```

5. `ECommons/UIHelpers/AddonMasterImplementations/!AddonMasterBase.cs:8` —— 119 个 addon 的基类，提供 `IsAddonReady` / `HasFocus` / `ClickButtonIfEnabled`：
   ```csharp
   public abstract unsafe class AddonMasterBase<T> : IAddonMasterBase where T : unmanaged
   ```

6. `ECommons/EzHookManager/EzHook.cs:27` —— 按签名或地址建 hook，可 `Pause()` 保留原函数：
   ```csharp
   public EzHook(string sig, T detour, bool autoEnable = true, int offset = 0)
   ```

7. `ECommons/Automation/Callback.cs:74` —— 给 addon 发 Atk 回调（模拟点击的核心）：
   ```csharp
   public static void Fire(AtkUnitBase* Base, bool updateState, params object[] values)
   ```

8. `ECommons/Automation/LegacyTaskManager/TaskManager@Enqueue.cs:50` —— 按帧推进、可超时中断的协程式任务栈：
   ```csharp
   public void Enqueue(Func<bool?> task, int timeLimitMs, bool abortOnTimeout, string name = null)
   ```

9. `ECommons/Schedulers/Sequential/TaskQueue/SequentialTaskQueue.cs:56` —— 后台串行队列，返回可等待 token：
   ```csharp
   public TaskCompletionToken<T> Enqueue<T>(Func<T> task, bool clearQueue = false)
   ```

10. `ECommons/ImGuiMethods/EzOverlayWindow.cs:15` —— 贴屏幕角落、无边框不吃鼠标的自绘浮层：
    ```csharp
    public EzOverlayWindow(string name, HorizontalPosition hPos, VerticalPosition vPos, Vector2? offset = null)
    ```

11. `ECommons/Throttlers/EzThrottler.cs:14` + `ECommons/ExcelServices/ExcelItemHelper.cs:27`：
    ```csharp
    public static bool Throttle(string name, int miliseconds = 500, bool rethrottle = false)
    public static Item? Get(uint rowId) => Svc.Data.GetExcelSheet<Item>()!.GetRowOrDefault(rowId);
    ```

## 它解决什么问题

按「它真的强」的程度排，弱的直接略过：

- **原生 addon 读写（最强，5,730 行）**：119 个 addon 的强类型封装（按钮、列表项、文本框逐个给属性），`AtkReader` 把 `AtkValue` 解析成结构化数据，`Callback.Fire` 反向发事件。做「读游戏 UI 状态」几乎不用自己写 `GetNodeById`。
- **ImGui 控件库（6,051 行）**：`ImGuiEx` 补齐 Dalamud 没给的控件（可折叠表头、枚举下拉、Excel 数据下拉、拖放、多选、颜色选择、`EzTable`），还有 `Notify`/`MiddleOverlayWindow`/`TimedMiddleOverlayWindow` 这类提示浮层。
- **任务与节流**：三套东西并存——`TaskManager`（帧驱动、可超时）、`SequentialTaskQueue`（线程串行）、`ThreadPool`（受限并发），加 `EzThrottler`/`FrameThrottler` 做「每 N ms 最多一次」。对付「别每帧重算」这类问题最省事。
- **游戏数据**：`ExcelItemHelper.GetStat` / `GetRarity` / `GetCooldown`、`ExcelJobHelper`、`ExcelTerritoryHelper`，把 `GetExcelSheet<T>().GetRowOrDefault` 那套模板压成一行。
- **hook 与签名**：`EzHook`（签名/地址/偏移）、`EzHookFromCS`（给 FFXIVClientStructs 成员挂钩的 attribute）、`Svc.SigScanner`。
- **脚手架**：`EzConfig` 存档、`ConfigWindow` 一键配置窗、`EzCmd.Add` 命令、`EzIPC`（attribute 驱动的 IPC）、`Svc` 全局服务。这些是「省样板代码」，不是能力。
- 略过：`SplatoonAPI`（画地面圆/线）、`PartyFunctions`、`Gamepad`、`Funding`、`WindowsFormsReflector`（反射调 WinForms 做剪贴板，v3 起为了摆脱依赖才这么写）。

## 对我们的用处

目标：往游戏原生 `ItemDetail` 窗口插自己的文本节点并撑高窗口。

**能直接用的（脚手架层，不是解法）**

- `Svc.AddonLifecycle`（`DalamudServices/Svc.cs:16`）——注册 `PostUpdate` 的现成路子，正好对应「时机放 PostUpdate」。
- `EzThrottler.Throttle`（`Throttlers/EzThrottler.cs:14`）——切物品时算高度别每帧重算。
- `GenericHelpers.GetNodeByIDChain`（`GenericHelpers/AddonHelpers.cs:35`）/ `AtkReader`（`UIHelpers/AtkReader.cs:12`）——定位和校验 `ItemDetail` 现有文本节点，调试期有用。
- 兜底方案：`EzOverlayWindow`（`ImGuiMethods/EzOverlayWindow.cs:15`）/ `MiddleOverlayWindow`（`ImGuiMethods/MiddleOverlayWindow.cs:19`）——不改原生节点，纯 ImGui 浮层贴上去。**但不是我们要的效果**，原生框不会变高。
- `ConfigWindow`（`SimpleGui/ConfigWindow.cs:14`）、`EzCmd.Add`（`EzCmd.cs:15`）——配置窗和命令，顺手。

**明确没有的**

- **没有任何节点创建能力**：全仓 `grep -rn "UpdateDrawNodeList"` 零命中，也没有 `new AtkResNode` / 节点内存分配（`Marshal.AllocHGlobal` 只出现在 `Callback.cs:77` 造 `AtkValue`、`UIInput/` 造事件数据）。`GetNodeByIDChain`、`GetRootNode`（`AddonHelpers.cs:74`）都是只读导航。
- **没有 `ItemDetail` 的 AddonMaster**：119 个封装里只有 `ItemDetailCompare`（`UIHelpers/AddonMasterImplementations/ItemDetailCompare.cs:6`），而且它只有一个 `CloseButton => Addon->GetComponentButtonById(148)`（同文件 `:11`），跟文本/高度无关。**未确认**上游是否有意留白（也可能是 `ItemDetail` 一直在变）。
- **没有任何「撑高窗口」的封装**：无 `WindowHeight`/九宫格背景相关的辅助。

**结论**：ECommons 是「周边脚手架」，我们那个任务的核心难点（造节点、挂链头、改三处高度、`UpdateDrawNodeList`）它一点没帮上，全得自己写。值得作为依赖引入以省样板代码，但**不能指望它解决插节点**。

## 坑 / 限制

- **许可证**：MIT，**可以整段抄进我们插件**（保留版权声明即可）。这是它相对 Luna 的最大优势。
- **重度单例 + 强制初始化**：`ECommonsMain.Init` 必须在插件构造函数里调（`ECommonsMain.cs:59`），且 `Svc.Init(pluginInterface)` 失败会**弹 Windows MessageBox 并抛异常**（`ECommonsMain.cs:70` 的 catch 块，`:82` 调 `TerraFX.Interop.Windows.Windows.MessageBox`）。忘了 `Dispose()` 会留下 hook 与线程。
- **初始化有副作用**：`Init` 里直接 `Svc.Log.MinimumLogLevel = LogEventLevel.Verbose`（`ECommonsMain.cs:125`），会改全局日志等级。
- **全局静态服务使生命周期不可控**：`Svc.*` 全是静态属性，同一进程里多个插件共用同一份；出问题难定位到是谁改的。
- **依赖形态是 HintPath 而非 SDK**：`ECommons.csproj` 用 `Microsoft.NET.Sdk` + `$(DalamudLibPath)Dalamud.dll`（`ECommons.csproj:36,81-86`），而我们是 `Dalamud.NET.Sdk/15.0.0`。**推测**以 NuGet 包引用一般能共存（它 `ProduceReferenceAssembly=false`），但和 OmenTools 那次 `ProjectReference` 踩过的 SDK 属性互污染是同类风险，真要用优先走 NuGet 而非源码工程。
- `WarningsAsErrors=RS0030`（`ECommons.csproj:25`）+ 根目录 `ECommons/BannedSymbols.txt`：它自己禁了一批 API，抄代码时会带上这些禁令的语境。
- **`Player` 类踩坑**：`README.md:1-8` 明说 `ECommons.GameHelpers.Player` 与 Dalamud 的冲突，给了 `global using Player = ECommons.GameHelpers.LegacyPlayer.Player;` 这个绕法——说明它的 `Player` 正在重构且未收尾。

## 还没读透的部分

- `Automation/UIInput/`（约 2,785 行里的一部分）：`EventData`/`InputData` 怎么伪造 Atk 输入事件，未读。
- `UIHelpers/AtkEventDataBuilder.cs`、`AtkReaderImplementations/`：事件数据结构化构造的具体写法，只看了类名。
- `Hooks/` 下 14 个 hook 结构体（`ActionEffect`、`DirectorUpdate` 等）一个都没细读。
- `EzHookManager/EzHookCommon.cs` 与 `EzHookFromCS` 的自动挂载机制（attribute 扫描时机）未确认。
- 119 个 AddonMaster 里 `ItemDetail` 缺席的原因（未确认是漏了还是不打算做）。
- `Schedulers/SingleThreadRunnerHelper/`（`SingleThreadRunner`、`ThreadGuard`）的线程亲和性实现未读。
