# AtmoOmen（Dalamud-DailyRoutines）

调研时间 2026-10-25。源码 clone 在 `.tmp/study/AtmoOmen/`，本文所有路径都相对各自仓库根。
`OmenTools/...` 开头的引用指独立仓库 `AtmoOmen/OmenTools`（本机在 `<dev>\KnowledgeBase\OmenTools`），与 `docs\框架学习\OmenTools.md` 内容不重复。

## ① 一句话定位

国服 Dalamud 生态里体量最大的个人作者：DailyRoutines 一个人写了 300+ 个功能模块（公开的 `ModulesPublic` 就有 404 个 `.cs`、120,482 行），并把「模块基类 + 宿主注入 + 每模块独立配置文件 + hook 自动释放 + 运行时 Roslyn 编译模块」做成了一套完整骨架；同时维护 Dalamud / FFXIVClientStructs 的国服分支与国服 SDK。

我们该学的是骨架，不是功能：

1. **模块生命周期的两端契约**：`Init/Uninit` 由基类包一层（`PublicInit/PublicUninit`），资源释放有明确的自动/手动边界（`Hook<>`/`MemoryPatch` 自动，其它手动）。
2. **改原生 UI 的挂链/摘链纪律**：谁来 `UpdateDrawNodeList()`、卸载时怎么判 addon 还活着（KamiToolKit 的实现把这件事做对了）。
3. **配置迁移 + 原子写**：`PreviousModuleName` 迁移 + 去抖原子落盘的写法可以直接搬。

不该学的：**他的代码是 AGPL-3.0**（`DailyRoutines.Common/LICENSE`、`DailyRoutines.ModulesPublic/LICENSE`），不能抄进我们的仓库；**核心插件源码闭源**，只能读契约、不能读实现。

## ② 仓库清单

| 名称 | 星数 | 语言 | 最近提交 | 一句话作用 |
| --- | --- | --- | --- | --- |
| `DailyRoutines` | 10 | — | 2026-10-24 | 主插件仓库，**只有 README + `Resources/icon.png` + `Resources/Modules/*.webp|json`，核心源码闭源**（`git ls-tree HEAD` 实证，无 `.gitmodules`、无 `.cs`） |
| `DailyRoutines.ModulesPublic` | 48 | C# | 2026-10-25 00:12 | 公开模块实现集，404 个 `.cs` / 120,482 行，AGPL-3.0 |
| `DailyRoutines.Common` | 0 | C# | 2026-10-24 13:46 | 模块系统抽象层（ModuleBase / ManagerBase / ModuleCompiler / 配置模型），AGPL-3.0 |
| `DailyRoutines.ModuleTemplate` | 7 | C# | **2025-09-27（API 13，已过时一年）** | 官方模块模板，里面的 API 现在已不存在，只能看「曾经的最小模块长什么样」 |
| `Dalamud.CN.NET.Sdk` | 7 | MSBuild XML | 2026-04-30 | 国服编译 SDK（MIT），与官方 15.0.0 只差 3 处 |
| `EXDViewer` | 22 | Rust | 2026-10-11 | 游戏数据/资源查看器，内置 `rmcp` 写的 MCP 服务（查询接口设计值得看） |
| `KamiToolKit` | 38 | C# | 2026-10-24 | 原生 UI 节点库（**MIT**），DailyRoutines 全部 UI 的地基，232 个 `.cs` / 33,057 行 |
| `DailyRoutines.CodeAnalysis` | 3 | C# | 2026-07-17 | Roslyn 规范分析器（DR0001/0002/0008/0009），以 NuGet 包形式强制模块代码风格 |

## ③ 逐题回答

### 1. 模块系统

**基类**：`public abstract class ModuleBase : IEquatable<ModuleBase>`（`DailyRoutines.Common/Module/Abstractions/ModuleBase.cs:16`，全文 454 行）。

构造函数里做完的事（`:20-34`）：`ModuleGUID = Guid.Empty.ToString()`（`:20`）、`ModuleName = GetType().Name`（`:21`）、`WithConfig = File.Exists(ConfigFilePath)`（`:22`）、用反射找本类型自己声明的无参 `ConfigUI` 来决定 `WithConfigUI`（`:24-32`）、`cleanupAction = GenerateCleanupDelegate(GetType())`（`:34`）。

对外暴露（`:39-46`）：`ModuleName`（可覆写）、`PrecedingModules / PairModules / ConflictModules`、`WithConfigUI`、`WithConfig`、`ModuleIdentifier`、`ModuleGUID { get; init; }`。

**生命周期方法**（全部由基类包一层，模块作者只覆写 `protected virtual`）：

| 方法 | 位置 | 说明 |
| --- | --- | --- |
| `Info` | `ModuleBase.cs:186` | `public virtual ModuleInfo`，`field ??=` 懒初始化 |
| `Permission` | `ModuleBase.cs:193` | 同上，区域/默认开关/测试者可见性 |
| `Init()` | `ModuleBase.cs:195` | 唯一的主初始化入口 |
| `ConfigUI()` | `ModuleBase.cs:197` | 设置界面，被 `OverlayConfig` 调 |
| `OverlayUI / OverlayOnOpen / OverlayOnClose / OverlayPreDraw / OverlayPostDraw / OverlayUpdate / OverlayPreOpenCheck` | `ModuleBase.cs:199-211` | 悬浮窗（ImGui）的 7 个挂点 |
| `Uninit()` | `ModuleBase.cs:213` | 手写清理 |

包一层的实现：

- `PublicInit()`（`ModuleBase.cs:114-133`）：`if (IsEnabled) return;` → `IsDisposed = false` → 注册 IPC（`IPCAttributeRegistry.RegObjectIPCs(this)`）→ `Init()` → `IsInitialized = true`；`catch` 时 `DLog.Error("初始化模块时发生错误", ex)` **然后直接 `PublicUninit()` 回滚**。
- `PublicUninit()`（`ModuleBase.cs:135-164`）：`if (IsDisposed) return;` → `try { Uninit() } catch { DLog.Error("卸载模块时发生错误") }` + `try { BaseUninit() } catch { DLog.Error("基础卸载模块时发生错误") }`，最后 `finally { IsDisposed = true }`。**两层都各自 try/catch，`Uninit` 抛异常不会阻止基础清理。**
- `BaseUninit()`（`ModuleBase.cs:225-242`）：摘悬浮窗 → `IPCAttributeRegistry.UnregObjectIPCs(this)` → `TaskHelper?.Abort(); TaskHelper?.Dispose(); TaskHelper = null` → `cleanupAction?.Invoke(this)`。

**注册 / 启停**：

- 模块**不用注册**：继承 `ModuleBase` + 有无参构造即可（反射扫描；`DailyRoutines.Common/Module/Compilers/ModuleCompiler.cs:155-207` 的 `GetDerivedTypes<T>` 就是扫「非抽象 + 可赋值 + 有无参构造」的实现，宿主用它扫程序集 —— **推断**，因为真正的宿主在闭源 dll 里）。
- 启停走**静态服务定位器**，不是 DI：`Load(bool affectConfig = false)` → `ManagerHost.Current.LoadAsync(this, affectConfig)`（`ModuleBase.cs:52-62`），`Unload()` → `ManagerHost.Current.UnloadAsync(...)`（`:64-74`）。
- `ManagerHost.Current` 是 `IManagerHost` 的静态可注入属性，未注册时 `throw new InvalidOperationException("管理器能力提供方宿主尚未注册")`（`DailyRoutines.Common/Runtime/Hosts/ManagerHost.cs:5-12`）；接口本身见 `DailyRoutines.Common/Runtime/Abstractions/IManagerHost.cs`（`Get<T>()`、`LoadAsync`、`UnloadAsync`、`AddWindow`、`RemoveWindow`、`GetLoc`）。
- 悬浮窗也走同一个宿主：`Overlay` 构造函数里 `ManagerHost.Current.AddWindow(this)`（`DailyRoutines.Common/Interface/Windows/Overlay.cs:13-16`），`DrawConditions() => ModuleBase.IsEnabled`（`:41`），窗口 ID 用 `###{FullName}` 防重名（`:13-14`）；`OverlayConfig` 同构（`Interface/Windows/OverlayConfig.cs:10-20`）。

**配置存储**：

- 每模块一个 JSON：`ConfigFilePath => Path.Join(IDalamudPluginInterface.Instance().GetPluginConfigDirectory(), $"{ModuleName}.json")`（`ModuleBase.cs:248-249`）；模块自己的资源目录是 `.../Module/{ModuleName}`（`:251-262`）。管理器配置在 `.../Manager/{TypeName}.json`（`DailyRoutines.Common/Manager/Abstractions/ManagerBase.cs:33-41`）。
- `LoadConfig<T>() where T : ModuleConfig`（`ModuleBase.cs:264-302`）：文件不存就 `Activator.CreateInstance<T>()`；**若 `tempConfig.PreviousModuleName` 非空且旧配置文件存在 → 读旧文件、迁移、`SaveConfig`**（`:276-293`）。这就是配置迁移机制，旧名类里覆写 `PreviousModuleName` 即可（`DailyRoutines.Common/Module/Abstractions/ModuleConfig.cs:7-8`，基类只有一个 `[JsonIgnore] public virtual string? PreviousModuleName => null`）。
- `SaveConfig<T>`：`JsonConvert.SerializeObject(config, Formatting.Indented, JsonSerializerSettings.GetShared())` + `SecureSaveHelper.Instance().WriteAllText(...)`（`ModuleBase.cs:304-320`）。
- 剪贴板导入导出：base64 + JSON（`ModuleBase.cs:322-365`）。
- 模块里调用形态（实证）：`config = Config.Load(this) ?? new();`（`DailyRoutines.ModulesPublic/Combat/AutoDisableBattleBGM.cs:33`）、`config.Save(this)`（`:42`）。`Config.Load(this)` / `config.Save(this)` 这两个扩展属于命名空间 `DailyRoutines.Extensions`，**不在 Common 里，来自闭源 dll，实现未确认**；Common 里同构的写法可以在 `DailyRoutines.Common/Manager/Extensions/ManagerConfigExtension.cs:7-14` 看到（`extension<T>(T config) where T : ManagerConfig` + `public static T? Load(ManagerBase)` / `public void Save(ManagerBase)`）。
- 关键约定：配置类**不许用 `readonly` 字段**，由分析器 DR0008 强制（`DailyRoutines.CodeAnalysis/Rules/Design/ConfigurationClassesMustNotUseReadonlyFieldsAnalyzer.cs:10-20`）。

**hook / patch 自动释放（重要，也是盲区）**：

- `GenerateCleanupDelegate(Type)` 用表达式树扫**全部字段**（`BindingFlags.Instance|NonPublic|Public|Static`，`ModuleBase.cs:385-388`），只挑两类：泛型定义等于 `Hook<>` 的字段，以及 `MemoryPatch` 可赋值的字段（`:391-397`）；没有匹配字段直接返回 `null`（`:400`）；生成的委托对每个字段 `if (field != null) { DisposeResource(field); field = null; }`（非 `readonly` 才会置空），最后 `Expression.Lambda<Action<ModuleBase>>(...).Compile(true)`（`:405-435`）；`DisposeResource` 里 try/catch + `DLog.Error($"[ModuleBase] 释放模块资源 {resource.GetType().Name} 时发生错误", ex)`（`:438-451`）。
- **盲区**：只有 `Hook<>` 和 `MemoryPatch` 会被自动释放。自建 AtkNode、事件订阅、`TaskHelper` 以外的一次性资源，必须自己写 `Uninit`（`TaskHelper` 例外，`BaseUninit` 会替你 Abort+Dispose，`ModuleBase.cs:231-238`）。

**最小模块长什么样**（现行 API，不是模板仓库里那份）：

- 无配置、纯 hook（39 行）：`DailyRoutines.ModulesPublic/System/AutoSkipBuddyFeedScene.cs:10`（`: ModuleBase`）、`Info`（`:12-17`）、`static readonly CompSig`（`:19-20`）、`Hook<...>? xxxHook`（`:25`）、`Init()` 里 `??= Sig.GetHook<...>(detour); Hook.Enable()`（`:27-31`），**整个文件没有 `Uninit`** —— 因为 hook 由 `cleanupAction` 自动释放。
- 无配置、纯 patch（33 行）：`DailyRoutines.ModulesPublic/Action/DisableGroundActionAutoFace.cs:17-20`（`Permission { AllDefaultEnabled = true }`）、`:22`（`MemoryPatch xxxPatch = null!`）、`:24-32`（`new MemoryPatch("74 ?? 48 8D 8E ...", [0xEB])` + `Enable()`）。
- 要注册 addon 事件就必须自己写 `Uninit`：`DailyRoutines.ModulesPublic/Interface/AutoPreserveCollectable.cs:23-27`（`RegisterListener` / `UnregisterListener` 成对）。
- 带配置（62 行，最完整的范例）：`Combat/AutoDisableBattleBGM.cs:29`（`private Config config = null!;`）、`:33`（`config = Config.Load(this) ?? new();`）、`:39-44`（`ConfigUI()` 里 `ImGui.Checkbox(...)` 后立刻 `config.Save(this)`）、`:58-61`（嵌套 `private class Config : ModuleConfig { public bool EnableInDuty; }`）。

**`ModuleTemplate` 已经过时，别照抄**：`DailyRoutines.ModuleTemplate/DailyRoutines.ModuleTemplate.csproj:1` 是 `Dalamud.CN.NET.Sdk/13.1.0`，`:46` 写死 `E:\XIVLauncherCN\pluginConfigs\DailyRoutines\Dev`，模板代码用 `class AutoSoulsowModuleTemplate : DailyModuleBase`（`DailyRoutines.ModuleTemplate/AutoSoulsow.cs:11`）、`Category = ModuleCategories.Action`（`:13-18`）、`DService.ClientState...`（`:24-26`）、`base.Uninit()`（`:107`）—— 这些类型在当前版本里都已不存在。它唯一的价值是说明「最小模块曾经只有 Info + Init」。

**同构的四层扩展点**（同一个套路复制了 4 遍，说明这套骨架是可复用的）：`Module/`（模块）、`Manager/`（管理器）、`Notification/`（通知渠道）、`DataUploader/`（数据上传），各自都是 `XxxBase` + `XxxConfig` + `XxxConfigExtension`（目录见 `DailyRoutines.Common/` 下的 47 个 `.cs`）。

### 2. 插件主类

- **入口类名 = `DailyRoutines.Plugin`**：对已安装的 `DailyRoutines.dll`（11,116,032 字节，无 pdb）做 `grep -a` 元数据串，含 `DailyRoutines.Plugin`（4 次）、`ModuleManager`（21 次）、`ManagerHost`、`IDalamudPlugin`，无 `PluginBase`。**源码闭源，初始化/卸载的实际顺序读不到，下面是可证的契约层事实 + 推断。**
- **没有 DI 容器**，是三种静态服务定位器：
  1. `ManagerHost.Current`（`DailyRoutines.Common/Runtime/Hosts/ManagerHost.cs:5-12`）—— 宿主接口，最外层。
  2. `ManagerBase<T>.Instance()`（`DailyRoutines.Common/Manager/Abstractions/ManagerBase.cs:10-14`）—— 要求 `IsInitialized && !IsDisposed`，否则抛 `InvalidOperationException($"管理器 {typeof(T).Name} 尚未注册或初始化")`。
  3. OmenTools 的 `DService` / `OmenServiceBase<T>.Instance()`（见 `OmenTools/DService.cs:30/37/85`，`docs\框架学习\OmenTools.md` 已有笔记）。
- **卸载顺序的契约**（从下往上都是实证，只有最外层的调用方是推断）：
  1. 宿主 `UnloadAsync` → 模块 `PublicUninit()`（`ModuleBase.cs:135-164`）→ `Uninit()`（作者手写）→ `BaseUninit()`（`ModuleBase.cs:225-242`：摘悬浮窗 → 解 IPC → `TaskHelper.Abort()+Dispose()` → `cleanupAction` 释放 `Hook<>`/`MemoryPatch`）。
  2. 管理器自己是一条**四态状态机**：`STATE_CREATED / RUNNING / STOPPING / STOPPED = 0/1/2/3`（`ManagerBase.cs:322-325`），`PublicInitAsync` 用 `Interlocked.CompareExchange` 抢状态（`:45`）；`PublicUninitAsync` 先 `PublicStopAsync`（`:65`），Stop 里**先 `CancelAsync()` 再在框架线程跑 `Stop()`**（`:104/:113`），然后 `Task.Run(DrainBackgroundTasksAsync)`（`:73`）**等所有后台任务退出**，再 `IFramework.Instance().Run(Uninit)`（`:77`）把清理放到框架线程，`finally` 里 `TryDisposeCancellationTokenSource`（`:84-89`）；`DrainBackgroundTasksAsync`（`:220-246`）用 `AsyncLocal<long?>` 排除「自己等自己」（`:234`）；`TryDisposeCancellationTokenSource`（`:271-280`）三条件都满足才 Dispose。
  3. 运行时编译的模块全部卸载：`ModuleCompiler.UnloadAllAsync()` 清编译/程序集缓存 → `ModuleSerializationCache.RemoveAssemblies` → `FrameworkWorkScheduler.RunAsync(contexts, TryUnloadContext)`（`DailyRoutines.Common/Module/Compilers/ModuleCompiler.cs:38-78`）；可卸载上下文是 `AssemblyLoadContext(name, isCollectible: true)`（`Module/Compilers/ModuleLoadContext.cs:6`）。
- **他踩过的 hook 泄漏 / 卸载时序问题，代码里有三处明确痕迹**：
  1. `ModuleSerializationCache`（183 行，`Module/Compilers/ModuleSerializationCache.cs`）整篇都是在**反射清 Json.NET 与 `System.ComponentModel` 的静态缓存**（`JsonTypeReflector+CreatorCache.Instance`、`DefaultContractResolver._contractCache`、`TypeDescriptor.s_providerTable`、`ReflectTypeDescriptionProvider._typeData` 等，`:21-128`），并逐个判断缓存项是否引用目标程序集（`ReferencesAssembly`，`:158-175`）。这是可卸载 ALC 泄漏的典型死法：类型被第三方静态字典钉住，ALC 永远收不掉。
  2. KamiToolKit 的节点 `Dispose()` 里第一件事是**判游戏是否正在退出**：`if (IFramework.Get().IsFrameworkUnloading) { LogIndented("Game is shutting down, aborting manual dispose.", ...); return; }`（`KamiToolKit/BaseTypes/NodeBase/NodeBase.Dispose.cs:63-67`），随后校验节点有效性（`:71`）、带 `SuppressNativeUpdate` 逐个 Dispose 子节点（`:79-87`）、解 tooltip 事件（`:89`）、`AtkStage.Instance()->ClearNodeFocus(ResNode)`（`:92`）、`DetachNode()`（`:95`），还有双 Dispose 守卫（`:55`）。**注意：Common 里没有 `IsFrameworkUnloading` 字样，这个守卫只在 KamiToolKit 层 —— 也就是说 OmenTools 那套节点封装没这层保护。**
  3. 摘链时先判 addon 还活着，再动它的 UldManager（见下节 `NodeBase.Linking.cs:288-320`）。
- 另外还有一个防篡改设计：安装目录里的 `Dev/DailyRoutines.ReleaseIntegrity` 明文列了 4 个 dll 的 SHA256（`DailyRoutines.dll|5685329F...` 等），**推测**是加载前校验 DLL 未被替换。
- 依赖面（`Dev/DailyRoutines.deps.json`）：`DailyRoutines/2.2.4.1`，`runtimeTarget .NETCoreApp v10.0`，直接依赖 Common / KamiToolKit / `Microsoft.CodeAnalysis.CSharp 5.9.0` / OmenTools / OmenTools.KamiToolKit / Otp.NET / RSASharp / `System.Management 10.0.11` / TimeAgo.Core / TinyPinyin。

### 3. 原生 UI

**代码在哪**：改游戏自带窗口的模块**全部集中在 `DailyRoutines.ModulesPublic/Interface/`（137 个 `.cs`）**，另有 `System/`（89 个）里的少数（如 `System/AutoAntiCensorship.cs`）。用 `AtkTextNode* / AtkResNode* / GetStringArrayData / StringArrayData` 关键词筛出 20 个文件，其中代表：`AutoClaimPVPRewards`、`AutoCollectableExchange`、`AutoDisplayIDInformation`、`AutoDisplayMSQProgress`、`AutoHideExpBar`、`AutoNumericInputMax`、`AutoRecommendFauxHollows`、`AutoRetainerWork.PriceAdjustWorker`、`AutoSharpenInterfaceText`、`AutoShopPurchase`、`BetterMarketBoard.UI.MarketData`、`ColorThemeHotReload`、`CustomizeInterfaceText`、`OptimizedCharacterClass`、`OptimizedFriendList.Utils`、`OptimizedLetter`、`OptimizedMacro`、`OptimizedQuickPanel`、`OptimizedSalvage.NativeAddon`、`ShopDisplayRealItemIcon`、`ScrollableTabs`。

**四种手法（各举例）**：

1. **KamiToolKit 节点（主流，占比最大）**：`new TextInputNode { ... }` + `searchBarNode.AttachNode(component)`（`DailyRoutines.ModulesPublic/Interface/FastBLUSpellbookSearchBar.cs:75-96`），生命周期是 `AddonEvent.PostDraw` 里懒创建、`PreFinalize` 里置 `null`、`Uninit` 里 `Dispose()`（`:38-44`、`:46-102`）；同一文件还示范了「用原生 API 把原窗口标题节点藏掉」：`component->GetComponent()->UldManager.SearchNodeById(3)->ToggleVisibility(false)`（`:64-73`），以及用 Agent 事件回填输入：`AgentId.AozNotebook.SendEvent(2, 0, 0U, input)`（`:128`）。另一个例子：`IconButtonNode { Size=36f, IconId=66469, OnClick=..., TextTooltip=..., Position=new(298,86) }` + `AttachNode(CharacterInspect->RootNode)`（`Interface/AdventurerPlateThroughInspect.cs:56-69`）。
2. **裸 ClientStructs 节点**：`var textNode = (AtkTextNode*)button->UldManager.SearchNodeById(6);` 后 `textNode->SetText(text)`（`Interface/AutoDisplayMSQProgress.cs:61-64`）；`component->AtkTextNode->SetNumber(max)`，前置判 `component->AtkResNode->NodeFlags.HasFlag(NodeFlags.Visible)`（`Interface/AutoNumericInputMax.cs:116-131`）。
3. **改 StringArrayData（文本数组）**：`AtkStage.Instance()->GetStringArrayData(StringArrayType.Hud2)`（`Interface/AutoDisplayIDInformation.cs:239`）、`...GetStringArrayData(StringArrayType.ItemSearch)->StringArray[208 + (6 * counter)]`（`Interface/BetterMarketBoard/BetterMarketBoard.UI.MarketData.cs:726`）。这与 `docs\框架学习\OmenTools.md` 里 TooltipManager 走 `StringArrayData[27]` 是同一类手法。
4. **hook 原生文本函数 / 内存 patch**：`CompSig AtkTextNodeSetTextSig = new("48 85 C9 0F 84 ?? ?? ?? ?? 4C 8B DC 53 56")` → `Hook<AtkTextNodeSetTextDelegate>`（`Interface/AutoSharpenInterfaceText.cs:25/33/40`），detour 里先 `((AtkResNode*)node)->GetOwnerAddon()` 判是哪个 addon 再决定要不要改写（`:55`），否则 `Original(node, text)`（`:50`）；极端例子 `System/AutoAntiCensorship.cs:38-68` 用 6 个 CompSig 改聊天/招募板的屏蔽词过滤（`#if DEBUG` 门控相关模块见 `System/AutoDumpCensoredWords.cs:1`）。

**addon 事件统一走 `IAddonLifecycle`**：`RegisterListener(AddonEvent.PostDraw / PostSetup / PreFinalize / PreRequestedUpdate / PostUpdate / PreShow / PreDraw / PostRefresh / PreHide, "AddonName", handler)`，`Uninit` 里 `UnregisterListener`；批量 addon 直接传数组。这是所有 UI 模块的共同骨架（例：`Interface/FastBLUSpellbookSearchBar.cs:34-35`、`Interface/AutoPreserveCollectable.cs:23-27`）。

**KamiToolKit 把三个坑替你做掉了**（这就是我们该抄的部分，MIT 可用）：

- **挂链后重建绘制名单**：`NodeBase.Linking.cs:337-366` 的 `UpdateNative()` —— `MarkDirty()` 重算位置 → `ParentUldManager->AddNodeToObjectList(this)` 并把子节点的 UldManager 一起补上 → 若父 addon 存在则 `UldManager.UpdateDrawNodeList()` + `UpdateCollisionNodeList(false)`（`:364-365`）。
- **摘链前判 addon 存活**：`RemoveParentAddonReferences()`（`:288-320`）遍历 `RaptureAtkUnitManager.Instance()->AllLoadedUnitsList` 确认 addon 还在列表里（`:296-307`），不在就放弃、只把子节点的 `ParentAddon` 置空（`:310-314`）；确认活着才 `UpdateDrawNodeList()` + `UpdateCollisionNodeList(false)`（`:317-320`），且可用 `SuppressNativeUpdate`（`:17`）跳过。
- **不支持的场景会喊出来**：挂 `NamePlate` 时 `IPluginLog.Get().Warning("Warning, attaching to AddonNamePlate is not supported. Use OverlayController instead.")`（`:361-362`）。

### 4. 国服 SDK 差异（文件级）

判断依据是本机 NuGet 缓存里两个 15.0.0 包的**直接 diff**：`~/.nuget/packages/dalamud.net.sdk/15.0.0/Sdk/` vs `~/.nuget/packages/dalamud.cn.net.sdk/15.0.0/Sdk/`（各 3 个文件）。仓库 `Dalamud.CN.NET.Sdk/` 内容与包一致（同样 3 个 Sdk 文件 + csproj/sln/LICENSE/README）。

**实质差异只有 3 处，其余逐行相同：**

1. `Sdk.props` 多了一个开关属性组（`Dalamud.CN.NET.Sdk/Dalamud.CN.NET.Sdk/Sdk/Sdk.props:26-29`）：
   `<Use_Dalamud_CN Condition="'$(Use_Dalamud_CN)' == ''">true</Use_Dalamud_CN>` —— 默认 true。
2. `DalamudLibPath` 的 Windows 分支拆成两条（`Sdk.props:32-38`）：`Use_Dalamud_CN == true` → `$(appdata)\XIVLauncherCN\addon\Hooks\dev\`（`:33`），`!= true` → `$(appdata)\XIVLauncher\addon\Hooks\dev\`（`:34`）；官方包只有后一条。Linux / OSX / `DALAMUD_HOME` 三条完全相同（`:35-37`，`DALAMUD_HOME` 非空时覆盖）。
3. `Sdk.targets` 只有两条提示文本里的包名前缀不同：`Dalamud.CN.NET.Sdk: Dalamud installation not found at $(DalamudLibPath)`（`Dalamud.CN.NET.Sdk/.../Sdk/Sdk.targets:6`）、`Dalamud.CN.NET.Sdk: root at $(DalamudLibPath)`（`:10`）；target 名 `EnsureDalamudLibPathExists` / `PrintRootPath` 与结构一致。

**完全相同的部分**（`Sdk.props`，官方 :41-94 / CN :41-94 同号）：

- `TargetFramework net10.0-windows`（`:41`）、`LangVersion 14.0`（`:42`）、`Platforms/PlatformTarget x64`（`:45-48`）、`Nullable enable`、`AllowUnsafeBlocks true`、`ProduceReferenceAssembly false`、`AppendTargetFrameworkToOutputPath false`、`RestorePackagesWithLockFile true`、`CopyLocalLockFileAssemblies true`（`:55`）、`AssemblySearchPaths` 追加 `$(DalamudLibPath)`（`:56`）。
- 8 个 `Use_Dalamud_*` 开关默认全 true（`:61-69`）：`Packager`、`FFXIVClientStructs`、`Newtonsoft_Json`、`Lumina`、`Lumina_Excel`、`Serilog`、`ImGui`、`MSObjectPool`。
- NuGet 只引两个包：`DalamudPackager 15.0.0`（受开关控制）+ `DotNet.ReproducibleBuilds 1.2.39`（`PrivateAssets=All`）（`:73-76`）。**包源就是 nuget.org，没有额外源。**
- 程序集引用（全部 `Private="false"`，`:79-94`）：`Dalamud`、`Dalamud.Bindings.ImGui / ImPlot / ImGuizmo`、`FFXIVClientStructs`、`InteropGenerator.Runtime`、`Newtonsoft.Json`、`Lumina`、`Lumina.Excel`、`Serilog`、`Microsoft.Extensions.ObjectPool`。**没有老 SDK 里的 `ImGui.NET` / `ImGuiScene` / `PInvoke.User32` / `PInvoke.Windows.Core`。**
- 版本号：`Sdk/SdkPackageVersions.props:5-6` 两个包都是 `15.0.0`，与官方同名文件逐字节相同。

**包元数据**（`Dalamud.CN.NET.Sdk/Dalamud.CN.NET.Sdk/Dalamud.CN.NET.Sdk.csproj`）：`Microsoft.Build.NoTargets/2.0.1`（`:1`）、`netstandard2.0`（`:5`）、`PackageId Dalamud.CN.NET.Sdk`（`:11`）、`Version $(PackageVersion_Dalamud_NET_Sdk)`（`:12`）、`PackageType MSBuildSdk`（`:16`）、`PackageLicenseExpression MIT`（`:18`）、`GeneratePackageOnBuild true`（`:19`）、`SuppressDependenciesWhenPacking true`（`:22`）、`IncludeBuildOutput false`（`:23`）；只把 3 个 Sdk 文件打进包（`:27-32`）。`LICENSE.txt:1-2` = `Copyright (c) 2024-present XIVLauncher and Dalamud contributors` + Godot 的 MIT 版权行。README 另有一条口径：版本号首位 = API 版本（11 = API11/.NET8，12 = API12/.NET9）。

**结论**：国服 SDK 与官方 SDK 的差别**只有「默认到哪个目录找 Dalamud 的 DLL」**（外加日志前缀）。真正的国服 API 差异来自 `%APPDATA%\XIVLauncherCN\addon\Hooks\dev\` 下那批 DLL（CN 版 Dalamud / FFXIVClientStructs），不是 SDK 本身。我们自己的 `src/Directory.Build.props` 已经自动探测 `DALAMUD_HOME`，**换 CN SDK 拿不到任何额外收益**；只有「想省掉 DALAMUD_HOME 探测、直接默认 CN 路径」时才值得换，代价是多一个包源依赖 + 跟上游同步（CN 包的 `Sdk.props` 时间戳 2025-12-17，官方 2026-04-30，仓库最近提交是 merge upstream，属于定期跟随后上游的 fork）。

### 5. 值得抄的通用工具（8 个）

1. **配置迁移**：基类配置带 `[JsonIgnore] virtual string? PreviousModuleName`，`LoadConfig` 发现旧文件名存在就自动读旧文件 + 回写新文件（`DailyRoutines.Common/Module/Abstractions/ModuleConfig.cs:7-8`、`ModuleBase.cs:276-293`）。改模块名字不丢用户配置，成本极低。
2. **去抖 + 原子落盘**：`SecureSaveHelper.WriteAllText` 每文件一条 `Channel<string>`，`Task.Delay(500)` 后只取最后一份内容写盘；写盘走「临时文件 + `File.Replace`/`File.Move`」，取消时也把最后一份刷出去（`OmenTools/OmenService/Implementations/Helpers/SecureSaveHelper.cs:10`、`:60-85`、`:87-97`）。我们现在的 `File.WriteAllText` 在游戏崩溃/断电时会留半个 JSON。
3. **4 态生命周期 + CTS 释放纪律**：`ManagerBase`（`DailyRoutines.Common/Manager/Abstractions/ManagerBase.cs:43-125`、`:164-203`、`:220-246`、`:271-280`、`:322-325`）。三件事值得照搬：状态用 `Interlocked.CompareExchange` 抢、后台任务登记进 `ConcurrentDictionary<long, Task>` 并在卸载时 drain、CTS 只在「已请求取消 + 任务全部结束 + 未 Dispose」三条件满足时 Dispose。
4. **编译缓存**：`ModuleCompiler` 按源码 SHA256 缓存编译产物字节、按哈希缓存 `Lazy<Assembly>`（`DailyRoutines.Common/Module/Compilers/ModuleCompiler.cs:106-153`、`:209-238`），Release 优化 + `allowUnsafe` + 可卸载 ALC（`:19-26`、`:312-357`）。
5. **可卸载 ALC 的缓存清理**：`ModuleSerializationCache`（`Module/Compilers/ModuleSerializationCache.cs:21-128`）反射清 Json.NET / `TypeDescriptor` 静态缓存；OmenTools 里还有配套的 `CollectibleContractResolver` —— 用 `ConditionalWeakTable<Type, JsonContract>` 存 `IsCollectible` 类型的契约，避免 `DefaultContractResolver` 自己钉住可卸载类型（`OmenTools/Info/Json/CollectibleContractResolver.cs:10-18`）。**做「运行时加载外部脚本/插件」时这是必修课。**
6. **任务队列 `TaskHelper`**：单个 `Channel<ITaskHelperMessage>` 驱动（`OmenTools/Threading/TaskHelper/TaskHelper.cs:12`、`:170`、`:187`、`:252`），`Abort()` 只是往通道里写一条 `AbortMessage`（`:522`），重载 `Enqueue` 支持超时/重试/权重（`OmenTools/Threading/TaskHelper/TaskHelper.Enqueue.cs:15/46/77/122`），`IsBusy`（`TaskHelper.cs:96`）。DailyRoutines 里 1064 处引用 —— 这就是它「等 UI 就绪再点」的统一手段。
7. **节流**：`Throttler` / `Throttler<T>.Throttle(name, milliseconds = 500, reThrottle = false)` / `Check(name)`（`OmenTools/Threading/Throttler.cs:17/34/44/75`）。热路径（每帧、每个事件）必用。
8. **模糊搜索**：`ModuleSearcher` 用 `FuzzyMatcher<ModuleBase>`，标题/类名/元信息三段权重分开（`DailyRoutines.Common/Module/ModuleSearcher.cs:8-10`、`:35-51`）。做「模块/命令/物品模糊搜索」可以照抄权重思路。
9.（附加，小到不能再小但很实用）**文本自适配字号**：C# 14 `extension(TextNode)` 里 `while (FontSize > 1 && GetTextDrawSize(String).X > Size.X) FontSize--`（`DailyRoutines.Common/Extensions/TextNodeExtension.cs:7-13`）；**手柄/键盘冲突键**：`ConflictKey` 用 `GetValidVirtualKeys().Contains(field) ? value : VirtualKey.SHIFT` 兜住非法键位，`IsPressed()` 同时看键盘与手柄（`DailyRoutines.Common/Info/ConflictKey.cs:8-22`）。

### 6. 风险与坑

- **许可**：`DailyRoutines.Common/LICENSE` 与 `DailyRoutines.ModulesPublic/LICENSE` 都是 **AGPL-3.0**；`KamiToolKit/LICENSE` 是 **MIT (c) 2024 MidoriKami**；`Dalamud.CN.NET.Sdk/LICENSE.txt` 是 MIT。结论：**KTK 与 CN SDK 的代码可以抄/可以引用；Common 与 ModulesPublic 的代码不能抄进我们的仓库**（连「改写一遍」在 AGPL 下也危险）。
- **核心闭源**：`Plugin`、`ModuleManager`、`Lang`（LanguageManager）、`Config.Load/Save` 扩展都在 11MB 的 `DailyRoutines.dll` 里，没有源码也没有 pdb。任何「它到底按什么顺序初始化」的问题只能实测，不能读。
- **强绑国服**：`DailyRoutines.Common.csproj:1`、`ModulesPublic.csproj` 都用 `Dalamud.CN.NET.Sdk/15.0.0`，`ModulesPublic` 里 `GameState.IsCN` 出现在 10 个文件、`IsTC` 4 个、`CNOnly = true` 7 个模块；`ModulePermission.IsSkip()` 在 `#if DEBUG` 下直接返回 false（`DailyRoutines.Common/Module/Models/ModulePermission.cs:85-96`）。移植时这些门控会整块消失。
- **模块模板过时**：`DailyRoutines.ModuleTemplate` 停在 API 13（2025-09-27），模板代码用的 `DailyModuleBase` / `ModuleCategories` / `DService` 现在都不存在，照它写编译不过。
- **超重初始化**：核心 dll 11MB + 私有模块 1.7MB + 公开模块 2.5MB，还带 `Microsoft.CodeAnalysis.dll` 3.1MB + `.CSharp.dll` 7.1MB（常驻，只为实现「游戏内写脚本」）、NAudio、ImageSharp、AngleSharp、Markdig 等。装它是真有代价的，我们的小插件不要学这种「全家桶」。
- **运行时编译的连带成本**：Roslyn 编译 + 可卸载 ALC + 反射清缓存（`ModuleSerializationCache`）三件套是作者自己踩过泄漏才补上的；只抄 `AssemblyLoadContext(isCollectible: true)` 而不清 Json.NET / `TypeDescriptor` 缓存，等于把泄漏抄进来。
- **本地化键在闭源资产里**：模块里 2574 处 `Lang.Get("XxxTitle")`，键的实际值来自插件目录 `Dev/Assets/Langs/*.json`（7 种语言，键如 `AutoGatherDiademDescription`）。**推测**：往 `ModulesPublic` 加新模块时若没在闭源插件的 Langs 资产里登记键，界面会直接显示键名。也就是说这个仓库不是自洽的，脱离闭源宿主无法单独构建成可用插件。
- **`ModuleInfo` 静态构造会发网络请求**：首次访问时 `Task.Run` 拉 `https://gh.atmoomen.top/raw.githubusercontent.com/.../AuthorSupportLinks.json`（`DailyRoutines.Common/Module/Models/ModuleInfo.cs:33-57`），失败静默；头像 URL 也走同一个 GitHub 镜像前缀（`:71`）。离线/镜像挂掉时行为未验证。
- **有防篡改机制**：`Dev/DailyRoutines.ReleaseIntegrity` 列了 4 个 dll 的 SHA256（推测：加载前校验，改 DLL 会被拒）。不要指望「改一下他的 dll」这种玩法。
- **KamiToolKit 的已知禁区**：`NamePlate` 不支持挂节点，必须改用 `OverlayController`（`KamiToolKit/BaseTypes/NodeBase/NodeBase.Linking.cs:361-362`，这是代码里直接 warn 的）。
- **依赖越界示例**：`ModulesPublic` 引了 `Iced`（x86 反汇编器），只被 `Interface/ColorThemeHotReload.cs:12/20` 用来解码指令。这种「为了一个功能引入一个反汇编器」的做法不要学。

## ④ 可以立刻用在下一个插件里的三件事

1. **配置「改名不丢配置」+ 原子落盘**：配置类加 `[JsonIgnore] public override string? PreviousModuleName => "旧名字";`，加载时若新文件不存在且旧文件存在就迁移（照 `DailyRoutines.Common/Module/Abstractions/ModuleBase.cs:276-293` 的流程写十几行）；保存改成「去抖 500ms + 临时文件 + `File.Replace`」（照 `OmenTools/.../SecureSaveHelper.cs:60-97`）。我们的 `TextToTalkCN` 之类改配置结构时天天遇得到。
2. **把「卸载」当成状态机而不是一个方法**：`Created → Running → Stopping → Stopped`，Stop 时先取消 CTS、再等后台任务退出（drain）、最后在框架线程做真正的清理，并且只在「已取消 + 任务清空 + 未 Dispose」时 Dispose CTS（照 `DailyRoutines.Common/Manager/Abstractions/ManagerBase.cs:61-125`、`:220-246`）。这直接解决我们踩过的「后台线程静默死掉 / 卸载后还在跑」。
3. **改原生 addon 时抄 KTK 的挂链/摘链纪律**（不用抄代码，抄顺序）：`PostDraw` 懒创建 → `AttachNode` 后必须让父级 `UldManager.UpdateDrawNodeList()` + `UpdateCollisionNodeList(false)`；`PreFinalize` 立刻把引用置 null；卸载时**先确认 addon 还在 `AllLoadedUnitsList` 里**再动 UldManager，且游戏退出中（`IsFrameworkUnloading`）直接跳过手动 Dispose（照 `KamiToolKit/BaseTypes/NodeBase/NodeBase.Linking.cs:288-320`、`NodeBase.Dispose.cs:63-95`）。或者更省事：KamiToolKit 是 MIT，直接引用它就白拿这套保护。

## ⑤ 结论可信度

**源码实证（读到的文件与行号如上）**：
- 模块系统全文（`ModuleBase.cs` 454 行、`ModuleInfo.cs`、`ModuleConfig.cs`、`ModuleCategory.cs`、`ModulePermission.cs`、`ModuleSearcher.cs`）；
- 管理器状态机（`ManagerBase.cs` 328 行）；
- 运行时编译与 ALC 清理（`ModuleCompiler.cs` 535 行、`ModuleLoadContext.cs`、`ModuleSerializationCache.cs` 183 行）；
- 宿主契约（`IManagerHost.cs`、`ManagerHost.cs`）、悬浮窗（`Overlay.cs`、`OverlayConfig.cs`）；
- 模块范例 4 个（`AutoSkipBuddyFeedScene`、`DisableGroundActionAutoFace`、`AutoPreserveCollectable`、`AutoDisableBattleBGM`）与 UI 范例 6 个（`FastBLUSpellbookSearchBar`、`AdventurerPlateThroughInspect`、`AutoDisplayMSQProgress`、`AutoNumericInputMax`、`AutoDisplayIDInformation`、`AutoSharpenInterfaceText`）；
- KamiToolKit 挂链/摘链/Dispose（`NodeBase.Linking.cs`、`NodeBase.Dispose.cs`）；
- SDK 差异用「两个 15.0.0 包的 `diff -u`」得出（比读仓库更硬）；
- EXDViewer MCP（`viewer/src/mcp/handler.rs`、`mod.rs`）；
- 版本与依赖（`Dev/DailyRoutines.deps.json`）、安装目录文件清单。

**推测（未验证，用前自查）**：
- 宿主用 `ModuleCompiler.GetDerivedTypes<T>` 扫程序集来发现模块 —— 接口在 Common 里，但调用方在闭源 dll；
- `DailyRoutines.ReleaseIntegrity` 是启动时校验 DLL 的完整性；
- 新增模块的 `Lang.Get` 键必须在闭源插件的 `Assets/Langs/*.json` 里登记，否则显示键名；
- 平台相关度：`DailyRoutines.Plugin` 内部初始化顺序（DService → ManagerHost → Manager → Module）。

**未确认 / 读不到**：
- 核心插件源码（`DailyRoutines.Plugin`、`ModuleManager`、`LanguageManager`、`DailyRoutines.Extensions` 里的 `Config.Load/Save` 扩展）—— 闭源，只有元数据；
- `ModuleTemplate` 是否有「更新版」藏在别处（仓库里那份停在 API 13）；
- EXDViewer 只读了 MCP 接口层，Rust 侧数据管线（`excel/`、`assets/`）没深入；
- 官方 `Dalamud.NET.Sdk` 的**仓库源码**没查，用的是本机 NuGet 缓存里的 15.0.0 包（对我们是最终事实，但「官方仓库当前 HEAD 是否还有别的改动」未确认）。
