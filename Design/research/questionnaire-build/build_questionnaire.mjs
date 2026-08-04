import fs from "node:fs/promises";
import path from "node:path";
import { Workbook, SpreadsheetFile } from "@oai/artifact-tool";

const questions = [
  {
    id: "Q01", priority: "必须回答", category: "现状材料",
    question: "能否补一组最新版真机截图或录屏？最需要：首页三个档位、首页滚动前/标题停靠后、文章列表顶部/滚动后、正文刚进入/阅读栏停靠、翻译进行中/完成后、正文深色模式、当前七键控件板。",
    options: ["可以，稍后提供", "现有材料已是最新", "没有现成材料", "由你根据现有材料判断"],
    fallback: "需要你确认；若没有新材料，我会按现有截图与代码推断，并标注可能的版本差异。"
  },
  {
    id: "Q02", priority: "必须回答", category: "现状材料",
    question: "Reference/2.PNG 是否可以视为目前最新的文章列表外观？",
    options: ["是，视为最新", "大体相同但有细节变化", "不是，稍后补最新截图", "不确定"],
    fallback: "不把它视为完全最新，只作为当前方向与密度参考。"
  },
  {
    id: "Q03", priority: "必须回答", category: "现状材料",
    question: "external resources/screenshots/文章内容.PNG 已早于当前控件板和阅读栏；现在正文主体排版是否仍基本相同？",
    options: ["主体排版基本相同", "已有明显变化，稍后补充", "仅控件板和阅读栏变化", "不确定"],
    fallback: "按代码和设计简报推断最新结构，旧截图只用于正文内容参考。"
  },
  {
    id: "Q04", priority: "必须回答", category: "现状材料",
    question: "真实数据压力测试使用什么材料？",
    options: ["我会提供真实极端案例", "请从现有素材中挑选", "请合理构造但使用真实风格", "两者结合"],
    fallback: "从现有内容挑选，并补充合理的极端案例。"
  },
  {
    id: "Q05", priority: "必须回答", category: "交付范围",
    question: "App 图标是否属于本轮重设计范围？",
    options: ["纳入第一轮", "暂不纳入", "只评估不重画", "由你判断"],
    fallback: "暂不重画图标，只评估它与三个设计方向是否一致。"
  },
  {
    id: "Q06", priority: "必须回答", category: "交付范围",
    question: "浮世绘头图可以被替换时，当前 App 图标应如何处理？",
    options: ["必须保留当前图标", "可以优化但保持主题", "可以彻底重做", "第一轮先不动"],
    fallback: "方向 B 保留当前主题，方向 A/C 允许替换，以便真正比较。"
  },
  {
    id: "Q07", priority: "必须回答", category: "交付范围",
    question: "长图分享是否列为第一轮的核心设计稿？",
    options: ["同意，纳入核心稿", "选定方向后再做", "只给规则不画稿", "暂不考虑"],
    fallback: "三个方向先给长图规则，选中方向后绘制完整长图稿。"
  },
  {
    id: "Q08", priority: "必须回答", category: "交付范围",
    question: "发现页、空状态、加载态和错误态需要做到什么范围？",
    options: ["三个方向都画", "选定方向后再展开", "第一轮只画最关键状态", "由你判断"],
    fallback: "第一轮画最关键压力状态，其余在选定方向后展开。"
  },
  {
    id: "Q09", priority: "必须回答", category: "交付范围",
    question: "设置页是否纳入设计稿？",
    options: ["完全不纳入", "只给沿用原则", "选定方向后补一页", "纳入第一轮"],
    fallback: "只给如何沿用新系统的原则，不重构设置页。"
  },
  {
    id: "Q10", priority: "必须回答", category: "交付范围",
    question: "第一轮希望看到怎样的精细度？",
    options: ["高保真成品感", "中等保真，方向差异优先", "先粗稿再精修", "由你安排"],
    fallback: "中高保真，先确保三个方向的取舍清楚，再精修选中方向。"
  },
  {
    id: "Q11", priority: "必须回答", category: "翻译与中英关系",
    question: "翻译后的标题是否需要让用户一眼知道“这是译文”？",
    options: ["不标记，中文即默认", "极小“译”字或符号", "保留一行淡色原标题", "点按或长按显示原标题", "由你判断"],
    fallback: "使用极轻的译文标记，并提供按需查看原标题的入口。"
  },
  {
    id: "Q12", priority: "必须回答", category: "翻译与中英关系",
    question: "如果只能优先保证一个目标，你更重视什么？",
    options: ["快速扫中文标题", "随时核对原标题", "清楚知道翻译状态", "三者尽量平衡", "由你判断"],
    fallback: "中文扫读优先，同时保留安静的核对入口。"
  },
  {
    id: "Q13", priority: "建议回答", category: "翻译与中英关系",
    question: "未来的原译对照，你更倾向哪种方式？",
    options: ["中文下方整段英文", "点某段展开英文", "原文/译文整页切换", "左右滑动切换", "暂不决定", "由你判断"],
    fallback: "以整页切换为主，段落按需展开作为补充。"
  },
  {
    id: "Q14", priority: "建议回答", category: "翻译与中英关系",
    question: "标题翻译尚未完成时，应怎样显示？",
    options: ["直接显示英文，无状态", "英文加轻量处理中状态", "显示骨架或占位", "由你判断"],
    fallback: "保留英文，并显示轻量处理中状态。"
  },
  {
    id: "Q15", priority: "建议回答", category: "翻译与中英关系",
    question: "标题或正文翻译失败时，应怎样反馈？",
    options: ["保留英文即可", "轻量错误标记", "明确错误提示并可重试", "由你判断"],
    fallback: "保留英文，给出轻量错误标记与重试入口。"
  },
  {
    id: "Q16", priority: "建议回答", category: "翻译与中英关系",
    question: "中文译题与英文原题相邻时，能否接受文章行变高？",
    options: ["可以变高，核对优先", "密度优先，不常驻原标题", "仅在特定状态变高", "由你判断"],
    fallback: "密度优先，原标题不常驻，仅在需要时展开。"
  },
  {
    id: "Q17", priority: "建议回答", category: "翻译与中英关系",
    question: "RSS 本身就是中文的文章，应与“由英文翻译成中文”的文章有什么关系？",
    options: ["完全一样", "需区分原生中文与译文", "只在详情中可辨", "由你判断"],
    fallback: "列表中基本一致，详情或按需信息中可辨。"
  },
  {
    id: "Q18", priority: "建议回答", category: "文章行",
    question: "文章列表希望保持怎样的密度？",
    options: ["保持约 6–7 篇", "降到约 5–6 篇", "希望更密集", "不同内容自适应", "由你判断"],
    fallback: "保持一屏约 6–7 篇，同时让极端内容自然增高。"
  },
  {
    id: "Q19", priority: "建议回答", category: "文章行",
    question: "摘要对你判断是否打开文章的价值有多大？",
    options: ["经常靠摘要判断", "偶尔参考", "主要只扫标题", "不同源不同处理", "由你判断"],
    fallback: "保留摘要，但明显弱于标题。"
  },
  {
    id: "Q20", priority: "建议回答", category: "文章行",
    question: "右侧缩略图希望如何处理？",
    options: ["固定右侧缩略图", "仅高质量图片显示", "标题下小横幅", "完全无图", "请同时比较多个方案"],
    fallback: "仅在图片质量和相关性足够时显示；压力测试中覆盖无图状态。"
  },
  {
    id: "Q21", priority: "建议回答", category: "文章行",
    question: "目前已读行整体约 45% 不透明度，你喜欢这种强区分吗？",
    options: ["喜欢 45% 强区分", "提高到 60%–70%", "只改变标题和摘要灰度", "由你判断"],
    fallback: "提高到约 65%，避免整屏已读内容像被禁用。"
  },
  {
    id: "Q22", priority: "建议回答", category: "文章行",
    question: "时间信息怎样最有用？",
    options: ["相对时间更有用", "具体日期更有用", "当天相对、较早具体", "时间不重要", "由你判断"],
    fallback: "当天显示相对时间，较早内容显示具体日期。"
  },
  {
    id: "Q23", priority: "建议回答", category: "文章行",
    question: "源名过长时，应优先保证什么？",
    options: ["完整源名优先", "时间优先", "动态截断平衡", "由你判断"],
    fallback: "动态截断源名，但给时间保留稳定位置。"
  },
  {
    id: "Q24", priority: "建议回答", category: "文章行",
    question: "星标在列表行中应如何出现？",
    options: ["始终可见", "仅星标文章出现", "只在滑动或操作时出现", "由你判断"],
    fallback: "仅已星标文章显示。"
  },
  {
    id: "Q25", priority: "必须回答", category: "字体与语言",
    question: "简体、繁体与原始语言的处理规则是什么？",
    options: ["译文固定简体；RSS 可有繁体", "全部统一为简体", "保留各源原语言或字形", "其他（右侧说明）"],
    fallback: "译文使用简体；原生中文 RSS 保留来源字形。"
  },
  {
    id: "Q26", priority: "建议回答", category: "字体与语言",
    question: "若设计需要思源宋体 Regular / Medium / Semibold，是否接受增加几 MB 字体资源？",
    options: ["接受增加字体资源", "尽量不增加体积", "只增加一个必要字重", "由你判断"],
    fallback: "只增加能显著改善配对的一到两个必要字重。"
  },
  {
    id: "Q27", priority: "建议回答", category: "字体与语言",
    question: "衬线体适合出现在哪些位置？",
    options: ["只用于头图或大标题", "正文也可尝试衬线", "列表标题也可尝试", "请分别做对比"],
    fallback: "主要用于头图和正文大标题；正文另做阅读对比。"
  },
  {
    id: "Q28", priority: "建议回答", category: "字体与语言",
    question: "正文阅读字体更偏好哪一类？",
    options: ["黑体", "宋体", "中文宋体加英文 New York", "不同场景不同字体", "由你判断"],
    fallback: "基础方案先用黑体，同时测试长文宋体方案。"
  },
  {
    id: "Q29", priority: "建议回答", category: "字体与语言",
    question: "动态字号压力测试做到哪一级？",
    options: ["默认加放大两档", "再加最大普通字号", "包括无障碍超大字号", "由你判断"],
    fallback: "测试默认、放大两档和最大普通字号；规范中再覆盖无障碍降级。"
  },
  {
    id: "Q30", priority: "必须回答", category: "图像与品牌",
    question: "你现在对浮世绘方向的真实态度更接近哪一种？",
    options: ["很喜欢，只需控制边界", "喜欢氛围，不坚持日本视觉语言", "已有些腻，可以彻底替换", "三个方向分别保留、弱化、取消", "由你判断"],
    fallback: "三个方向分别保留、弱化和取消，以实稿比较。"
  },
  {
    id: "Q31", priority: "建议回答", category: "图像与品牌",
    question: "如果替换意象，你愿意探索哪些母题？",
    options: ["书房或阅读空间", "印刷校样或编辑痕迹", "航图、星图或远方来信", "抽象文字结构", "中国传统视觉", "组合或其他（右侧说明）", "由你判断"],
    fallback: "优先探索编辑校样、远方来信与抽象文字结构的组合。"
  },
  {
    id: "Q32", priority: "建议回答", category: "图像与品牌",
    question: "是否允许生成新的头图和装饰资源？",
    options: ["允许生成新图像", "仅可使用现有素材", "可生成但最终需我确认", "只做无图形方向"],
    fallback: "允许生成，但保留原始输出、最终版本和素材清单供你确认。"
  },
  {
    id: "Q33", priority: "建议回答", category: "图像与品牌",
    question: "浅色/深色头图“白天变夜晚”的叙事变化有多重要？",
    options: ["很喜欢，必须保留", "可以保留但不是重点", "只是可接受", "可以取消", "由你判断"],
    fallback: "保留自然的昼夜变化，但不把它设为所有方向的硬规则。"
  },
  {
    id: "Q34", priority: "建议回答", category: "图像与品牌",
    question: "Babel 是否可以按近似最终品牌名设计？",
    options: ["可按最终品牌设计", "可能改名，需可替换", "暂不确定", "由你判断"],
    fallback: "按可替换的字标和通用组件设计，不依赖特定字母造型。"
  },
  {
    id: "Q35", priority: "建议回答", category: "图像与品牌",
    question: "陶土红强调色需要保留到什么程度？",
    options: ["陶土红必须保留", "可微调陶土红", "三个方向可探索不同色", "完全开放", "由你判断"],
    fallback: "保留陶土红作为基线，允许三个方向探索不同但克制的强调色。"
  },
  {
    id: "Q36", priority: "建议回答", category: "正文与动效",
    question: "当前正文最让你不满意的部分是什么？可在右侧补充具体例子。",
    options: ["整体缺少品牌感", "字号或行宽", "标题或阅读栏", "图片排版", "底部控件板", "多个问题（右侧说明）", "由你判断"],
    fallback: "优先处理阅读栏、中英关系与控件板的信息层级。"
  },
  {
    id: "Q37", priority: "建议回答", category: "正文与动效",
    question: "翻译逐字或逐段出现时，你现在的感受如何？",
    options: ["有生命感，喜欢", "偶尔打断但可接受", "明显打断阅读", "希望更安静", "由你判断"],
    fallback: "保留渐进感，但减少闪动和对正在阅读段落的干扰。"
  },
  {
    id: "Q38", priority: "建议回答", category: "正文与动效",
    question: "翻译完成后，需要怎样的完成反馈？",
    options: ["明确完成瞬间", "轻微但可感知", "几乎无感", "由你判断"],
    fallback: "轻微但可感知，不弹出额外提示。"
  },
  {
    id: "Q39", priority: "建议回答", category: "正文与动效",
    question: "进入文章的转场更适合哪种方向？",
    options: ["系统原生推入", "纸张从列表行展开", "系统转场加阅读栏轻接力", "请比较多个方案", "由你判断"],
    fallback: "保留系统转场，只让阅读栏和正文做轻微接力。"
  },
  {
    id: "Q40", priority: "建议回答", category: "正文与动效",
    question: "星标/未读/全部三档切换时，内容应怎样变化？",
    options: ["横向滑动", "交叉淡入", "内容切换加头图淡入", "由你判断"],
    fallback: "保留轻微横向动势，头图使用淡入，避免整屏剧烈移动。"
  },
  {
    id: "Q41", priority: "建议回答", category: "正文与动效",
    question: "是否需要为系统“减少动态效果”定义专门的降级规则？",
    options: ["需要", "暂时不需要", "选定方向后补", "由你判断"],
    fallback: "需要：将位移转场降级为淡入淡出。"
  },
  {
    id: "Q42", priority: "必须回答", category: "文件与评审",
    question: "最终可编辑文件希望使用什么格式？",
    options: ["HTML/CSS/SVG 加 PNG/PDF 即可", "明确需要 Figma", "两者都要", "暂不确定"],
    fallback: "以本地可编辑的 HTML/CSS/SVG 为主，并导出 PNG/PDF。"
  },
  {
    id: "Q43", priority: "必须回答", category: "文件与评审",
    question: "设计画布是否按当前截图的 402 × 874 pt、@3x 输出？",
    options: ["是，402 × 874 pt、@3x", "按另一设备尺寸（右侧填写）", "同时做多尺寸", "由你判断"],
    fallback: "按 402 × 874 pt、@3x 制作主稿，并验证较窄宽度。"
  },
  {
    id: "Q44", priority: "必须回答", category: "文件与评审",
    question: "你希望怎样评审三个方向？",
    options: ["一张总览板并排比较", "本地交互页面逐个切换", "两者都要", "由你判断"],
    fallback: "总览板与本地交互页面都提供。"
  },
  {
    id: "Q45", priority: "必须回答", category: "文件与评审",
    question: "选中方向后，是否希望继续把设计转成 App 中可真机验收的实现？",
    options: ["会，选定后继续实现", "先只做设计稿", "实现另行决定", "由你判断"],
    fallback: "设计稿先写到可实现的规格深度，是否编码后续再决定。"
  }
];

const workbook = Workbook.create();
const guide = workbook.worksheets.add("填写说明");
const form = workbook.worksheets.add("设计问卷");
const optionsSheet = workbook.worksheets.add("下拉选项（勿改）");

const colors = {
  paper: "#F3F0EB",
  card: "#FBF8F3",
  ink: "#2C2823",
  secondary: "#877F73",
  separator: "#E4DFD6",
  selection: "#E8E3DB",
  accent: "#C0603A",
  accentSoft: "#F0D8CD",
  required: "#C0603A",
  suggested: "#7F8A74",
  green: "#55745C",
  greenSoft: "#DCE8DD",
  pendingSoft: "#F4E5DD",
  white: "#FFFFFF"
};

function styleTitle(sheet, range) {
  const r = sheet.getRange(range);
  r.format.fill = colors.ink;
  r.format.font = { name: "Aptos Display", size: 22, bold: true, color: colors.paper };
  r.format.verticalAlignment = "center";
  r.format.horizontalAlignment = "left";
}

function styleHeader(range) {
  range.format.fill = colors.selection;
  range.format.font = { name: "Aptos", size: 11, bold: true, color: colors.ink };
  range.format.verticalAlignment = "center";
  range.format.wrapText = true;
  range.format.borders = {
    bottom: { style: "medium", color: colors.accent }
  };
}

// ── 填写说明 ────────────────────────────────────────────────────────────────
guide.showGridLines = false;
guide.getRange("A1:H2").merge();
guide.getRange("A1").values = [["Babel · 设计需求澄清问卷"]];
styleTitle(guide, "A1:H2");
guide.getRange("A3:H3").merge();
guide.getRange("A3").values = [["填写完成后保存这份 Excel，再告诉我即可。我会读取你的选择与补充说明，然后先给出最终执行清单，等你明确说“开始”后再制作设计稿。"]];
guide.getRange("A3:H3").format = {
  fill: colors.card,
  font: { name: "Aptos", size: 11, color: colors.secondary },
  wrapText: true,
  verticalAlignment: "center",
  borders: { bottom: { style: "thin", color: colors.separator } }
};

guide.getRange("A5:D5").merge();
guide.getRange("A5").values = [["填写进度"]];
guide.getRange("A5:D5").format = {
  fill: colors.accent,
  font: { name: "Aptos", size: 12, bold: true, color: colors.white },
  verticalAlignment: "center"
};

guide.getRange("A6:C10").values = [
  ["指标", "数值", "说明"],
  ["必须回答题目", null, "这些问题会直接改变第一稿方向"],
  ["必须回答已填写", null, "下拉选择或自由填写任一非空即算完成"],
  ["必须回答完成率", null, "建议达到 100% 后告诉我"],
  ["全部题目已填写", null, "建议题可以选择“由你判断”"]
];
guide.getRange("A6:C6").format = {
  fill: colors.selection,
  font: { name: "Aptos", size: 10, bold: true, color: colors.ink },
  verticalAlignment: "center"
};
guide.getRange("B7").formulas = [["=COUNTIF('设计问卷'!$B$6:$B$50,\"必须回答\")"]];
guide.getRange("B8").formulas = [["=COUNTIFS('设计问卷'!$B$6:$B$50,\"必须回答\",'设计问卷'!$H$6:$H$50,\"已填写\")"]];
guide.getRange("B9").formulas = [["=IF(B7=0,0,B8/B7)"]];
guide.getRange("B10").formulas = [["=COUNTIF('设计问卷'!$H$6:$H$50,\"已填写\")"]];
guide.getRange("B9").format.numberFormat = "0%";
guide.getRange("A7:C10").format = {
  fill: colors.card,
  font: { name: "Aptos", size: 10, color: colors.ink },
  verticalAlignment: "center",
  wrapText: true,
  borders: { insideHorizontal: { style: "thin", color: colors.separator } }
};
guide.getRange("B7:B10").format.font = { name: "Aptos Display", size: 16, bold: true, color: colors.accent };

guide.getRange("A12:H12").merge();
guide.getRange("A12").values = [["怎么填写"]];
guide.getRange("A12:H12").format = {
  fill: colors.ink,
  font: { name: "Aptos", size: 12, bold: true, color: colors.paper },
  verticalAlignment: "center"
};
guide.getRange("A13:H19").values = [
  ["1", "进入“设计问卷”页。", null, null, null, null, null, null],
  ["2", "E 列使用下拉选单；F 列始终可以自由补充。两列可以只填一列，也可以同时填写。", null, null, null, null, null, null],
  ["3", "如果一个下拉题想选多个答案，请在 E 列选最接近的一项，再把完整组合写在 F 列。", null, null, null, null, null, null],
  ["4", "开放题可以在 E 列选择“其他 / 由你判断”，并直接在 F 列写你的想法。", null, null, null, null, null, null],
  ["5", "G 列是“若留空，我会怎样处理”，用于减少你必须做的决定；它不是你的答案。", null, null, null, null, null, null],
  ["6", "H 列自动计算填写状态，请不要手动修改。", null, null, null, null, null, null],
  ["7", "截图或录屏可以继续放在项目文件夹内；请在对应问题的 F 列写明文件名或路径。", null, null, null, null, null, null]
];
for (let row = 13; row <= 19; row++) {
  guide.getRange(`A${row}`).format = {
    fill: colors.accentSoft,
    font: { name: "Aptos", size: 11, bold: true, color: colors.accent },
    horizontalAlignment: "center",
    verticalAlignment: "center"
  };
  guide.getRange(`B${row}:H${row}`).merge();
  guide.getRange(`B${row}:H${row}`).format = {
    fill: colors.card,
    font: { name: "Aptos", size: 11, color: colors.ink },
    wrapText: true,
    verticalAlignment: "center",
    borders: { bottom: { style: "thin", color: colors.separator } }
  };
}

guide.getRange("A21:H21").merge();
guide.getRange("A21").values = [["颜色说明"]];
guide.getRange("A21:H21").format = {
  fill: colors.ink,
  font: { name: "Aptos", size: 12, bold: true, color: colors.paper },
  verticalAlignment: "center"
};
guide.getRange("A22:B24").values = [
  ["陶土红", "必须回答"],
  ["灰绿色", "建议回答"],
  ["浅暖色输入框", "请选择或直接填写"]
];
guide.getRange("A22").format.fill = colors.accent;
guide.getRange("A23").format.fill = colors.suggested;
guide.getRange("A24").format.fill = colors.accentSoft;
guide.getRange("A22:A24").format.font = { color: colors.white, bold: true };
guide.getRange("B22:B24").format = {
  fill: colors.card,
  font: { name: "Aptos", size: 11, color: colors.ink },
  verticalAlignment: "center"
};

guide.getRange("A1:H24").format.rowHeight = 24;
guide.getRange("A1:H2").format.rowHeight = 32;
guide.getRange("A3:H3").format.rowHeight = 46;
guide.getRange("A13:H19").format.rowHeight = 38;
guide.getRange("A:A").format.columnWidth = 13;
guide.getRange("B:B").format.columnWidth = 24;
guide.getRange("C:C").format.columnWidth = 34;
guide.getRange("D:H").format.columnWidth = 12;
guide.freezePanes.freezeRows(3);

// ── 下拉选项 ────────────────────────────────────────────────────────────────
optionsSheet.showGridLines = false;
optionsSheet.getRange("A1:C1").values = [["问题编号", "选项序号", "下拉选项"]];
styleHeader(optionsSheet.getRange("A1:C1"));
const validationRanges = new Map();
let optionRow = 2;
for (const item of questions) {
  const start = optionRow;
  const rows = item.options.map((option, index) => [item.id, index + 1, option]);
  optionsSheet.getRange(`A${optionRow}:C${optionRow + rows.length - 1}`).values = rows;
  optionRow += rows.length;
  validationRanges.set(item.id, { start, end: optionRow - 1 });
}
optionsSheet.getRange(`A2:C${optionRow - 1}`).format = {
  font: { name: "Aptos", size: 10, color: colors.ink },
  fill: colors.card,
  verticalAlignment: "center",
  borders: { insideHorizontal: { style: "thin", color: colors.separator } }
};
optionsSheet.getRange("A:A").format.columnWidth = 12;
optionsSheet.getRange("B:B").format.columnWidth = 10;
optionsSheet.getRange("C:C").format.columnWidth = 34;
optionsSheet.freezePanes.freezeRows(1);

// ── 设计问卷 ────────────────────────────────────────────────────────────────
form.showGridLines = false;
form.getRange("A1:H2").merge();
form.getRange("A1").values = [["Babel · 设计需求澄清问卷"]];
styleTitle(form, "A1:H2");
form.getRange("A3:H3").merge();
form.getRange("A3").values = [["E 列选下拉项，F 列自由补充；可只填一列，也可同时填写。多选题请在 E 列选最接近的一项，再在 F 列补充完整组合。"]];
form.getRange("A3:H3").format = {
  fill: colors.card,
  font: { name: "Aptos", size: 11, color: colors.secondary },
  wrapText: true,
  verticalAlignment: "center",
  borders: { bottom: { style: "thin", color: colors.separator } }
};

form.getRange("A5:H5").values = [[
  "编号", "优先级", "分类", "问题", "下拉选择", "补充说明 / 直接填写", "若留空，我的默认处理", "填写状态"
]];
styleHeader(form.getRange("A5:H5"));

const formRows = questions.map(item => [
  item.id, item.priority, item.category, item.question, "", "", item.fallback, null
]);
form.getRange("A6:H50").values = formRows;
form.getRange("H6:H50").formulas = questions.map((_, index) => {
  const row = index + 6;
  return [`=IF(OR(E${row}<>\"\",F${row}<>\"\"),\"已填写\",\"待填写\")`];
});

form.getRange("A6:H50").format = {
  font: { name: "Aptos", size: 10, color: colors.ink },
  verticalAlignment: "top",
  wrapText: true,
  borders: { insideHorizontal: { style: "thin", color: colors.separator } }
};
form.getRange("A6:C50").format.fill = colors.card;
form.getRange("D6:D50").format.fill = colors.paper;
form.getRange("E6:F50").format.fill = colors.accentSoft;
form.getRange("G6:G50").format = {
  fill: colors.selection,
  font: { name: "Aptos", size: 10, italic: true, color: colors.secondary },
  verticalAlignment: "top",
  wrapText: true,
  borders: { insideHorizontal: { style: "thin", color: colors.separator } }
};
form.getRange("H6:H50").format = {
  fill: colors.card,
  font: { name: "Aptos", size: 10, bold: true, color: colors.secondary },
  horizontalAlignment: "center",
  verticalAlignment: "center",
  borders: { insideHorizontal: { style: "thin", color: colors.separator } }
};

for (let index = 0; index < questions.length; index++) {
  const row = index + 6;
  const item = questions[index];
  const optionRange = validationRanges.get(item.id);
  form.getRange(`E${row}`).dataValidation = {
    rule: {
      type: "list",
      formula1: `'下拉选项（勿改）'!$C$${optionRange.start}:$C$${optionRange.end}`
    }
  };
  form.getRange(`A${row}`).format = {
    fill: item.priority === "必须回答" ? colors.accentSoft : colors.card,
    font: { name: "Aptos", size: 10, bold: true, color: item.priority === "必须回答" ? colors.accent : colors.ink },
    horizontalAlignment: "center",
    verticalAlignment: "center",
    borders: { bottom: { style: "thin", color: colors.separator } }
  };
  form.getRange(`B${row}`).format = {
    fill: item.priority === "必须回答" ? colors.required : colors.suggested,
    font: { name: "Aptos", size: 10, bold: true, color: colors.white },
    horizontalAlignment: "center",
    verticalAlignment: "center",
    borders: { bottom: { style: "thin", color: colors.separator } }
  };
}

form.getRange("H6:H50").conditionalFormats.add("containsText", {
  text: "已填写",
  format: { fill: colors.greenSoft, font: { bold: true, color: colors.green } }
});
form.getRange("H6:H50").conditionalFormats.add("containsText", {
  text: "待填写",
  format: { fill: colors.pendingSoft, font: { bold: true, color: colors.accent } }
});

form.getRange("A:A").format.columnWidth = 8;
form.getRange("B:B").format.columnWidth = 13;
form.getRange("C:C").format.columnWidth = 17;
form.getRange("D:D").format.columnWidth = 49;
form.getRange("E:E").format.columnWidth = 29;
form.getRange("F:F").format.columnWidth = 44;
form.getRange("G:G").format.columnWidth = 40;
form.getRange("H:H").format.columnWidth = 13;
form.getRange("A1:H2").format.rowHeight = 32;
form.getRange("A3:H3").format.rowHeight = 42;
form.getRange("A5:H5").format.rowHeight = 32;
form.getRange("A6:H50").format.rowHeight = 68;
form.getRange("A6:H6").format.rowHeight = 112;
form.getRange("A9:H9").format.rowHeight = 76;
form.getRange("A16:H16").format.rowHeight = 78;
form.freezePanes.freezeRows(5);
form.freezePanes.freezeColumns(4);

const outputPath = path.resolve("Design/Babel-设计需求澄清问卷.xlsx");
const previewDir = path.resolve("Design/_build/previews");
await fs.mkdir(previewDir, { recursive: true });

const guidePreview = await workbook.render({
  sheetName: "填写说明",
  range: "A1:H24",
  scale: 1.2,
  format: "png"
});
await fs.writeFile(
  path.join(previewDir, "填写说明.png"),
  new Uint8Array(await guidePreview.arrayBuffer())
);

const formPreview = await workbook.render({
  sheetName: "设计问卷",
  range: "A1:H15",
  scale: 1.0,
  format: "png"
});
await fs.writeFile(
  path.join(previewDir, "设计问卷-前10题.png"),
  new Uint8Array(await formPreview.arrayBuffer())
);

try {
  const output = await SpreadsheetFile.exportXlsx(workbook);
  await output.save(outputPath);
} catch (error) {
  console.error(`EXPORT_ERROR_NAME=${error?.name ?? "Unknown"}`);
  console.error(`EXPORT_ERROR_MESSAGE=${error?.message ?? String(error)}`);
  process.exitCode = 2;
  process.exit();
}

const inspect = await workbook.inspect({
  kind: "table",
  range: "设计问卷!A1:H15",
  include: "values,formulas",
  tableMaxRows: 15,
  tableMaxCols: 8,
  maxChars: 9000
});
console.log(inspect.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "final formula error scan"
});
console.log(errors.ndjson);
console.log(`OUTPUT=${outputPath}`);
