# HoverProbe · 交接本

最后更新：2026-10-24

> 这是一个**只读探针**插件：只观察游戏道具简介框（`ItemDetail`）的节点数据并写日志，不改任何节点、不碰价格、不联网。
> 它的存在意义：排查「别的插件改了简介框」这类问题时，**不能把探针代码写进被测插件或正在开发的插件**（红线，见 `E:\DeepSeek Harness\AGENTS.md` 与 `%USERPROFILE%\.dsh\AGENTS.md`「跨插件通用经验 · 工作方式」）。

## 1. 当前状态

| 项 | 值 |
|---|---|
| 目录 | `E:\DeepSeek Harness\HoverProbe\` |
| 工程 | `HoverProbe.csproj`（`Dalamud.NET.Sdk/15.0.0`，`net10.0`，x64） |
| 源码 | `HoverProbePlugin.cs`（主逻辑）、`Service.cs`（服务定位） |
| 产物 | `bin\Release\HoverProbe.dll` |
| 测试位置 | `D:\Program Files (x86)\Dalamud\HoverProbe\`（dev 插件，登记名 `HoverProbe`） |
| 命令 | `/hoverprobe` 开关日志（默认开） |
| 状态 | 可用；最后用于 PriceInsight 的残影排查（14:03 那轮 Tick 采样） |

## 2. 关键设计决定

| 决定 | 原因 |
|---|---|
| 只读：绝不写节点、不改高度 | 探针一旦写值就会改变被测对象，结论不可信 |
| 日志走 `Log.Warning` | `dalamud.log` 只收 Warning 及以上，`Log.Info` 永远看不到 |
| 四个 addon 事件 + 每帧 `Framework.Update` 都采样 | 前者看「排版时机」，后者看「停留期间是否有写入」，两种证据分开取 |
| 独立工程、独立插件目录 | 不与业务插件共用代码，避免把探针逻辑带进发布物 |

## 3. 踩过的坑

> 下面 1–5 是同类别插件**通用**的编译/打包坑，已归档到 `%USERPROFILE%\.dsh\AGENTS.md`「开发环境坑」；这里只留本项目当时的记录。

1. **编译报 `CS0246 IAddonLifecycle`** → 缺 `using Dalamud.Plugin.Services;`
2. **委托里解引用原生指针** → 整个回调体必须包在 `unsafe { }` 里
3. **`Dump` 里用到实例字段，却写成 static** → 改成实例方法
4. **打包失败：`Plugin name is required`** → csproj 必须写 `Name` / `Author` / `Description` / `Punchline`
5. **加了 `Framework.Update` 采样却没效果** → 先在 `Service` 里补 `[PluginService] private IFramework Framework { get; init; }`；改完必须核对 dll 大小与日志里有没有新行，否则可能是补丁没生效

## 4. 回滚点

| 标签 / commit | 能力边界 |
|---|---|
| （无正式标签） | 本插件只用于排查，没打过 `cp-` 检查点；需要回到旧版时按 commit 取 |

## 5. 常用命令

```powershell
# 编译
cd "E:\DeepSeek Harness\HoverProbe"
& "<dev>\dotnet\dotnet.exe" build HoverProbe.csproj -c Release

# 部署（dev 插件目录）
Copy-Item "bin\Release\HoverProbe.dll","bin\Release\HoverProbe.json" "D:\Program Files (x86)\Dalamud\HoverProbe\" -Force

# 看日志
Select-String -Path "%USERPROFILE%\AppData\Roaming\XIVLauncherCN\dalamud.log" -Pattern "PROBE" | Select-Object -Last 40
```

游戏内：`/xlplugins` → 左侧「开发工具」→「已安装开发版插件」→ 禁用再启用 `HoverProbe`；聊天栏 `/hoverprobe` 开关。

## 6. 待办

- [ ] 采样字段目前是 `winH / nineGridH / rootH / hintY`，需要时可扩展
