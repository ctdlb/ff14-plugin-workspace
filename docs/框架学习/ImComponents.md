# ImComponents 学习笔记（源码精读）

> 调研对象：`E:\DeepSeek Harness\.tmp\study\ImComponents`（`--depth 1`，HEAD `ce6de81`，2025-12-21 "Update to dotnet10"）。
> 只读调研：未编译、未改动任何文件。推断标「推测」。这个库极小，**5 个文件全部读完**，没有跳过的目录。

## 一句话定位

Minizbot2012 的个人小工具集：三个零散的 ImGui 控件（**返回值变化的 Checkbox**、**开关样式的 ToggleButton**、**径向菜单 RadialMenu**）。它不是框架，没有基础设施，也没有一起用的入口。

- 仓库：<https://github.com/Minizbot2012/ImComponents>
- LICENSE：文件名 `LICENSE`，实际许可是 **GNU General Public License v3.0**（`LICENSE:1-2` 明写 "GNU GENERAL PUBLIC LICENSE / Version 3, 29 June 2007"）。是 copyleft，不是 MIT。
- 规模：**5 个 `.cs`，344 行**（`find … | xargs cat | wc -l`）。5 个文件都没有结尾换行，编辑器显示行数各多 1，按显示计为 349：`CheckBoxExt.cs` 23、`RadialMenu.cs` 228、`RadialRaii.cs` 58、`Singleton.cs` 8、`ToggleButton.cs` 32。
- 工程：`ImComponents.csproj:1` 用的是**裸 `Microsoft.NET.Sdk`**，不是 `Dalamud.NET.Sdk`；`TargetFramework` 是 `net10.0`（`:4`）。

## 核心 API

全库公开 API 只有 4 组，抄全了：

1. **返回「本帧是否被改过」的 Checkbox** —— `CheckBoxExt.cs:5`、`:13`
   ```csharp
   public static bool Checkbox(string text, ref bool active)
   public static bool Checkbox(string text, string tooltip, ref bool active)
   ```
   内部先存 `var old = active;`，`ImGui.Checkbox` 之后比较（`:6-11`），变化返回 `true`。带 tooltip 的重载用 `ImGui.IsItemHovered()` + `ImGui.SetTooltip`（`:16-17`）。

2. **开关样式的 ToggleButton**（画胶囊 + 圆点，不是 ImGui 自带控件）—— `ToggleButton.cs:7`
   ```csharp
   public static void ToggleButton(string id, ref bool v)
   ```
   用 `ImGui.InvisibleButton(id, new Vector2(width, height))` 占位（`:14`），再用 `ImGui.GetWindowDrawList()` 画圆角矩形与圆点（`:28-29`），最后 `AddText` 把 `id` 当标签画在右侧（`:30`）。尺寸：`height = ImGui.GetFrameHeight(); width = height * 1.55f; radius = height * 0.50f;`（`:11-13`）。

3. **径向菜单**（按住鼠标 → 绕环形选择）—— `RadialMenu.cs:14`、`:43`、`:117`、`:145`
   ```csharp
   public static RadialMenu Instance => Singleton<RadialMenu>.Instance;
   public bool BeginRadialPopup(bool open)
   public bool RadialMenuItem(string name)
   public void EndRadialMenu()
   ```
   外加回调重载 `public void RadialMenuItem(string name, Action<string> cb)`（`:141`）。内部用三个 `Stack<>` 保存层级/悬停项/旋转角（`RadialMenu.cs:21-23`），菜单半径 `RADIUS_MAX = 120f`、`RADIUS_MIN = 30f`（`:68-69`）。

4. **RAII 包装（未完成）** —— `RadialRaii.cs:14`、`:37`
   ```csharp
   public RadialMenu(bool open)
   public SubMenu(string name)
   ```
   另有单例工具 `Singleton.cs:7` `public static T Instance { get { return instance.Value; } }`（`Lazy<T>` + `Activator.CreateInstance(typeof(T), true)`，支持私有构造）。

## 它解决什么问题 / 怎么用

只解决三个很具体的小问题：**「改完要不要立刻存盘」的 Checkbox**、**好看一点的开关**、**手柄/鼠标径向菜单**。

```csharp
// 示意，未编译
// 1) 值变了才存盘（省掉每个 checkbox 自己比较）
if (ChangedCheck.Checkbox("显示最低价", "悬停时显示", ref config.ShowLowest))
    config.Save();

// 2) 开关按钮
ToggleComponents.ToggleButton("##enable", ref config.Enabled);

// 3) 径向菜单：按住某键时，用鼠标方向选项目
using (var menu = new ImComponents.Raii.RadialMenu(pressed))   // RadialRaii.cs:14
{
    menu.RadialMenuItem("传送");
    using (var sub = menu.Menu("更多"))                        // RadialRaii.cs:37
    {
        sub.RadialMenuItem("设置");
    }
}
```

## 对我们的用处

**没有用，建议不引入。** 我们做的是「往游戏原生 `ItemDetail` addon 里插文本节点并撑高窗口」：

- 这个库一共 344 行，全部是 ImGui 窗口内的自绘控件，**一行原生 addon / AtkUnitBase 代码都没有**（`RadialMenu.cs` 只用了 `Dalamud.Bindings.ImGui`，见 `:4`）。
- 唯一可能有用的是 `ToggleButton`（`ToggleButton.cs`，32 行）和 `ChangedCheck.Checkbox`（`CheckBoxExt.cs`，23 行）—— 这两段自己照着写更快，不必为它们引入一个 **GPL-3.0** 依赖。
- 径向菜单我们用不上（设置窗口不需要按住鼠标选环）。
- 许可问题是硬伤：GPL-3.0 是 copyleft，把它链接进我们的插件会在许可上牵连整个插件（具体法律后果**未确认**，但事实是许可证为 GPLv3，见 `LICENSE:1-2`）。

## 坑 / 限制

- **许可**：GPL-3.0（`LICENSE`）。比 MIT/Apache 严格得多，商用或闭源分发前必须先确认。
- **本机编不过**：`ImComponents.csproj:27-28` 的 `LibPath` 只探测两个路径——
  `$(HOME)\.xlcore\dalamud\Hooks\dev` 与 `$(AppData)\XIVLauncher\addon\Hooks\dev`。
  本机实测（2026-10-25）：国服目录是 `C:\Users\ctdlb\AppData\Roaming\XIVLauncherCN\addon\Hooks\dev`（存在），上面两条**都不存在**（`.xlcore\dalamud` 与 `XIVLauncher` 均报 No such file or directory）。
  于是 `LibPath` 为空，`HintPath` 退化成 `\Dalamud.Bindings.ImGui.dll`（`:33`），**编译必然报找不到引用**。要用得自己加一条 `XIVLauncherCN` 分支。
- **不需要 Dalamud SDK、也不带 Dalamud 引用**：只引用 `Dalamud.Bindings.ImGui.dll`（`:32-35`）。所以它对 Dalamud API 版本没有硬要求，代价是拿不到 `UiBuilder`、`IService` 之类；只要 ImGui 绑定命名空间对得上（跨版本是否兼容**未确认**）。
- **命名空间是混的**：`ImComponents`（`CheckBoxExt.cs:2`、`RadialMenu.cs:7`、`ToggleButton.cs:3`）、`MZCommon`（`Singleton.cs:3`）、`ImComponents.Raii`（`RadialRaii.cs:3`）。`RadialMenu.cs:5` 必须 `using MZCommon;` 才能拿到单例——这是从别的项目剪过来的痕迹。
- **明显的半成品痕迹**：`RadialRaii.cs:5` 注释原文 `//Eventually gonna re-wire everything to this class.... it'll be fun`；`RadialRaii.cs` 的 `Dispose` 调了 `GC.SuppressFinalize(this)`（`:20`、`:43`）但类里没有 finalizer，属无害噪声。
- **`EndRadialMenu` 不判空就 `Pop`**：`RadialMenu.cs:147` `var ctx = Root.items.Pop();`——推断：Begin/End 不配对时会抛 `InvalidOperationException`（空栈），把整个绘制帧打断。
- **画在背景层**：`RadialMenu.cs:149` 用 `ImGui.GetBackgroundDrawList()`，推测会被普通窗口/弹窗盖住（只能在没有遮挡时看得见）。
- **维护粗放**：`RadialMenu.cs:178` 变量名拼错 `arc_segemnts`；`RadialMenu.cs:20-27` 的 `RadialState` 全是小写 public 字段。生产代码里这些都会变成维护负担。
- **仓库信息量太低**：shallow clone 只有 1 条 commit（2025-12-21），无 README、无示例、无 CI，看不出谁在用、也看不出会不会继续维护。

## 还没读透的部分

无。5 个 `.cs` / 344 行已全部逐行读完；`.gitignore`、`LICENSE`、`ImComponents.csproj` 也读过。

未确认的只有两项：① GPL-3.0 链接进插件后的具体法律边界；② 这个库的 `Dalamud.Bindings.ImGui` 与本机 Dalamud 版本的兼容性（没编译，所以没验证）。
