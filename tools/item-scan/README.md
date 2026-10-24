# item-scan

按条件扫描 FF14 游戏数据表（默认 `Item`），直接读本机 sqpack，不经过 EXDViewer。

批量查询（几千上万行、要排序/筛选/导出）用它；只想看一两行的原始字段，还是用 `tools\exd.ps1` 更快。

## 用法

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\item-scan\item-scan.ps1 `
    --where "Description.Length >= 150" --columns RowId,Name --limit 10
```

（`-ExecutionPolicy Bypass` 不能省：本机执行策略禁止直接跑 `.ps1`。）

## 参数

| 参数 | 说明 | 默认 |
|---|---|---|
| `--sheet` | 表名，如 `Item`、`Mount`、`Recipe` | `Item` |
| `--where` | 筛选条件，见下 | 不过滤 |
| `--columns` | 输出列，逗号分隔，支持 `A.B` 与 `.Length` | `RowId,Name` |
| `--orderby` | 排序列 | 不排序 |
| `--desc` | 排序反向 | 否 |
| `--limit` | 最多输出多少行 | 50 |
| `--csv` | 导出 CSV 路径（UTF-8 BOM） | 不导出 |

## 条件写法

```
属性路径 运算符 值
```

- 运算符：`==` `!=` `>` `<` `>=` `<=`
- 属性路径可嵌套：`ItemSearchCategory.RowId`
- 字符串属性加 `.Length` 取长度：`Description.Length`
- 值可加双引号，不加也行
- 数字按数值比较，其余按字符串比较

常用条件：

```powershell
# 描述长度 >= 150 的物品
--where "Description.Length >= 150"

# 能上市场板的物品（市场分类不为 0）
--where "ItemSearchCategory.RowId != 0"

# 名字精确匹配
--where "Name == 煎饺"

# 组合：可交易且描述够长（只支持单条件，组合请导 CSV 后再筛）
--where "Description.Length >= 200"
```

## 示例

```powershell
# 描述最长的 10 个物品
powershell -NoProfile -ExecutionPolicy Bypass -File tools\item-scan\item-scan.ps1 `
    --where "Description.Length >= 100" --columns RowId,Name,Description.Length `
    --orderby "Description.Length" --desc --limit 10

# 全部可交易物品导出 CSV
powershell -NoProfile -ExecutionPolicy Bypass -File tools\item-scan\item-scan.ps1 `
    --where "ItemSearchCategory.RowId != 0" --columns RowId,Name `
    --limit 100000 --csv items.csv
```

## 实现要点（改代码前先看）

- 数据路径：环境变量 `FF14_DATA`，默认 `D:\Program Files (x86)\最终幻想XIV\game\sqpack`
  - **必须指到 `sqpack` 目录**，指到 `game` 会报 `the data path arg must point to the sqpack directory`
- 语言：写死 `Language.ChineseSimplified`，不传会报 `Specified excel language is not supported`
- 引用 `Lumina.dll` / `Lumina.Excel.dll` 来自 `%APPDATA%\XIVLauncherCN\addon\Hooks\dev`，Dalamud 升级后若 API 变动需要重新编译
- 表类型按名字反射查找，所以 `--sheet` 支持任意 Lumina sheet 名（如 `Mount`、`Emote`、`Recipe`）
