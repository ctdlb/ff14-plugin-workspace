# OtterGui 学习笔记（源码精读）

> 调研对象：`E:\DeepSeek Harness\.tmp\study\OtterGui`（`--depth 1`，HEAD `79771ee`，2026-04-29 "Fix MountType."）。
> 只读调研：未编译、未改动任何文件。推断一律标「推测」，没读到的标「未读」。

## 一句话定位

Ottermandias（Glamourer / Penumbra / Mare 作者）抽出来的 **Dalamud ImGui 控件与工具库**，服务对象是「插件自己的设置窗口」：RAII 包装、分栏表格、UTF-8 文本 API、配置保存/回滚、服务容器。它**完全不碰原生 addon**。

- 仓库：<https://github.com/Ottermandias/OtterGui>
- LICENSE：文件名 `LICENSE`，实际许可是 **Apache License 2.0**（`LICENSE:1-3` 明写 "Apache License / Version 2.0, January 2004"），非 MIT、非 GPL。
- 规模：**236 个 `.cs`，24,073 行**
- 目标框架：`OtterGui.csproj:1` `<Project Sdk="Dalamud.NET.Sdk/15.0.0">`

| 目录 | 文件 / 行数 | 干什么 |
| --- | --- | --- |
| `Text/` | 124 / 8,862 | UTF-8 版全量 ImGui 控件（`ImUtf8.*`），本项目最重的一块 |
| `Classes/` | 32 / 3,870 | 配置保存、备份、事件、键盘/正则/集合工具 |
| `Widgets/` | 19 / 2,246 | 组合控件（框架分组、筛选下拉、TabBar、Changelog、Tutorial） |
| `Filesystem/` | 17 / 2,931 | 文件选择器（未读） |
| `Raii/` | 7 / 697 | `ImRaii`：Push/Pop 的 `IDisposable` 包装 |
| `Table/` | 7 / 590 | 泛型排序+筛选表格 |
| `Services/` | 6 / 847 | DI 容器、Hook 封装、ImGui 缓存 |
| 根目录 7 个 | 7 / 1,699 | `Functions.cs`、`Util.cs`、`ImGuiClip.cs`、`ItemSelector.cs` 等 |

## 核心 API

1. **RAII 一次性 Push 多个 ID** —— `Raii/Id.cs:9`
   ```csharp
   public static Id PushId(string id, bool enabled = true)
   ```
   返回的 `Id` 在 `Dispose` 时把计数内的 ID 全弹掉：`Raii/Id.cs:63-64` `public void Dispose() => Pop(_count);`。同类还有 `PushId(int)` `:12`、`PushId(nint)` `:15`。

2. **带边框的「分组框」**（设置页最常用）—— `Widgets/ImGuiFramedGroup.cs:10`、`:98`
   ```csharp
   public static float BeginFramedGroup(string label, string description = "", uint headerColor = 0,
       FontAwesomeIcon headerPreSymbol = FontAwesomeIcon.None)
   public static void EndFramedGroup(uint borderColor = 0)
   ```
   `description` 非空时会在标题后画 ⓘ 并挂 tooltip（`:62-69`）。RAII 版本 `Raii/EndObjects.cs:171`：`public static IEndObject FramedGroup(string label, uint borderColor = 0, uint headerColor = 0, ...)`。

3. **泛型表格（列定义 + 筛选 + 排序）** —— `Table/Table.cs:58`、`Table/Table.cs:67`、`Table/Column.cs:29`
   ```csharp
   public Table(string label, IReadOnlyCollection<T> items, params Column<T>[] headers)
   public void Draw(float itemHeight)
   public virtual void DrawColumn(TItem item, int idx)
   ```
   列上覆写 `DrawFilter()`（`Table/Column.cs:16`）与 `Compare`（`Table/Column.cs:26`）即可得到筛选框和排序。

4. **UTF-8 文本（免 string 分配）** —— `Text/ImUtf8.Text.cs:18-19`
   ```csharp
   public static void Text(ReadOnlySpan<byte> text)
       => ImGui.TextUnformatted(text);
   ```
   另有 `Text(ReadOnlySpan<char>)` `:25`、`Text(..., uint color)` `:39`。整个 `Text/` 目录是 ImGui 每个控件的 UTF-8 复刻。

5. **裁剪绘制长列表** —— `ImGuiClip.cs:52`
   ```csharp
   public static void ClippedDraw<T>(IReadOnlyList<T> data, Action<T> draw, float lineHeight)
   ```
   内部用 `ImUtf8.ListClipper`（`:54`），只画可见行；非随机访问版在 `:96`。

6. **配置保存 + 备份回滚** —— `Classes/SaveService.cs:62`、`:9`、`Classes/Backup.cs:34`
   ```csharp
   public void Save(SaveType type, in ISavable<T> group)
   public interface ISavable<in T> { public string ToFilename(T fileNames); public void Save(StreamWriter writer); }
   public static bool TryGetFile<T>(DirectoryInfo dir, string fileName, [NotNullWhen(true)] out T? parsedFile, out string message, Func<string, T?>? parse = null)
   ```
   `SaveType` 有 Queue/Delay/Immediate/ImmediateSync/None（`:25-32`）；`Backup.CreateAutomaticBackup` 在 `Classes/Backup.cs:23`，上限 `MaxNumBackups = 10`（`:8`）。

7. **服务容器** —— `Services/ServiceManager.cs:37`、`:65`
   ```csharp
   public T GetService<T>() where T : class
   public ServiceManager AddSingleton<T>()
   ```
   基于 `Microsoft.Extensions.DependencyInjection`，服务用空接口 `IService` 标记（`Services/IService.cs:6`）。

8. **简单表格 / 竖排 TabBar**（不想接 `Table<T>` 时的轻量选择）—— `ImGuiTable.cs:10`、`Widgets/TabBar.cs:24`
   ```csharp
   public static void DrawTable<T>(string label, IEnumerable<T> data, Action<T> drawRow, ImGuiTableFlags flags = ImGuiTableFlags.None, params string[] columnTitles)
   public static bool Draw(string label, ImGuiTabBarFlags flags = ImGuiTabBarFlags.None, params ITab[] tabs)
   ```

## 它解决什么问题 / 怎么用

解决的是「每个 Dalamud 插件都要重写一遍设置窗口」：把 Push/Pop 收进 `using`、把表格的筛选排序做成可继承的列、把配置文件保存做成带备份和延迟合并的服务。

```csharp
// 示意，未编译
using var id     = ImRaii.PushId("MyPlugin");              // Raii/Id.cs:9
var width = Widget.BeginFramedGroup("价格显示", "悬停时是否显示最低价");  // Widgets/ImGuiFramedGroup.cs:10
ImUtf8.Text("当前阈值：1000"u8, 0xFFFFFF00);                // Text/ImUtf8.Text.cs:39
ImGui.Checkbox("启用", ref config.Enabled);
ImGui.PushItemWidth(width);                                 // BeginFramedGroup 已自动缩过 itemWidth
Widget.EndFramedGroup();                                    // Widgets/ImGuiFramedGroup.cs:98

var table = new Table<ItemEntry>("##items", entries, priceColumn, nameColumn); // Table/Table.cs:58
table.Draw(ImGui.GetTextLineHeightWithSpacing());                              // Table/Table.cs:67

// 保存：走延迟合并，避免每帧写盘（Classes/SaveService.cs:62）
saveService.Save(SaveType.Delay, config);
```

## 对我们的用处

我们在做「往游戏原生 `ItemDetail` addon 里插自己的文本节点并撑高窗口」。

- **对插节点：零帮助。** 全仓 grep `AtkUnitBase` / `FFXIVClientStructs` 命中 **0** 次；`using Dalamud.*` 全是 ImGui、Window、Services 一类（`Dalamud.Bindings.ImGui` 出现 151 次最多）。它连一个原生指针都不碰。
- **对设置窗口：有用。** `ImRaii`、`Widget.BeginFramedGroup`、`Table<T>`、`FilterComboCache`、`SaveService`+`Backup` 正好是设置页要的东西，能省掉几百行样板代码。
- 结论：**不整仓引入**（会拉进 8,800 行 `Text/` 和一个空子模块），按文件抄需要的几处：`Raii/`、`Widgets/ImGuiFramedGroup.cs`、`Table/`、`ImGuiClip.cs`、`Classes/SaveService.cs` + `Classes/Backup.cs`。
- 抄的时候注意 Apache-2.0 §4：保留版权与许可声明、标注修改过的文件。

## 坑 / 限制

- **子模块是空的，原样 clone 编不过**：`.gitmodules:1-4` 指向 `OtterGuiInternal`，目录里 0 个文件；但有 **12 个文件** `using OtterGuiInternal`（如 `Text/Extended/ImUtf8.Spinner.cs:2`、`Text/ImUtf8.RotatedText.cs:3`、`Widgets/ToggleButton.cs`）。要先 `git submodule update --init`。
- **绑定 API 15**：`OtterGui.csproj:1` 用 `Dalamud.NET.Sdk/15.0.0`，与我们工作区一致，可直接对齐。
- **NuGet 依赖**（`OtterGui.csproj:28-30`）：`Microsoft.Extensions.DependencyInjection 9.0.2`、`JetBrains.Annotations 2024.3.0`，另 `<Reference Include="Dalamud.Bindings.ImGui" Private="false" />`。
- 源码里 8 处 `using Newtonsoft.Json`（如 `Classes/Backup.cs:1`）但 csproj **未声明** —— 推测靠 Dalamud 自带的那份，自己建工程时要显式加。
- **没有 README、没有示例工程**，用法只能从源码读；`ItemSelector.cs:456` 的 `ItemDetailsWindow` 是最接近「设置页布局」的现成范例。
- **三套 API 并存**：`ImRaii`（`Raii/`）、`ImUtf8`（`Text/`）、`Widget`（`Widgets/`）。全仓 `[Obsolete]` 命中 0 次，所以不算废弃，但风格是新旧叠加，容易挑错一套（哪个是「最新方向」未确认，推测是 `ImUtf8`）。
- `Widgets/ImGuiFramedGroup.cs:152` 用 `private static readonly Stack<(Vector2, Vector2)> LabelStack` 存标签位置 —— 静态栈，Begin/End 必须严格配对且不能跨帧（推测：嵌套或异常跳出会让边框画错位）。
- `.editorconfig` 有 239,840 字节（约 234 KB），整套拷进来会盖掉本工作区的代码风格配置；只拷 `.cs` 就好。
- git 是 shallow（只有 1 条 commit），看不到演进历史，因此「哪些名字已经过时」只能靠 grep，不能靠 log。

## 还没读透的部分

| 跳过的目录 | 规模 | 原因 |
| --- | --- | --- |
| `Filesystem/` | 17 / 2,931 | 文件选择器/树，与本任务和设置窗口都无关 |
| `Classes/` | 32 / 3,870 | 只读了 `SaveService.cs`、`Backup.cs`；`EventWrapperBase.cs`(17KB)、`MessageService.cs`、`KeyboardManager.cs` 未读 |
| `Text/` | 124 / 8,862 | 只读了 `ImUtf8.Text.cs` 与目录清单；`SpanTextWriter.cs`(13KB)、`ImUtf8.InputText.cs`(20KB) 未读 |
| `String/`、`Log/`、`Compression/`、`Custom/`、`Extensions/` | 14 / 1,560 | 与 UI 无关的工具代码 |
| `Services/DynamisIpc.cs`、`HookManager.cs`、`FastHook.cs` | 3 个 | 只看了 `ServiceManager`/`IService`；Hook 部分未深读 |
