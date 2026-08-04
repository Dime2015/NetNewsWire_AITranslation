const state = {
  direction: "a",
  screen: "home",
  mode: "starred",
  theme: "light",
  repeatSource: true,
  softTranslate: true,
  largeType: false,
};

const query = new URLSearchParams(window.location.search);
["direction", "screen", "mode", "theme"].forEach(key => {
  if (query.has(key)) state[key] = query.get(key);
});
["repeatSource", "softTranslate", "largeType"].forEach(key => {
  if (query.has(key)) state[key] = query.get(key) !== "false";
});
if (query.get("export") === "1") document.body.classList.add("export-1");
if (query.get("export") === "3") document.body.classList.add("export-3");
if (query.get("export") === "long") document.body.classList.add("export-long");

const directionCopy = {
  a: {
    code: "方向 A",
    title: "安静的编辑排版",
    summary: "不靠插图做品牌，用排版秩序、纸张层次和克制的陶土色建立识别。",
  },
  b: {
    code: "方向 B",
    title: "图像只留在门口",
    summary: "保留现有浮世绘的情绪资产，但只让图像出现在入口、空状态和引导时刻。",
  },
  c: {
    code: "方向 C · 推荐",
    title: "译者的校样桌",
    summary: "以校样线、批注、裁切标与双语结构形成全球化、编辑感更强的产品身份。",
  },
};

const screenModes = {
  home: [
    ["starred", "星标"],
    ["unread", "未读"],
    ["all", "全部"],
  ],
  list: [
    ["rest", "顶部"],
    ["docked", "下滑停靠"],
  ],
  article: [
    ["original", "原文"],
    ["translating", "翻译中"],
    ["translated", "已翻译"],
    ["docked", "下滑停靠"],
  ],
  settings: [["default", "默认"]],
  language: [["default", "默认"]],
  feed: [["default", "默认"]],
  longimage: [
    ["lightdoc", "浅色长图"],
    ["darkdoc", "深色长图"],
  ],
  icons: [["all", "Light / Dark / Mono"]],
  stress: [
    ["rows", "文章行"],
    ["type", "混排与大字"],
  ],
};

const notes = {
  home: {
    title: "主页：阅读意图先于订阅结构",
    body: "星标、未读、全部仍然是一级入口；视觉上不把它们做成三张同权重的大卡片，而是保持轻量、可扫描。",
    bullets: [
      "默认呈现用户上次使用的模式，不强制回到“未读”。",
      "全局目标语言只在入口以一句自然语言交代，不制造持续的“翻译状态”。",
      "B 方向的图像到列表开始前自然退场，内容区保持安静。",
    ],
  },
  list: {
    title: "文章列表：标题第一，摘要第三",
    body: "摘要保留，但退到第三层级；已读行使用 68% 的整体强度，仍保持可读，而不是接近不可见。",
    bullets: [
      "缩略图固定 70pt，缺图时直接让标题占满，不放占位图。",
      "停靠标题使用短交叉淡入，不做标题“飞行”。",
      "“重复订阅源名”开关用于比较单源列表的冗余感。",
    ],
  },
  article: {
    title: "文章内容：把翻译当作阅读状态",
    body: "原文、翻译中、已翻译是同一篇内容的三个状态，不使用长期的“已翻译”徽章。",
    bullets: [
      "标题从正文交接到毛玻璃栏采用两层交叉淡化，避免中间形变。",
      "控制板只保留阅读、翻译、长图、星标四个高频动作，更多动作收进“…”菜单。",
      "目标语言文章的翻译键可用左侧开关比较“弱化”和“保持常规”。",
    ],
  },
  settings: {
    title: "设置主页：从系统清单变成产品结构",
    body: "把翻译与语言放到第一个产品级分组，阅读、订阅与支持依次后置，减少当前页面的大段空白。",
    bullets: [
      "仍使用 iOS 熟悉的设置行，不引入陌生导航。",
      "每行用一句副文案交代影响范围。",
      "全局设置不替代单订阅源覆盖项。",
    ],
  },
  language: {
    title: "翻译与语言：一个明确的默认目标",
    body: "最重要的设置不是“开关翻译”，而是“我用什么语言阅读”。源语言继续自动识别。",
    bullets: [
      "默认目标语言为全 App 单一值。",
      "翻译失败、进行中可以提示；完成后不持续贴标签。",
      "保留术语、人名与链接的偏好设置入口。",
    ],
  },
  feed: {
    title: "单个订阅源：只保留覆盖项",
    body: "订阅源设置不重复全局选项，只显示这个源确实可以覆盖的语言、全文抓取和列表展示规则。",
    bullets: [
      "默认继承全局目标语言。",
      "可以为特定外语源单独关闭自动翻译。",
      "危险操作独立成组并置底。",
    ],
  },
  longimage: {
    title: "长图：从系统截图变成可辨认的出版物",
    body: "导出长图是 App 唯一会离开产品环境传播的界面，因此品牌信息、排版和来源必须更完整。",
    bullets: [
      "标题、来源、正文和引文拥有明确层级。",
      "底部保留 Babel 标识、订阅源与生成时间，不喧宾夺主。",
      "深色文章可输出深色长图，不强制转成白纸。",
    ],
  },
  icons: {
    title: "App 图标：每个方向都有完整模式",
    body: "三套图标不是只换背景色，而是在同一个核心构形下分别为浅色、深色、单色调整对比。",
    bullets: [
      "A：B 与“译”的编辑字标，最克制。",
      "B：门洞与远方，延续“图像只在入口”的概念。",
      "C：双字母与校样裁切标，产品特征最强。",
    ],
  },
  stress: {
    title: "压力测试：先让最难的内容成立",
    body: "这里集中展示无图无摘要、三行中文、CJK/Latin 混排、双语相邻和大字号状态。",
    bullets: [
      "标题不会因为固定行高被裁切。",
      "中英文共享节奏，但不用完全相同的字重。",
      "窄屏与动态字体优先牺牲摘要行数，不牺牲标题可读性。",
    ],
  },
};

function statusBar() {
  return `
    <div class="statusbar">
      <span>9:41</span>
      <span class="statusbar__icons">▮▮▮  Wi‑Fi <i class="statusbar__battery"></i></span>
    </div>`;
}

function appShell(content, extra = "") {
  return `<div class="app ${state.largeType ? "is-large-type" : ""} ${extra}">
    ${statusBar()}${content}
  </div>`;
}

function bottomBar(active = "home") {
  return `<nav class="bottom-bar" aria-label="主导航">
    <button class="${active === "home" ? "is-active" : ""}">⌂<small>主页</small></button>
    <button class="${active === "saved" ? "is-active" : ""}">◇<small>稍后读</small></button>
    <button class="${active === "search" ? "is-active" : ""}">⌕<small>搜索</small></button>
    <button class="${active === "settings" ? "is-active" : ""}">⚙︎<small>设置</small></button>
  </nav>`;
}

function homeScreen() {
  const labels = {
    starred: ["星标", "18 篇", "为你保留的文章"],
    unread: ["未读", "47 篇", "继续今天的阅读"],
    all: ["全部", "1,284 篇", "浏览完整资料库"],
  };
  const current = labels[state.mode] || labels.starred;
  return appShell(`
    <div class="screen-scroll">
      <div class="nav-row"><button class="nav-button">＋</button><span class="nav-title">Babel</span><button class="nav-button">⌕</button></div>
      <section class="hero">
        <div class="hero__kicker">YOUR READING LANGUAGE · 简体中文</div>
        <h1>${current[2]}</h1>
        <p>世界的内容，以你的阅读语言安静抵达。</p>
        <div class="translation-line">English · 日本語 · Français <span></span> 简体中文</div>
      </section>
      <div class="mode-tabs">
        ${["starred","unread","all"].map(mode => `
          <button class="mode-tab ${state.mode === mode ? "is-active" : ""}" data-mode="${mode}">
            <b>${labels[mode][0]}</b><span>${labels[mode][1]}</span>
          </button>`).join("")}
      </div>
      <div class="section-label"><h2>订阅源</h2><span>按更新排序</span></div>
      <ul class="feed-list">
        ${[
          ["FT", "Financial Times", "金融与全球商业", "12"],
          ["N", "The New Yorker", "文化、观点与长篇", "8"],
          ["日", "日経クロステック", "技术与产业", "5"],
          ["L", "Lawfare", "安全、法律与政策", "3"],
          ["S", "Scope of Work", "工作与组织", "2"],
        ].map(x => `<li class="feed-row"><span class="feed-mark">${x[0]}</span><span><b>${x[1]}</b><small>${x[2]}</small></span><span class="count">${x[3]}</span></li>`).join("")}
      </ul>
    </div>
    ${bottomBar("home")}
  `);
}

const articles = [
  {
    source: "Financial Times",
    title: "全球供应链正在学习如何与不确定性共处",
    summary: "企业不再只追求最低成本，而是重新计算韧性、速度与地缘风险。",
    time: "12 分钟前",
    image: true,
  },
  {
    source: "The New Yorker",
    title: "What We Lose When Every Place Starts to Look the Same",
    summary: "A journey through the quiet disappearance of local texture.",
    time: "今天 08:40",
    image: true,
  },
  {
    source: "日経クロステック",
    title: "生成 AI 時代に、読解という行為はどう変わるのか",
    summary: "翻訳と要約が日常化した後、人は何を自分で読むのか。",
    time: "昨天",
    image: false,
  },
  {
    source: "Financial Times",
    title: "一封来自布鲁塞尔的短信",
    summary: "短文也应当保持完整、轻盈，而不是被迫填满固定高度。",
    time: "周二",
    image: false,
    read: true,
  },
];

function articleRow(item, index, forceSource) {
  const source = state.repeatSource || forceSource || index === 0;
  return `<li class="article-row ${item.image ? "" : "no-image"} ${item.read ? "is-read" : ""}">
    <div>
      ${source ? `<div class="article-source"><i></i>${item.source}</div>` : ""}
      <h2>${item.title}</h2>
      <p>${item.summary}</p>
      <time>${item.time} · ${index % 2 ? "7" : "5"} 分钟</time>
    </div>
    ${item.image ? `<div class="thumbnail"></div>` : ""}
  </li>`;
}

function listScreen() {
  const docked = state.mode === "docked";
  return appShell(`
    <div class="screen-scroll">
      <div class="nav-row"><button class="nav-button">‹</button><span></span><button class="nav-button">•••</button></div>
      <header class="list-header ${docked ? "is-docked" : ""}">
        <span class="list-header__mark">FEED · ENGLISH → 简体中文</span>
        <h1>Financial Times</h1>
        <p>82 篇文章 · 12 篇未读 · 默认翻译为简体中文</p>
      </header>
      <ul class="article-list">
        ${articles.map((item, i) => articleRow({...item, source: "Financial Times"}, i, false)).join("")}
      </ul>
    </div>
  `);
}

function translationState() {
  if (state.mode === "translating") {
    return `<div class="translation-state"><b>正在准备你的阅读版本</b>已完成 6 / 10 个段落。你可以先阅读已经完成的部分。<div class="progress-line"></div></div>`;
  }
  if (state.mode === "original") {
    return `<div class="translation-state"><b>原文 · English</b>目标阅读语言为简体中文。翻译只在你需要时出现。</div>`;
  }
  return "";
}

function controlBoard() {
  const soft = state.softTranslate && state.mode === "original" ? "is-soft" : "";
  return `<nav class="control-board" aria-label="文章操作">
    <button>◐<small>阅读</small></button>
    <button class="${soft}">译<small>翻译</small></button>
    <button>▧<small>长图</small></button>
    <button>☆<small>星标</small></button>
    <button>•••<small>更多</small></button>
  </nav>`;
}

function articleScreen() {
  const docked = state.mode === "docked";
  const translated = state.mode === "translated" || docked;
  const title = translated
    ? "全球供应链正在学习如何与不确定性共处"
    : "Global Supply Chains Are Learning to Live With Uncertainty";
  return appShell(`
    <header class="article-nav ${docked ? "is-docked" : ""}">
      <button class="nav-button">‹</button>
      <div class="dock-title">${title}</div>
      <button class="nav-button">•••</button>
    </header>
    <article class="article-body ${docked ? "is-docked" : ""}">
      <h1 class="article-title">${title}</h1>
      <p class="article-deck">${translated ? "效率不再是唯一目标。企业正在重新权衡成本、速度、冗余与地缘政治风险。" : "Efficiency is no longer the only goal. Companies are recalculating cost, speed, redundancy and geopolitical risk."}</p>
      <div class="article-meta"><b>Financial Times</b><span>2026 年 7 月 31 日</span><span>8 分钟</span></div>
      ${translationState()}
      <div class="article-copy">
        <p class="dropcap">${translated ? "在过去三十年里，全球供应链被设计成一台追求效率的机器。库存被压缩，路线被优化，每一个多余环节都被视为成本。" : "For three decades, global supply chains were designed as machines for efficiency. Inventories were compressed, routes optimised and every redundant step treated as a cost."}</p>
        <p>${translated ? "如今，企业没有放弃效率，但它们开始为不确定性付费。更近的供应商、更大的库存与第二套方案，正从浪费变成保险。" : "Companies have not abandoned efficiency. But they are beginning to pay for uncertainty: nearer suppliers, larger inventories and second options are turning from waste into insurance."}</p>
        <p>${translated ? "这并不是去全球化，而是一种更复杂的全球化。网络没有消失，只是学会了保留余地。" : "This is not deglobalisation. It is a more complicated globalisation: the network remains, but it is learning to leave room for failure."}</p>
      </div>
    </article>
    ${controlBoard()}
  `);
}

function settingsRow(icon, title, sub, value = "›") {
  return `<div class="settings-row">
    <span class="settings-row__icon">${icon}</span>
    <span><b>${title}</b>${sub ? `<small>${sub}</small>` : ""}</span>
    <span class="settings-row__value">${value}</span>
  </div>`;
}

function settingsScreen() {
  return appShell(`
    <div class="screen-scroll">
      <div class="nav-row"><span></span><span class="nav-title"></span><button class="nav-button">完成</button></div>
      <h1 class="settings-title">设置</h1>
      <section class="settings-group">
        <h2>跨语言阅读</h2>
        <div class="settings-card">
          ${settingsRow("译", "翻译与语言", "阅读语言、自动翻译与术语", "简体中文 ›")}
          ${settingsRow("文", "阅读外观", "字体、字号与行距")}
        </div>
      </section>
      <section class="settings-group">
        <h2>内容与订阅</h2>
        <div class="settings-card">
          ${settingsRow("◉", "订阅与同步", "账户、刷新与后台更新")}
          ${settingsRow("▤", "文章与列表", "摘要、缩略图与已读行为")}
          ${settingsRow("⇩", "导出与分享", "长图、水印与默认外观")}
        </div>
      </section>
      <section class="settings-group">
        <h2>Babel</h2>
        <div class="settings-card">
          ${settingsRow("?", "帮助与反馈", "")}
          ${settingsRow("i", "关于 Babel", "版本 1.0")}
        </div>
      </section>
    </div>
    ${bottomBar("settings")}
  `);
}

function languageScreen() {
  return appShell(`
    <div class="screen-scroll">
      <div class="nav-row"><button class="nav-button">‹</button><span class="nav-title">翻译与语言</span><span class="nav-button"></span></div>
      <section class="language-hero">
        <small>全 App 默认阅读语言</small>
        <h2>简体中文</h2>
        <div class="language-route"><span>自动识别源语言</span><i></i><b>简体中文</b></div>
      </section>
      <section class="settings-group">
        <h2>默认行为</h2>
        <div class="settings-card">
          <div class="settings-row"><span class="settings-row__icon">自</span><span><b>自动翻译外语文章</b><small>打开文章后开始准备阅读版本</small></span><span class="switch"></span></div>
          ${settingsRow("同", "目标语言文章", "不重复翻译，只保留手动入口", "弱化 ›")}
          ${settingsRow("原", "保留原文入口", "随时在文章内切换", "开启 ›")}
        </div>
      </section>
      <section class="settings-group">
        <h2>译文偏好</h2>
        <div class="settings-card">
          ${settingsRow("A", "人名与专有名词", "首次出现时保留原文", "›")}
          ${settingsRow("链", "链接与脚注", "保持原始地址与编号", "›")}
          ${settingsRow("册", "个人术语表", "0 个自定义词条", "›")}
        </div>
      </section>
    </div>
  `);
}

function feedScreen() {
  return appShell(`
    <div class="screen-scroll">
      <div class="nav-row"><button class="nav-button">‹</button><span class="nav-title">订阅源设置</span><span class="nav-button"></span></div>
      <div class="language-hero">
        <small>FINANCIAL TIMES</small>
        <h2>金融与全球商业</h2>
        <div class="language-route"><span>English</span><i></i><b>简体中文</b></div>
      </div>
      <section class="settings-group">
        <h2>翻译覆盖</h2>
        <div class="settings-card">
          ${settingsRow("译", "目标语言", "跟随全 App 默认设置", "简体中文 ›")}
          <div class="settings-row"><span class="settings-row__icon">自</span><span><b>自动翻译</b><small>打开文章时自动准备</small></span><span class="switch"></span></div>
        </div>
      </section>
      <section class="settings-group">
        <h2>内容</h2>
        <div class="settings-card">
          ${settingsRow("全", "全文获取", "可用时优先展示完整正文", "自动 ›")}
          ${settingsRow("摘", "列表摘要", "保留一至两行", "显示 ›")}
          ${settingsRow("铃", "新文章通知", "", "关闭 ›")}
        </div>
      </section>
      <section class="settings-group">
        <h2>管理</h2>
        <div class="settings-card">
          ${settingsRow("⌁", "编辑名称与文件夹", "", "›")}
          ${settingsRow("×", "取消订阅", "", '<span style="color:var(--accent)">取消</span>')}
        </div>
      </section>
    </div>
  `);
}

function longImageScreen() {
  return appShell(`
    <div class="longimage-wrap">
      <article class="longimage-sheet">
        <div class="longimage-brand"><span><i class="mini-logo">B</i>BABEL READING COPY</span><span>简体中文</span></div>
        <h1 class="longimage-title">全球供应链正在学习如何与不确定性共处</h1>
        <p class="longimage-sub">效率不再是唯一目标。企业正在重新权衡成本、速度、冗余与地缘政治风险。</p>
        <div class="article-meta"><b>Financial Times</b><span>2026.07.31</span><span>8 分钟</span></div>
        <div class="longimage-copy">
          <p>在过去三十年里，全球供应链被设计成一台追求效率的机器。库存被压缩，路线被优化，每一个多余环节都被视为成本。</p>
          <p>如今，企业没有放弃效率，但它们开始为不确定性付费。更近的供应商、更大的库存与第二套方案，正从浪费变成保险。</p>
          <p class="longimage-quote">“最便宜的路径，不一定是最能抵达终点的路径。”</p>
          <p>这并不是去全球化，而是一种更复杂的全球化。网络没有消失，只是学会了保留余地。</p>
          <p>对读者而言，这场变化也意味着一个更难回答的问题：当世界不再追求单一效率，我们应当如何理解成本？</p>
        </div>
        <footer class="longimage-footer"><span><i class="mini-logo">B</i>分享自 Babel</span><span>原文：ft.com · 译文为阅读辅助</span></footer>
      </article>
    </div>
  `);
}

function iconsScreen() {
  const dir = state.direction;
  const glyph = dir === "a" ? "B" : dir === "b" ? "⌁" : "B译";
  return appShell(`
    <div class="screen-scroll">
      <div class="nav-row"><button class="nav-button">‹</button><span class="nav-title">App 图标</span><span class="nav-button"></span></div>
      <section class="icon-showcase">
        <h1>${directionCopy[dir].title}</h1>
        <p>同一核心构形，为系统的浅色、深色和单色模式分别校准。</p>
        <div class="icon-grid">
          ${["light","dark","mono"].map(mode => `<div class="icon-card"><div class="app-icon ${dir} icon-${mode}"><span>${glyph}</span></div><small>${mode.toUpperCase()}</small></div>`).join("")}
        </div>
        <div class="section-label" style="padding-left:0;padding-right:0;margin-top:16px"><h2>小尺寸检查</h2><span>60 / 40 / 29 pt</span></div>
        <div style="display:flex;align-items:end;gap:18px;padding:12px 4px">
          ${[60,40,29].map(size => `<div class="app-icon ${dir} icon-light" style="width:${size}px;border-radius:22%"><span style="font-size:${Math.max(11,size*.38)}px">${glyph}</span></div>`).join("")}
        </div>
        <div class="translation-state" style="margin-top:18px"><b>推荐判断</b>${dir === "c" ? "C 的裁切标在 29pt 仍然可辨认，也最像“跨语言编辑工具”。" : dir === "b" ? "B 的门洞意象最亲和，但小尺寸时需要减少内部细节。" : "A 最安静成熟，但与普通文字工具的区分度较弱。"}</div>
      </section>
    </div>
  `);
}

function stressScreen() {
  const stressArticles = [
    { source: "短行 · 无图无摘要", title: "一封来自布鲁塞尔的短信", summary: "", time: "2 分钟前", image: false },
    { source: "三行中文标题", title: "为什么最有效率的全球供应链，反而最难抵御下一次意外", summary: "标题优先保留，摘要先让位。", time: "今天", image: false },
    { source: "CJK / Latin 混排", title: "OpenAI、半导体与「规模定律」之后的产业选择", summary: "English names 与中文标点共享同一视觉节奏。", time: "昨天", image: true },
    { source: "English", title: "The Quiet Politics of Reading Across Languages", summary: "Adjacent language rows keep distinct texture without changing density.", time: "周二", image: false },
  ];
  return appShell(`
    <div class="screen-scroll">
      <div class="nav-row"><button class="nav-button">‹</button><span class="nav-title">压力测试</span><span class="nav-button"></span></div>
      <section class="stress-sheet">
        <h1>内容边界</h1>
        <p>402pt 主画布 · 当前${state.largeType ? "动态字体 +2" : "标准字号"} · ${state.theme === "dark" ? "深色" : "浅色"}</p>
        <ul class="article-list" style="padding:0">
          ${stressArticles.map((item, i) => articleRow(item, i, true)).join("")}
        </ul>
        <span class="stress-tag">窄屏策略</span>
        <div class="translation-state" style="margin-top:5px"><b>优先级</b>标题完整性 ＞ 来源与时间 ＞ 摘要行数 ＞ 缩略图。大字号下摘要可降为一行。</div>
      </section>
    </div>
  `);
}

function renderScreen() {
  const root = document.getElementById("deviceScreen");
  root.dataset.direction = state.direction;
  root.dataset.theme = state.theme;
  const renderers = {
    home: homeScreen,
    list: listScreen,
    article: articleScreen,
    settings: settingsScreen,
    language: languageScreen,
    feed: feedScreen,
    longimage: longImageScreen,
    icons: iconsScreen,
    stress: stressScreen,
  };
  root.innerHTML = renderers[state.screen]();
  root.querySelectorAll("[data-mode]").forEach(button => {
    button.addEventListener("click", () => {
      state.mode = button.dataset.mode;
      syncControls();
      render();
    });
  });
}

function renderNotes() {
  const item = notes[state.screen];
  document.getElementById("screenNotes").innerHTML = `
    <p class="eyebrow">${directionCopy[state.direction].code} / ${state.screen.toUpperCase()}</p>
    <h3>${item.title}</h3>
    <p>${item.body}</p>
    <ul>${item.bullets.map(x => `<li>${x}</li>`).join("")}</ul>
  `;
}

function syncControls() {
  document.querySelectorAll("#directionControl button").forEach(button => {
    button.classList.toggle("is-active", button.dataset.value === state.direction);
  });
  document.querySelectorAll("#themeControl button").forEach(button => {
    button.classList.toggle("is-active", button.dataset.value === state.theme);
  });
  document.getElementById("screenControl").value = state.screen;
  document.getElementById("repeatSource").checked = state.repeatSource;
  document.getElementById("softTranslate").checked = state.softTranslate;
  document.getElementById("largeType").checked = state.largeType;

  const modeControl = document.getElementById("modeControl");
  modeControl.innerHTML = screenModes[state.screen]
    .map(([value, label]) => `<option value="${value}">${label}</option>`)
    .join("");
  if (!screenModes[state.screen].some(([value]) => value === state.mode)) {
    state.mode = screenModes[state.screen][0][0];
  }
  modeControl.value = state.mode;

  const copy = directionCopy[state.direction];
  document.getElementById("directionCode").textContent = copy.code;
  document.getElementById("directionTitle").textContent = copy.title;
  document.getElementById("directionSummary").textContent = copy.summary;
}

function render() {
  syncControls();
  renderScreen();
  renderNotes();
}

document.getElementById("directionControl").addEventListener("click", event => {
  const button = event.target.closest("button[data-value]");
  if (!button) return;
  state.direction = button.dataset.value;
  render();
});

document.getElementById("themeControl").addEventListener("click", event => {
  const button = event.target.closest("button[data-value]");
  if (!button) return;
  state.theme = button.dataset.value;
  render();
});

document.getElementById("screenControl").addEventListener("change", event => {
  state.screen = event.target.value;
  state.mode = screenModes[state.screen][0][0];
  render();
});

document.getElementById("modeControl").addEventListener("change", event => {
  state.mode = event.target.value;
  render();
});

["repeatSource", "softTranslate", "largeType"].forEach(id => {
  document.getElementById(id).addEventListener("change", event => {
    state[id] = event.target.checked;
    render();
  });
});

document.addEventListener("keydown", event => {
  const key = event.key.toLowerCase();
  if (["a", "b", "c"].includes(key)) state.direction = key;
  if (key === "d") state.theme = state.theme === "light" ? "dark" : "light";
  if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
    const options = screenModes[state.screen].map(([value]) => value);
    const current = options.indexOf(state.mode);
    const offset = event.key === "ArrowRight" ? 1 : -1;
    state.mode = options[(current + offset + options.length) % options.length];
  }
  render();
});

render();
