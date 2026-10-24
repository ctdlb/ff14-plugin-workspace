# Luna 学习笔记

## 一句话定位

Ottermandias（Glamourer / Penumbra / Mare 作者）写的「插件底层设施库」：自建 ImGui 绑定（ImSharp）、DI 化的服务系统、带备份的配置文件、文件浏览器、自定义 DirectX 绘制。**不是**给「快速做一个功能」用的，是给「长期维护的大型插件」用的地基。

| 项 | 值 |
| --- | --- |
| 仓库 | https://github.com/Ottermandias/Luna |
| LICENSE 文件 | 根目录 `LICENSE` |
| 实际许可 | **GNU Affero GPL v3（AGPL-3.0）**，`LICENSE:1-4` 起即为 AGPL 全文 |
| 版权人 | **未填写**——`LICENSE:633` 仍是模板占位 `Copyright (C) <year>  <name of author>`，全文只有 FSF 自己的版权行（`LICENSE:4`）。权利人只能从 git 历史推（**推测**为 Ottermandias） |
| 规模 | **368 个 `.cs`，44,585 行**；其中 Luna 本体 308 文件 / 37,418 行，`Luna.Generators` 31 / 4,993，`Luna.Tests` 29 / 2,174 |
| 最近提交 | **2026-10-20 16:38:31 +0200**（`8761f09`，"Improve active filter display."） |
| 分发 | 无 NuGet 打包配置（`Luna.csproj` 里没有 `PackageId`），`README.md` 只有一行介绍、无安装说明。**推测**只能源码引入 |

## 目录地图

一个解决方案三个工程：`Luna/`（库本体）、`Luna.Generators/`（31 个源生成器）、`Luna.Tests/`（29 个测试 + `.verified/` 快照）；外加空子模块 `ImSharp/`。

`Luna/` 下一级目录按代码量排：

- `Filesystem/` **5,811 行**：`IFileSystemNode`/`IFileSystemFolder` 抽象 + `BaseFileSystem` 实现 + `Ui/` 现成的文件树界面（可搜索、多选、拖放、着色）
- `DirectX/` **5,336 行**：`CustomRenders/`、`ImageProcessing/`、`Helpers/`，`Resources/` 里是 `.hlsl` 与预编译 `.dxbc` 着色器（混合、颜色变换）
- `Files/` **2,617 行**：`ConfigurationFile<TProvider>`、`SaveService`、`BaseBackupService`/`BackupFile`、`JsonRecoveryStream`（损坏配置的抢救）
- `Services/` **2,456 行**：`IService` 体系、`ServiceManager`（DI 容器）、`HookManager`、`FastHook`、`ImSharpDalamudContext`、`FrameworkManager`
- `Json/` **2,367 行**：`Utf8JsonObjectReader/Writer`、`JsonObjectConversion`、`TemporaryJsonObject`
- `Widgets/` **2,128 行**：`HeaderLine`、`SetButtons`、`Tutorial`、`InputPopup`、`KeySelectors`、`TagButtons`、`Changelog`
- `Layout/` **2,088 行**：`Window`/`OverlayWindow`/`WindowSystem` 包装、`BaseTab`/`BasePanel`/`BaseButton`、`Editors/`、`TwoPanelLayout`
- `Conditions/` **1,611 行**：JSON 可序列化的 `ICondition` 组合（And/Or/Not/True/False），配 `schemas/*.json`
- `Containers/` 1,512、`Ipc/` 1,501、`Colors/` 1,447、`Utility/` 1,371、`Extensions/` 1,254、`Logging/` 915
- 其余：`Compression/`、`Diagnostics/`、`Events/`、`GameInterop/`（只有 2 个文件：`SafeTextureHandle`、`SafeResourceHandle`）、`Keyboard/`、`Messaging/`、`PluginLoader/`、`Spans/`、`Tasks/`、`Text/`，根下 `LunaStyle.cs` 等

## 核心 API

1. `Luna/Services/IService.cs:5` —— 一切服务的空标记接口，由 `ServiceManager` 扫出来注册：
   ```csharp
   public interface IService;
   ```
   同文件还有 `IRequiredService`、`IAsyncService`、`IHookService`、`IDataContainer`、`IUiService` 等 10 个派生标记。

2. `Luna/Services/ServiceManager.cs:96` —— 手动注册单例；另有 `AddIServices(Assembly)`（`:129`）按接口自动扫：
   ```csharp
   public ServiceManager AddSingleton<T>()
   ```

3. `Luna/Services/HookManager.cs:84` —— 统一管理 hook 的创建/替换/销毁，带异常统计：
   ```csharp
   public Task<Hook<T>?> CreateHook<T>(string name, string signature, T detour, bool enable = false) where T : Delegate
   ```

4. `Luna/Files/ConfigurationFile.cs:11` —— 自动保存（防抖）+ 备份 + 损坏恢复的配置基类：
   ```csharp
   public abstract class ConfigurationFile<TProvider>(BaseSaveService<TProvider> saveService, MessageService messager, TimeSpan? saveDelay = null)
   ```

5. `Luna/Filesystem/BaseFileSystem.cs:30` —— 一棵完整的虚拟文件树模型（Node/Folder/Data/Separator）：
   ```csharp
   public BaseFileSystem(string name, LunaLogger log, bool allowsMultiSelection, IComparer<ReadOnlySpan<char>>? comparer = null)
   ```

6. `Luna/Tasks/SingleTaskQueue.cs:13` —— 保证同一时刻只有一个任务在跑，其余排队：
   ```csharp
   public Task Enqueue(IAction action, CancellationToken token = default)
   ```

7. `Luna/Keyboard/KeyboardManager.cs:25` —— 在 `IFramework` 上轮询热键，不必自己写每帧判断：
   ```csharp
   public ModifiableHotkey RegisterKey(ModifiableHotkey key)
   ```

8. `Luna/Messaging/MessageService.cs:69` —— 一条消息同时进日志 / 通知 / 聊天 / 历史记录：
   ```csharp
   public DateTime AddMessage(IMessage message, bool doStore = true, bool doNotify = true, bool doLog = true, bool doChat = false)
   ```

9. `Luna/GameInterop/SafeTextureHandle.cs:70` —— 包一层 `SafeHandle` 的原生贴图，自动增删引用：
   ```csharp
   public SafeTextureHandle(Texture* handle, bool incRef = true, bool ownsHandle = true)
   ```

10. `Luna/Layout/Window.cs:24` —— 把 Dalamud `Window` 的 ImGui 类型全换成自己的枚举，避免调用方碰 ImGui：
    ```csharp
    protected Window(string name, WindowFlags flags = WindowFlags.None, bool forceMainWindow = false)
    ```

11. `Luna/Text/UserRegex.cs:26` —— 「用户输入 + 编译好的正则」二合一，默认 `NonBacktracking`：
    ```csharp
    public UserRegex(string text, RegexOptions options = DefaultOptions)
    ```

## 它解决什么问题

- **ImGui 绑定层的替换（最核心，也是最大的门槛）**：`Luna/GlobalUsings.cs:21` 一句 `global using ImSharp;`，308 个文件里 90 个直接用 `Im.*`。整个 UI 层建立在 **ImSharp**（自建绑定）之上，而不是 `Dalamud.Bindings.ImGui`。所谓「Luna 真好用」，用起来意味着换一套 ImGui 写法。
- **配置与存档（`Files/`，2,617 行）**：防抖保存、原子写、自动备份成 `.bak`、JSON 损坏时走 `JsonRecoveryStream` 抢救。这是它最实在的一块。
- **文件浏览器（`Filesystem/`，5,811 行）**：虚拟文件树 + 现成 UI（搜索/多选/拖放/排序/着色/分割线）。Glamourer、Penumbra 那类「管理一堆文件」的插件需要它；我们不需要。
- **自定义 DirectX 绘制（`DirectX/`，5,336 行）**：往 ImGui 里插自己的着色器绘制指令，做图像混合/颜色变换。
- **DI 化的服务系统**：`Microsoft.Extensions.DependencyInjection` + `IService` 标记，服务之间靠构造函数注入，`IRequiredService` 保证必须初始化的服务一定被建。
- **杂项设施**：类型化 IPC（`Ipc/`，1,501 行，`FuncSubscriber`/`ActionSubscriber` 泛型包装）、`HookManager`、热键、消息、`UserRegex`、`Luna.Generators`（给 `[NamedEnum]`、`[StrongType]`、IPC 自动生成样板代码）。

## 对我们的用处

目标：往游戏原生 `ItemDetail` 窗口插自己的文本节点并撑高窗口。

**结论：一点用都没有。**

- **全仓零 Atk / 原生 UI 代码**。在 `Luna/` 下 `grep -rn "Atk\|RaptureAtk" --include=*.cs`（排除 `AtkValue` 之后）**零命中**；`GameInterop/` 只有 `SafeTextureHandle` 与 `SafeResourceHandle` 两个文件，管的是贴图/资源引用计数，跟节点无关。没有 `AtkUnitBase`、没有 `AtkResNode`、没有 addon 封装。
- **它是 ImGui 侧的工具库**，全部 UI 能力都落在自绘窗口上，对「改游戏原生窗口」这个方向没有任何抽象。
- 它对 **Atk 之外** 的 Indirection 是：如果要搞 ImGui 浮层（比如在 `ItemDetail` 旁边贴一块自绘文字作为兜底），理论上能用，但为了这块要背上 AGPL + 整套 DI + ImSharp 换绑定，代价远超收益。
- **反向价值**：读它可以学「怎么组织一个长期维护的大型插件」（服务分层、配置备份、热键轮询、hook 集中管理），但这些是架构参考，不是可复用的代码。

## 坑 / 限制

- **许可证是 AGPL-3.0——这是硬红线**：抄任何一段代码进我们的插件，整个插件就得按 AGPL 开源（含源码向使用者提供）。我们是要发到插件库的公开插件，**不能抄**。与之对比 ECommons 是 MIT。
- **许可证文件本身是裸模板**：`LICENSE` 全文是 AGPL-3.0 原文，`LICENSE:633` 的版权人占位符都没填。合规上「它是 AGPL」这件事没有疑问（全文就是 AGPL），但**权利人身份需要从 git 历史确认**（`git log` 首个作者是 Ottermandias，**推测**）。
- **子模块是空的，这个 clone 跑不起来**：`ImSharp/` 目录 0 个文件，`.gitmodules:1-4` 指向 `git@github.com:Ottermandias/ImSharp.git`（**SSH 地址**，无 key 拉不下来），分支 `gc1.88`。而 `Luna.csproj:35` 直接 `<Compile Include="..\ImSharp\ImSharp\**\*.cs" />` **把 ImSharp 当源码编进来**——不是 dll 引用，是整个源码树。所以**本机无法编译 Luna，也无法读 ImSharp 内部实现**（本笔记里所有 ImSharp 相关结论都只能是「Luna 怎么用它」，**未确认**它内部实现）。
- **ImGui 类型冲突**：`Luna.csproj:58-59` 显式 `<Reference Remove="Dalamud.Bindings.ImGuizmo" />`、`ImPlot`，说明它有意排除 Dalamud 的 ImGui 相关绑定。`Layout/Window.cs:15-17` 那儿专门写了一个「Click-redirection due to incompatible imgui types」的 `TitleBarButton` 来桥接两套类型。**混用 Luna 与 Dalamud.Bindings.ImGui 会有真实的类型不兼容成本。**
- **强制 DI 架构**：`ServiceManager`（`Services/ServiceManager.cs`）要求服务都走 `IService` 标记 + 构造函数注入，`MainLogger`、`LunaLogger`、`BaseSaveService` 都是构造参数。我们那点体量的插件套这套是纯负担。
- **依赖**：`Dalamud.NET.Sdk/15.0.0`（`Luna.csproj:1`，跟我们一致，这点没问题）、`JetBrains.Annotations 2024.2`、`Microsoft.Extensions.Logging 9.0`、`System.IO.Hashing 9.0.8`、`TerraFX.Interop.Windows`（`HintPath` 到 DalamudLibPath）、`Serilog.Sinks.File`。
- `DefineConstants` 里 `<DefineConstants>PROFILING</DefineConstants>` 然后 `<DefineConstants>HAS_NEWTONSOFT</DefineConstants>`（`Luna.csproj:22-23`）——**第二行覆盖第一行而不是追加**，实际 `PROFILING` 不生效。看起来是配置 bug（**推测**，未验证）。

## 还没读透的部分

- `ImSharp/` 是空的，**整个 ImGui 绑定层都没读到**——`Im.*` 的能力边界、与 Dalamud ImGui 的互操作细节全部未确认。
- `DirectX/`（5,336 行）只看了目录结构和 `.hlsl` 文件名，自定义绘制指令怎么挂进 ImGui 完全没读。
- `Filesystem/Ui/` 的实际绘制逻辑（怎么把 5,811 行的模型渲染成文件树）未读。
- `Ipc/` 的 1,501 行：`FuncSubscriber`/`FuncProvider`/`EventProvider` 只看了签名，`CallerPlugin` 与生命周期回收机制未读。
- `Luna.Generators/` 31 个生成器只看了文件名（`NamedEnum`、`StrongType`、`Ipc`、`AssociatedEnum`、`TooltipEnum`），没读实现。
- `PluginLoader/`（`IIntermediaryPlugin`、`IPluginDefinition`、`PluginLoadSource`）看起来是给「插件之间互相加载」用的，用途与风险都未确认。
- `Compression/`（`FileCompactor`、`CompressionFunctions`）与 `Luna.Tests` 的测试覆盖范围未看。
