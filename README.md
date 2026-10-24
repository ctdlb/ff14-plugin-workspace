# FF14 插件开发工作区

给 AI 用的插件开发工作区：一套规则、一套环境重建脚本、一批踩坑记录。仓库本身**不含任何插件代码**。

## 怎么装

把下面这句话发给 AI，它会自己完成部署：

> 从 https://github.com/ctdlb/ff14-plugin-workspace 把工作区部署到当前目录，然后读 `AGENTS.md` 和 `docs\新电脑环境搭建.md`，跑 `tools\setup-dev-env.ps1` 装环境，装完自己验证。

装到哪里：**跟当前对话的工作区目录走**——仓库直接落在那个目录里（不再套一层文件夹），脚本按自己所在位置反推工作区，不用指定路径。工具和知识库装在**同一块盘的根目录**下（`<盘符>:\FF14Dev`），装之前脚本会先报出路径让你确认。

> 工作区目录必须就是 `AGENTS.md` 所在的那一层，开对话的目录要和它一致。规则文件只从「当前对话目录」加载、不会往下钻子文件夹；多套一层又在上层开对话，就读不到工作区规则（用户级规则仍在）。

脚本做的事：

- 装 .NET SDK、MinGit、EXDViewer；
- 克隆八个源码知识库（Dalamud、FFXIVClientStructs、FFXIVClientStructs.Expansion、FFXIVNetworkOpcodes、imgui、KamiToolKit、OmenTools、OmenTools.KamiToolKit）；
- 检测游戏目录、必要时拉起 EXDViewer 让你填一次路径；
- 可选：把 GitHub 令牌存进凭据管理器（`-GitHubToken`）；
- **不装任何插件**（作者自己的插件要加 `-IncludeMyPlugins`）；
- **不碰 DSH 的用户级规则**（那是另一个仓库 `ctdlb/dsh-plugins` 的事）。

占用约 1.2 GB，十几分钟。

装完还要收尾两步，其中一步已经半自动：

1. **EXDViewer 指认游戏目录**：脚本会先从 XIVLauncher 配置里自动查出游戏目录并打印，然后把 EXDViewer 窗口拉起来，你在设置里填那一行、关掉窗口即可（已配过的机器自动跳过）。
2. **GitHub 令牌**：重跑脚本加 `-GitHubToken <令牌>`（或交互时直接粘贴），脚本会写进 Windows 凭据管理器，之后 push 不再弹窗。令牌本身只能你自己在 GitHub 生成。

## 自己动手装

```powershell
# 在当前对话的工作区目录里执行（仓库落在当前目录）
git -c http.proxy=http://127.0.0.1:7897 clone https://github.com/ctdlb/ff14-plugin-workspace.git .

powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\setup-dev-env.ps1"
```

`github.com` 需要代理，端口不同就改 `http.proxy`；没有代理就在浏览器里下载仓库 ZIP，解压到当前目录（别多套一层文件夹）。

## 脚本依赖

不需要预装任何运行时，全部是 Windows 自带：

| 依赖 | 情况 |
|---|---|
| Windows PowerShell 5.1 | 自带（Win10/11）；脚本只用 5.1 兼容语法，不要求 PowerShell 7 |
| `curl.exe` | 自带（Win10 1803+），脚本用它下载 |
| `Expand-Archive`、`Get-FileHash` | PowerShell 内置命令 |
| 网络 | 需要，下载约 1.2 GB |
| git | 可能没有。没有就用浏览器「Download ZIP」解压到目标目录，脚本之后会自己装好 MinGit |

Windows 默认禁止运行 `.ps1`，跑之前加一次 `-ExecutionPolicy Bypass`（只对本次生效，不改系统设置）。Windows 7 / 8.1 不支持：那类系统跑不了 Dalamud。

## 仓库里有什么

| 路径 | 用途 |
|---|---|
| `AGENTS.md` | 工作区规则：环境路径、发布流程、禁忌、验证要求 |
| `docs\新电脑环境搭建.md` | 换机器的完整步骤、参数、故障排查 |
| `docs\插件开发坑.md` | 踩过的坑与结论（窗口布局、节点链、探针用法等） |
| `tools\setup-dev-env.ps1` | 一条命令重建整套环境 |
| `tools\exd.ps1` | 查游戏数据表（走 EXDViewer 的 MCP） |
| `HoverProbe\` | 只读探针插件，用于观察游戏提示框布局，不发布 |

## 关于插件

本仓库**不含插件代码**，部署脚本**不装插件**。

作者自己的插件是独立仓库：[ctdlb/TextToTalkCN](https://github.com/ctdlb/TextToTalkCN)（汉化重构）、[ctdlb/DalamudPlugins](https://github.com/ctdlb/DalamudPlugins)（发布库）。要用插件走游戏内 `/xlplugins` 添加插件库，与本工作区无关。

## 其他

- 本仓库不含令牌、密钥或游戏文件。
- 工具与知识库跟仓库分开放：约 1.2 GB，不进 git，装坏了可以直接删掉重装。换位置用 `-Root` 指定。
- 文档里出现的 `<盘符>:\FF14Dev\...` 是**占位**：实际盘符＝你工作区所在的盘。例如工作区在 `D:\插件开发`，工具就装到 `D:\FF14Dev`；工作区在 `C:\...`，就是 `C:\FF14Dev`。
