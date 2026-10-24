using System.Collections;
using System.Globalization;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using Lumina;
using Lumina.Data;
using Lumina.Excel;

var opt = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
var flags = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
for (var i = 0; i < args.Length; i++)
{
    if (!args[i].StartsWith("--")) continue;
    var key = args[i][2..];
    if (i + 1 < args.Length && !args[i + 1].StartsWith("--")) { opt[key] = args[++i]; }
    else { flags.Add(key); }
}

var dataPath = Environment.GetEnvironmentVariable("FF14_DATA")
    ?? @"D:\Program Files (x86)\最终幻想XIV\game\sqpack";
var sheetName = opt.GetValueOrDefault("sheet", "Item");
var columns = opt.GetValueOrDefault("columns", "RowId,Name")
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
var where = opt.GetValueOrDefault("where");
var orderBy = opt.GetValueOrDefault("orderby");
var descending = flags.Contains("desc");
var limit = int.TryParse(opt.GetValueOrDefault("limit", "50"), out var lim) ? lim : 50;
var csvPath = opt.GetValueOrDefault("csv");

using var data = new GameData(dataPath, new LuminaOptions
{
    PanicOnSheetChecksumMismatch = false,
    DefaultExcelLanguage = Language.ChineseSimplified,
});
var excel = new ExcelModule(data);

var rowType = typeof(Lumina.Excel.Sheets.Item).Assembly.GetTypes()
    .FirstOrDefault(t => string.Equals(t.Name, sheetName, StringComparison.OrdinalIgnoreCase));
if (rowType == null)
{
    Console.Error.WriteLine($"找不到表：{sheetName}");
    return 2;
}

var getSheet = typeof(ExcelModule).GetMethods()
    .First(m => m.Name == "GetSheet" && m.IsGenericMethodDefinition && m.GetParameters().Length == 2);
var sheet = (IEnumerable)getSheet.MakeGenericMethod(rowType)
    .Invoke(excel, new object[] { Language.ChineseSimplified, null });

Regex cond = null;
string condProp = null, condOp = null, condValue = null;
if (!string.IsNullOrWhiteSpace(where))
{
    cond = new Regex(@"^\s*(?<prop>[A-Za-z0-9_.]+?)\s*(?<op>>=|<=|==|!=|>|<)\s*(?<val>.+?)\s*$");
    var match = cond.Match(where);
    if (!match.Success)
    {
        Console.Error.WriteLine($"条件看不懂：{where}");
        return 3;
    }

    condProp = match.Groups["prop"].Value;
    condOp = match.Groups["op"].Value;
    condValue = match.Groups["val"].Value.Trim().Trim('"');
}

object Resolve(object root, string path)
{
    object cur = root;
    foreach (var part in path.Split('.'))
    {
        if (cur == null) return null;
        if (cur is Lumina.Text.ReadOnly.ReadOnlySeString se) cur = se.ToString();

        if (part == "Length")
        {
            cur = cur switch
            {
                string s => s.Length,
                ICollection c => c.Count,
                _ => cur.GetType().GetProperty("Length")?.GetValue(cur),
            };
            continue;
        }

        var p = cur.GetType().GetProperty(part, BindingFlags.Public | BindingFlags.Instance);
        cur = p?.GetValue(cur);
    }

    return cur is Lumina.Text.ReadOnly.ReadOnlySeString r ? r.ToString() : cur;
}

static string Fmt(object v) => v switch
{
    null => string.Empty,
    string s => s,
    bool b => b ? "true" : "false",
    IFormattable f => f.ToString(null, CultureInfo.InvariantCulture),
    _ => v.ToString(),
};

bool Matches(object row)
{
    if (cond == null) return true;

    var left = Resolve(row, condProp);
    var leftText = Fmt(left);

    if (left is not string
        && double.TryParse(leftText, NumberStyles.Any, CultureInfo.InvariantCulture, out var ln)
        && double.TryParse(condValue, NumberStyles.Any, CultureInfo.InvariantCulture, out var rn))
    {
        return Compare(ln, rn, condOp);
    }

    return CompareText(leftText, condValue, condOp);
}

static bool Compare(double a, double b, string op) => op switch
{
    "==" => Math.Abs(a - b) < 1e-9,
    "!=" => Math.Abs(a - b) >= 1e-9,
    ">" => a > b,
    "<" => a < b,
    ">=" => a >= b,
    "<=" => a <= b,
    _ => false,
};

static bool CompareText(string a, string b, string op)
{
    var c = string.CompareOrdinal(a, b);
    return op switch
    {
        "==" => c == 0,
        "!=" => c != 0,
        ">" => c > 0,
        "<" => c < 0,
        ">=" => c >= 0,
        "<=" => c <= 0,
        _ => false,
    };
}

var rows = new List<(string[] Cols, double SortNum, string SortText)>();
foreach (var row in sheet)
{
    if (!Matches(row)) continue;

    var cols = columns.Select(c => Fmt(Resolve(row, c))).ToArray();
    var sortValue = orderBy == null ? null : Resolve(row, orderBy);
    var sortText = Fmt(sortValue);
    var sortNum = double.TryParse(sortText, NumberStyles.Any, CultureInfo.InvariantCulture, out var n) ? n : 0d;
    rows.Add((cols, sortNum, sortText));
}

if (orderBy != null)
{
    rows = descending
        ? rows.OrderByDescending(r => r.SortNum).ThenByDescending(r => r.SortText, StringComparer.Ordinal).ToList()
        : rows.OrderBy(r => r.SortNum).ThenBy(r => r.SortText, StringComparer.Ordinal).ToList();
}

Console.WriteLine(string.Join("\t", columns));
foreach (var r in rows.Take(limit))
{
    Console.WriteLine(string.Join("\t", r.Cols));
}

Console.WriteLine($"匹配 {rows.Count} 行，显示 {Math.Min(limit, rows.Count)} 行");

if (!string.IsNullOrWhiteSpace(csvPath))
{
    var sb = new StringBuilder();
    sb.AppendLine(string.Join(",", columns.Select(c => $"\"{c}\"")));
    foreach (var r in rows)
    {
        sb.AppendLine(string.Join(",", r.Cols.Select(v => $"\"{v.Replace("\"", "\"\"")}\"")));
    }

    File.WriteAllText(csvPath, sb.ToString(), new UTF8Encoding(true));
    Console.WriteLine($"已写 {csvPath}");
}

return 0;