# CkCommons 学习笔记

> 调研对象：`E:\DeepSeek Harness\.tmp\study\CkCommons`（浅克隆 `--depth 1`，只有 1 条提交历史）。
> 只读调研：没编译、没改源码。推断写「推测」，没读到的写「未确认」。

## 1. 一句话定位

**给 Dalamud 插件作者用的 ImGui 工具箱**：把 ImGui 包一层更好看、更少样板代码的封装（`CkGui`），配 RAII 作用域（`CkRaii`）、统一配色/尺寸（`CkStyle`）、富文本（`RichText`）、可复用控件（`Widgets`）和一套配置保存器（`HybridSaver`）。

- 仓库：<https://github.com/CordeliaMist/CkCommons>
- LICENSE：`LICENSE`（根目录），**MIT**，`Copyright (c) 2025 Cordelia`
- 规模：**145 个 `.cs` / 19,464 行**
- 最近提交：**2026-10-23** `c01d915` `Merge pull request #6 from AzureRavie/bug/chat-string-crash`
- 工程：`Dalamud.NET.Sdk/15.0.0`（`Use_DalamudPackager=false`）；`ProjectReference ..\OtterGui\OtterGui.csproj`；NuGet `SixLabors.ImageSharp 3.1.11`、`NAudio 2.2.1`

## 2. 核心 API / 目录地图

| 目录 | 文件 / 行数 | 干什么 |
| --- | --- | --- |
| `CkGui/` | 16 / 3,350 | ImGui 封装主体（`CkGui`、`CkGuiEx`、`CkGuiUtils`、`CkGuiClip`） |
| `CkRaii/` | 10 / 1,301 | OtterGui `ImRaii` 的加强版：Child/Group/TabBar/Colors/Style |
| `CkStyle/` | 1 / 65 | 集中配色与尺寸常量 |
| `RichText/` | 19 / 1,837 | 仿 SeString 的富文本渲染（颜色/发光/图标/表情） |
| `DynamicDrawSystem/` | 24 / 3,356 | 动态绘制系统（未细读） |
| `Widgets/` | 9 / 1,806 | `CkHeader`、`FancySearchBar`、`FancyTabBar`、`ItemSelectorBox`、`TagCollection`、`DatePicker` |
| `CkFileSystem/` | 16 / 2,568 | 文件/路径工具（未细读） |
| `Helpers/` | 10 / 1,178 | 杂项，含唯一的原生 addon 工具 `AddonHelp.cs` |
| `DalamudServices/` | 5 / 502 | `Svc`：一堆 `[PluginService] static` |
| `Colors/` | 4 / 693 | 颜色常量与转换 |
| `HybridSaver/` | 5 / 337 | 配置保存框架（JSON / StreamWriter 双模式 + 备份） |
| `Audio/`、`RichChatLog/`、`Textures/`、`CkCustom/`、`Compression/`、`MufflerCore/` | 5/535、3/411、3/210、1/207、1/59、2/130 | 音频通道、聊天日志、贴图缓存等 |
| 根 | `CkCommonsHost.cs`(73)、`Globals.cs`(16) | 唯一入口 + global using |

关键签名：

```csharp
// CkCommonsHost.cs:40
public static void Init(IDalamudPluginInterface pluginInterface, IDalamudPlugin instance,
                        CkLogFilter logFilter = CkLogFilter.All)
// CkCommonsHost.cs:64
public static void Dispose()          // 要调它才释放 AudioSystem / NewRichText / TextureManager

// CkGui/CkGui.cs:12
public static partial class CkGui
//   :18 public static void CenterNextWindow(float width, float height, ImGuiCond cond = ImGuiCond.None)
//   :26 public static uint Color(byte r, byte g, byte b, byte a)
//   :42 public static uint ApplyAlpha(uint rgba, float alpha)

// CkRaii/Child.cs:4   public static partial class CkRaii
// RichText/NewRichText.cs:13   public static partial class NewRichText
// HybridSaver/HybridSaveService.cs:9
public class HybridSaveServiceBase<T> where T : IConfigFileProvider   // :23 Init / :72 Save / :93 Load
// DalamudServices/Svc.cs:14   public class Svc   // :18 IAddonLifecycle AddonLifecycle …

// Helpers/AddonHelp.cs:9   public static bool IsAddonReady(AtkUnitBase* addon)
// Helpers/AddonHelp.cs:13  public static bool IsReady(this AtkUnitBase addon)
// Helpers/AddonHelp.cs:23  public static AtkUnitBase* Base(this AddonArgs args)
// Helpers/AddonHelp.cs:29  public static bool TryGetAddonByName<T>(string addon, out T* addonPtr) where T : unmanaged
```

## 3. 它解决什么问题

Dalamud 插件的 ImGui 代码重复度极高：每个窗口都要重写「Child/Group 的 Begin-End 配对」「配色」「滚动区」「TabBar」「搜索框」。CkCommons 把这些抽成可复用的静态方法与 `using` 作用域，再加一套统一视觉风格和富文本能力，目标是**少写样板、样式一致**。它服务于**插件自己的 ImGui 窗口**，与游戏原生界面无关。

## 4. 对我们的用处

**对「往 `ItemDetail` 插节点 + 撑高窗口」几乎零帮助。** 实测：

- 全库 `AtkUnitBase` 只有 4 处命中，全在 `Helpers/AddonHelp.cs:9/13/23/24`，都是「判就绪 / 从 `AddonArgs` 取指针」的小工具；
- 全库 `ItemDetail` **0 命中**；
- 没有任何建节点、挂链、`UldManager.UpdateDrawNodeList()`、`SetHeight` 之类的代码。

可能有点用的只有两小处（都不急）：

- `Helpers/AddonHelp.cs:9-10`：`addon->IsVisible && addon->UldManager.LoadedState == AtkLoadState.Loaded && addon->IsFullyLoaded()`。比常见的 `IsAddonAndNodesReady()` 多判了一个 `UldManager.LoadedState`。**推测**：插节点前用它做门槛，能少一类「节点还没准备好」的崩，值得在我们的判就绪处试。这是百来字节的判据，照抄即可，不用引库。
- 若哪天真要给我们自己的插件写设置窗口，`CkGui` / `CkRaii` / `Widgets` 能省很多 ImGui 样板；但那和「道具简介框」无关。

**不引入的理由**：为了一个判定函数拖进 19k 行 + `OtterGui` 工程引用 + ImageSharp + NAudio，收益是负的；且它的静态服务注入会和我们现有的 OmenTools 静态实例体系叠一层（推测：能共存，但两套 `[PluginService]` 各注一遍没必要）。

## 5. 坑 / 限制

- **README 与代码对不上**：README 教你 `CkCommonsMain.Init(pluginInterface, this)` / `CkCommonsMain.DisposeAll()`，实际类型叫 `CkCommonsHost`，方法是 `Init` / `Dispose`（`CkCommonsHost.cs:31/40/64`）。照 README 抄会编不过。
- **`OtterGui` 是工程引用**（`CkCommons.csproj` 里 `..\OtterGui\OtterGui.csproj`），必须作为同级子模块存在，不能只引 dll。这正好撞上我们那条「两套 SDK 混用报上千个找不到 `Action`/`Func`、不能用 `ProjectReference`」的坑。
- `Dalamud.NET.Sdk/15.0.0`（非 CN 版）。我们全线是 `Dalamud.CN.NET.Sdk/15.0.0`，**推测**要改 sdk 才能编。
- 静态服务注入（`Svc` 全是 `[PluginService] static`）→ **一个进程只能有一份**，多插件同时引用会互相覆盖。
- `Init` 里顺手改了全局日志级别：`Svc.Log.MinimumLogLevel = LogEventLevel.Debug`（`CkCommonsHost.cs:46`），会污染宿主插件的日志。
- 必须成对调 `Init` / `Dispose`，否则 `AudioSystem`、`NewRichText`、`TextureManager` 泄漏（`CkCommonsHost.cs:64-72`）。
- MIT，可抄代码（保留版权声明）。

## 6. 还没读透的部分

- `DynamicDrawSystem/`（24 文件 / 3,356 行）只看了目录名，**完全没读**——它是全库第二大的子系统，不知道解决什么。
- `CkFileSystem/`（16 / 2,568）没读。
- `RichText` 的渲染管线（`NewRichString` / `NewRichText.Manager` / `EmojiLoader`）只看了类声明。
- `Widgets/ItemSelectorBox.cs`（`ItemSelectorBoxBuilder<T>`）与游戏物品数据怎么接的，未确认。
- `CkCommonsHost.CheckForObfuscation`（`CkCommonsHost.cs:54-58`）实现读了，触发条件与实际用途**未确认**。
- `Globals.cs` 里把 `ImGui*Flags` 全部起了别名（`CFlags`/`WFlags`/…），是否有命名冲突隐患未验证。
