const icons = {
  home: '<svg class="babel-icon babel-icon--solid" viewBox="0 0 24 24"><path d="M3 10.5 12 3l9 7.5v9a1.5 1.5 0 0 1-1.5 1.5H15v-7H9v7H4.5A1.5 1.5 0 0 1 3 19.5z"/></svg>',
  search: '<svg class="babel-icon" viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/></svg>',
  bookmark: '<svg class="babel-icon" viewBox="0 0 24 24"><path d="M6 4.5A1.5 1.5 0 0 1 7.5 3h9A1.5 1.5 0 0 1 18 4.5V21l-6-4-6 4z"/></svg>',
  settings: '<svg class="babel-icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="3.2"/><path d="M19 13.5v-3l-2.1-.6a7 7 0 0 0-.8-1.8l1.1-1.9-2.1-2.1-1.9 1.1a7 7 0 0 0-1.8-.8L10.5 2h-3l-.6 2.1a7 7 0 0 0-1.8.8L3.2 3.8 1.1 5.9l1.1 1.9a7 7 0 0 0-.8 1.8L0 10.5v3l2.1.6a7 7 0 0 0 .8 1.8l-1.1 1.9 2.1 2.1 1.9-1.1a7 7 0 0 0 1.8.8l.9 2.4h3l.6-2.1a7 7 0 0 0 1.8-.8l1.9 1.1 2.1-2.1-1.1-1.9a7 7 0 0 0 .8-1.8z" transform="translate(2) scale(.83)"/></svg>',
  back: '<svg class="babel-icon" viewBox="0 0 24 24"><path d="m15 5-7 7 7 7"/></svg>',
  more: '<svg class="babel-icon" viewBox="0 0 24 24"><circle cx="5" cy="12" r="1.3" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.3" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1.3" fill="currentColor" stroke="none"/></svg>',
  reader: '<svg class="babel-icon" viewBox="0 0 24 24"><path d="M4 5.5h16M4 10h16M4 14.5h10M4 19h12"/></svg>',
  translate: '<svg class="babel-icon" viewBox="0 0 24 24"><path d="M4 5h9M8.5 3v2M6 7c1.2 3.3 3.3 5.7 6.5 7.3M11.5 7c-1 3-3.2 5.7-6.5 8M14 20l3.5-9 3.5 9M15.3 17h4.4"/></svg>',
  image: '<svg class="babel-icon" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="8.5" cy="9" r="1.5"/><path d="m5 18 4.5-4 3.5 3 3.5-4 3.5 5"/></svg>',
  star: '<svg class="babel-icon" viewBox="0 0 24 24"><path d="m12 3 2.7 5.5 6.1.9-4.4 4.3 1 6.1-5.4-2.9-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z"/></svg>',
  info: '<svg class="babel-icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5h.01"/></svg>',
  sparkle: '<svg class="babel-icon" viewBox="0 0 24 24"><path d="m12 3 1.4 4.1L18 9l-4.6 1.9L12 15l-1.4-4.1L6 9l4.6-1.9zM18.5 15l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"/></svg>',
  hide: '<svg class="babel-icon" viewBox="0 0 24 24"><path d="M3 3l18 18M10.6 10.7A2 2 0 0 0 13.4 13.5M9.8 5.2A11.7 11.7 0 0 1 12 5c5.5 0 9 7 9 7a15 15 0 0 1-2.3 3.2M6.2 6.3C4.1 7.7 3 12 3 12s3.5 7 9 7c1 0 2-.2 2.8-.5"/></svg>',
  hand: '<svg class="babel-icon" viewBox="0 0 24 24"><path d="M7 11V5.5a1.5 1.5 0 0 1 3 0V10M10 10V4.5a1.5 1.5 0 0 1 3 0V10M13 10V5.5a1.5 1.5 0 0 1 3 0V11M16 11V8a1.5 1.5 0 0 1 3 0v6c0 4.2-2.8 7-7 7h-1c-2.2 0-3.6-1-5-2.8L3.5 15a1.5 1.5 0 0 1 2.3-1.9L8 15"/></svg>',
  chevron: '<svg class="babel-icon" viewBox="0 0 24 24"><path d="m9 5 7 7-7 7"/></svg>'
};

const state = { screen: 'home', theme: 'light' };
const params = new URLSearchParams(location.search);
if (params.has('screen')) state.screen = params.get('screen');
if (params.has('theme')) state.theme = params.get('theme');
if (params.get('export') === '1') document.body.classList.add('export');

const status = () => '<div class="babel-status"><span>9:41</span><span class="babel-status__right">▮▮▮ Wi‑Fi <i class="babel-battery"></i></span></div>';

const bottomDock = active => `<nav class="babel-bottom-dock" aria-label="主导航">
  <button class="${active === 'home' ? 'is-active' : ''}" aria-label="主页">${icons.home}<small>主页</small></button>
  <button aria-label="搜索">${icons.search}<small>搜索</small></button>
  <button aria-label="稍后读">${icons.bookmark}<small>稍后读</small></button>
  <button class="${active === 'settings' ? 'is-active' : ''}" aria-label="设置">${icons.settings}<small>设置</small></button>
</nav>`;

function home() {
  const feeds = [['FT','Financial Times','金融与全球商业','12'],['N','The New Yorker','文化、观点与长篇','8'],['日','日経クロステック','技术与产业','5'],['L','Lawfare','安全、法律与政策','3'],['S','Scope of Work','工作与组织','2']];
  return `${status()}<section class="babel-top-shell"><nav class="babel-nav"><button>＋</button><b class="babel-wordmark">Babel</b><button>${icons.search}</button></nav><div class="babel-language-pill">READ IN · 简体中文</div><div class="babel-hero"><p class="babel-hero__eyebrow">YOUR READING SPACE</p><h1>用自己的语言，<br>读世界的内容。</h1><p>翻译安静地发生，阅读仍然是主角。</p></div><div class="babel-segment"><button>星标</button><button class="is-active">未读 · 47</button><button>全部</button></div></section><section class="babel-content"><div class="babel-section-title"><h2>订阅源</h2><span>按更新排序</span></div>${feeds.map(f=>`<div class="babel-feed-row"><span class="babel-feed-mark">${f[0]}</span><span><b>${f[1]}</b><small>${f[2]}</small></span><span>${f[3]}</span></div>`).join('')}</section>${bottomDock('home')}`;
}

function list() {
  const rows = [
    ['全球供应链正在学习如何与不确定性共处','企业正在重新权衡成本、速度与地缘政治风险。',true],
    ['What We Lose When Every Place Starts to Look the Same','A journey through the quiet disappearance of local texture.',true],
    ['生成 AI 時代に、読解という行為はどう変わるのか','翻译与摘要成为日常以后，人还会如何阅读？',false],
    ['一封来自布鲁塞尔的短信','短文也应当保持轻盈。',false]
  ];
  return `${status()}<section class="babel-list-shell"><nav class="babel-nav"><button>${icons.back}</button><b class="babel-wordmark">文章</b><button>${icons.more}</button></nav><div class="babel-list-title"><small>ENGLISH → 简体中文</small><h1>Financial Times</h1><p>82 篇文章 · 12 篇未读</p></div></section><section class="babel-article-list">${rows.map((r,i)=>`<article class="babel-article-row ${r[2]?'':'babel-article-row--plain'}"><div><small>${i===0?'12 分钟前':'今天'}</small><h2>${r[0]}</h2><p>${r[1]}</p><time>${i%2?7:5} 分钟阅读</time></div>${r[2]?'<div class="babel-thumb"></div>':''}</article>`).join('')}</section>${bottomDock('')}`;
}

const actionDock = () => `<nav class="babel-action-dock" aria-label="文章操作"><button aria-label="阅读模式">${icons.reader}</button><button class="is-active" aria-label="翻译">${icons.translate}</button><button aria-label="生成长图">${icons.image}</button><button aria-label="星标">${icons.star}</button><button aria-label="更多">${icons.more}</button></nav>`;

function article() {
  return `${status()}<main class="babel-reader"><nav class="babel-reader-nav"><button>${icons.back}</button><span>已为你译成简体中文</span><button>${icons.more}</button></nav><article class="babel-reader-sheet"><h1>全球供应链正在学习如何与不确定性共处</h1><p class="babel-reader-deck">效率不再是唯一目标。企业正在重新权衡成本、速度、冗余与地缘政治风险。</p><div class="babel-reader-meta"><b>Financial Times</b><span>7 月 31 日</span><span>8 分钟</span></div><div class="babel-reader-copy"><p>在过去三十年里，全球供应链被设计成一台追求效率的机器。库存被压缩，路线被优化，每一个多余环节都被视为成本。</p><p>如今，企业没有放弃效率，但它们开始为不确定性付费。更近的供应商、更大的库存与第二套方案，正从浪费变成保险。</p><p>这并不是去全球化，而是一种更复杂的全球化。网络没有消失，只是学会了保留余地。</p></div></article></main>${actionDock()}`;
}

function actions() {
  return `${status()}<div class="babel-menu-backdrop"></div><section class="babel-menu"><div class="babel-menu__favorites"><button class="is-active">${icons.translate}</button><button>${icons.star}</button><button>${icons.image}</button></div><button class="babel-menu__row"><span>为什么推荐这篇</span>${icons.info}</button><button class="babel-menu__row is-active"><span>更多类似内容</span>${icons.sparkle}</button><button class="babel-menu__row"><span>减少此类内容</span>${icons.hand}</button><button class="babel-menu__row"><span>隐藏这篇文章</span>${icons.hide}</button></section>`;
}

function settingRow(icon, title, sub, value='›', active=false) {
  return `<div class="babel-settings-row ${active?'is-active':''}"><span class="babel-settings-row__icon">${icons[icon]}</span><span><b>${title}</b><small>${sub}</small></span><small>${value}</small></div>`;
}

function settings() {
  return `${status()}<div class="babel-settings-title"><small>BABEL</small><h1>设置</h1></div><section class="babel-settings-sheet"><div class="babel-settings-group"><small>阅读</small>${settingRow('translate','翻译与语言','目标语言、自动翻译与术语','简体中文',true)}${settingRow('reader','阅读外观','字体、字号与行距')}</div><div class="babel-settings-group"><small>内容</small>${settingRow('bookmark','订阅与同步','刷新、账户与后台更新')}${settingRow('image','长图与分享','导出外观与来源标记')}</div><div class="babel-settings-group"><small>Babel</small>${settingRow('info','帮助与反馈','版本 1.0')}</div></section>${bottomDock('settings')}`;
}

function language() {
  return `${status()}<section class="babel-list-shell"><nav class="babel-nav"><button>${icons.back}</button><b class="babel-wordmark">翻译与语言</b><span></span></nav><div class="babel-list-title"><small>DEFAULT READING LANGUAGE</small><h1>简体中文</h1><p>自动识别文章语言，再转换成你的阅读语言。</p></div></section><section class="babel-content"><div class="babel-settings-sheet" style="margin:0;padding-top:10px"><div class="babel-settings-group"><small>默认行为</small><div class="babel-settings-row is-active"><span class="babel-settings-row__icon">${icons.sparkle}</span><span><b>自动翻译外语文章</b><small>打开文章时开始准备</small></span><span class="babel-switch"></span></div>${settingRow('translate','目标语言文章','按钮保留但降低视觉强度','弱化')}${settingRow('reader','保留原文入口','随时在文章中切换','开启')}</div><div class="babel-settings-group"><small>译文偏好</small>${settingRow('info','人名与专有名词','首次出现时保留原文')}${settingRow('bookmark','个人术语表','0 个自定义词条')}</div></div></section>`;
}

const renderers = { home, list, article, actions, settings, language };

function render() {
  const phone = document.getElementById('phone');
  phone.dataset.theme = state.theme;
  phone.innerHTML = `<div class="babel-app">${renderers[state.screen]()}</div>`;
  document.getElementById('screenPicker').value = state.screen;
  document.querySelectorAll('[data-theme]').forEach(button => button.classList.toggle('is-active', button.dataset.theme === state.theme));
}

document.getElementById('screenPicker').addEventListener('change', event => { state.screen = event.target.value; render(); });
document.querySelector('.review__theme').addEventListener('click', event => { const button = event.target.closest('button[data-theme]'); if (!button) return; state.theme = button.dataset.theme; render(); });
document.addEventListener('keydown', event => { if (event.key.toLowerCase() === 'd') { state.theme = state.theme === 'light' ? 'dark' : 'light'; render(); } });
render();
