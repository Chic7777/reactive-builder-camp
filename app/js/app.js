(function () {
  const i18n = {
    zh: {
      brand: "恋爱脑清醒日历",
      brandEn: "Love-Brain Clarity Calendar",
      lead: "一张软软的月历，安静见证你把恋爱脑念头放下，继续好好生活。日记只留在这台浏览器里。",
      living: "恭喜你，依旧在好好生活",
      livingStrong: "恭喜你，依旧在好好生活 · 越来越多格子安静了",
      demo: "进入演示模式",
      demoOn: "演示中 · 再点可刷新",
      seed: "填入示例数据",
      connect: "连接 MetaMask",
      connected: "已连接",
      write: "写下今天",
      linkQ: "这次和之前哪一天有关？",
      fresh: "全新的一件事",
      save: "保存到本地",
      pledge: "我愿意彻底放下，继续好好生活",
      demoRelease: "演示：标记彻底放下",
      needText: "先写一点再保存。",
      saved: "已保存到浏览器。正文不会上链。",
      pickLink: "从第二条起，请选择关联的日子，或选「全新的一件事」。",
      oracleTitle: "毒舌神谕",
      chainHint: "演示模式不上链；连接钱包并填写合约后才会发 touch / pledge。",
      noContract: "还没有填写合约地址：可继续演示。部署后写入 app/config.js。",
      txTouch: "已发送 touch / link",
      txPledge: "已发送放下承诺",
      demoEntered: "已进入演示模式。点格子写日记，或先「填入示例数据」。",
      seeded: "已填入示例：粉色纠缠团 + 平静已放下团。点今天可继续写。",
      pledgedDemo: "演示：已记下放下承诺。可立刻点「标记彻底放下」看格子变平静。",
      releasedDemo: "演示：这团已彻底放下，格子变平静。",
      badge: "演示中",
      tapHint: "点某一天写下恋爱脑",
      entryLabel: "日记只存本机浏览器 · 永不上传",
      close: "关闭",
      foot: "赛道 2 · 测试网 · 运行时无 AI · 正文只在本机",
      noEthers: "钱包库未加载，请用演示模式（无需联网 CDN）。",
      noMeta: "未检测到 MetaMask，请用演示模式。",
      week: ["一", "二", "三", "四", "五", "六", "日"]
    },
    en: {
      brand: "Love-Brain Clarity Calendar",
      brandEn: "恋爱脑清醒日历",
      lead: "A soft month view that quietly witnesses you letting go. Diary text stays in this browser only.",
      living: "Congrats, you're still living well",
      livingStrong: "Congrats, you're still living well · more quiet squares now",
      demo: "Enter demo mode",
      demoOn: "Demo on · tap to refresh",
      seed: "Load sample data",
      connect: "Connect MetaMask",
      connected: "Connected",
      write: "Write this day",
      linkQ: "Which earlier day is this about?",
      fresh: "A brand-new thing",
      save: "Save locally",
      pledge: "I choose to let go and keep living well",
      demoRelease: "Demo: mark released",
      needText: "Write something first.",
      saved: "Saved in the browser. Text never goes on-chain.",
      pickLink: "From the second entry on, pick related days or 'brand-new'.",
      oracleTitle: "Sassy oracle",
      chainHint: "Demo stays off-chain. Wallet + contract address needed for txs.",
      noContract: "No contract address yet—demo still works. Set app/config.js after deploy.",
      txTouch: "Sent touch / link",
      txPledge: "Sent let-go pledge",
      demoEntered: "Demo mode on. Tap a day to write, or load sample data.",
      seeded: "Sample loaded: pink linked thread + one calm released thread.",
      pledgedDemo: "Demo pledge saved. Tap “mark released” to calm the cells.",
      releasedDemo: "Demo: thread released; cells calmed.",
      badge: "Demo",
      tapHint: "Tap a day to write",
      entryLabel: "Diary stays in this browser only",
      close: "Close",
      foot: "Track 2 · testnet · no runtime AI · text stays local",
      noEthers: "Wallet library missing—use demo mode (no CDN needed).",
      noMeta: "No MetaMask—use demo mode.",
      week: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }
  };

  const state = ClarityStorage.load();
  // 双击打开时默认视为可演示；显式点按钮会强化 UI
  if (typeof state.demo !== "boolean") state.demo = true;

  let view = new Date();
  let selected = null;
  let walletAddr = null;
  let localThreadSeq = 1;
  let toastTimer = null;

  function $(id) {
    return document.getElementById(id);
  }

  function setText(id, value) {
    const el = $(id);
    if (el) el.textContent = value;
  }

  function setHtml(id, value) {
    const el = $(id);
    if (el) el.innerHTML = value;
  }

  function t() {
    return i18n[state.lang] || i18n.zh;
  }

  function dayKey(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return y + "-" + m + "-" + day;
  }

  function shiftDay(base, delta) {
    const d = new Date(base.getFullYear(), base.getMonth(), base.getDate() + delta);
    return dayKey(d);
  }

  function toast(msg) {
    const el = $("toast");
    if (!el) return;
    el.textContent = msg;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      el.hidden = true;
    }, 2800);
  }

  function setStatus(msg) {
    setText("status", msg || "");
    if (msg) toast(msg);
  }

  function bgFile(category) {
    const map = (window.ClarityConfig && ClarityConfig.backgrounds) || {};
    return map[category] || map.fallback || "fallback.svg";
  }

  function applyPalette() {
    const entries = Object.keys(state.entries).map(function (k) { return state.entries[k]; });
    const total = entries.length || 1;
    const calm = entries.filter(function (e) { return e.released; }).length;
    const drama = entries.filter(function (e) { return !e.released; }).reduce(function (s, e) {
      return s + Math.min(1, (e.text || "").length / 80);
    }, 0);
    const calmness = Math.min(1, calm / total);
    document.documentElement.style.setProperty("--calmness", String(calmness));
    document.documentElement.style.setProperty("--drama", String(Math.min(1, drama / Math.max(1, entries.length))));
    setText("livingWell", calmness > 0.45 ? t().livingStrong : t().living);
  }

  function paintDemoBadge() {
    const badge = $("demoBadge");
    const btn = $("btnDemo");
    if (badge) {
      badge.hidden = !state.demo;
      badge.textContent = t().badge;
    }
    if (btn) {
      btn.textContent = state.demo ? t().demoOn : t().demo;
      btn.classList.toggle("is-demo", !!state.demo);
    }
  }

  function paintUI() {
    const copy = t();
    setHtml("brand", copy.brand + "<span>" + copy.brandEn + "</span>");
    setText("lead", copy.lead);
    setText("btnSeed", copy.seed);
    setText("btnConnect", walletAddr ? (copy.connected + ": " + walletAddr.slice(0, 6) + "…") : copy.connect);
    setText("btnSave", copy.save);
    setText("btnPledge", copy.pledge);
    setText("btnDemoRelease", copy.demoRelease);
    setText("oracleLabel", copy.oracleTitle);
    setText("chainHint", copy.chainHint);
    setText("tapHint", copy.tapHint);
    setText("entryLabel", copy.entryLabel);
    setText("footerNote", copy.foot);
    paintDemoBadge();

    const zh = $("langZh");
    const en = $("langEn");
    if (zh) zh.setAttribute("aria-pressed", state.lang === "zh" ? "true" : "false");
    if (en) en.setAttribute("aria-pressed", state.lang === "en" ? "true" : "false");

    renderMonth();
    applyPalette();
    if (selected) openDay(selected, false);
  }

  function renderMonth() {
    const copy = t();
    const y = view.getFullYear();
    const m = view.getMonth();
    setText("monthTitle", state.lang === "zh"
      ? y + "年" + (m + 1) + "月"
      : view.toLocaleString("en", { month: "long", year: "numeric" }));

    const week = $("weekdays");
    if (week) week.innerHTML = copy.week.map(function (w) { return "<span>" + w + "</span>"; }).join("");

    const grid = $("grid");
    if (!grid) return;
    grid.innerHTML = "";
    const first = new Date(y, m, 1);
    const startPad = (first.getDay() + 6) % 7;
    const daysInMonth = new Date(y, m + 1, 0).getDate();
    const todayKey = dayKey(new Date());

    for (let i = 0; i < startPad; i++) {
      const btn = document.createElement("button");
      btn.className = "day muted";
      btn.type = "button";
      btn.disabled = true;
      grid.appendChild(btn);
    }
    for (let d = 1; d <= daysInMonth; d++) {
      const date = new Date(y, m, d);
      const key = dayKey(date);
      const entry = state.entries[key];
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "day";
      if (key === todayKey) btn.classList.add("today");
      if (entry) {
        btn.classList.add("has-entry");
        const drama = Math.min(1, (entry.text || "").length / 100);
        btn.style.setProperty("--drama", String(entry.released ? 0.1 : drama));
        if (entry.released) btn.classList.add("calm-thread");
      }
      btn.innerHTML = "<span class=\"n\">" + d + "</span>";
      btn.addEventListener("click", function () { openDay(key, true); });
      grid.appendChild(btn);
    }
  }

  function priorDays(beforeKey) {
    return Object.keys(state.entries)
      .filter(function (k) { return k < beforeKey; })
      .sort()
      .reverse();
  }

  function openSheet() {
    const panel = $("panel");
    const backdrop = $("sheetBackdrop");
    if (panel) panel.hidden = false;
    if (backdrop) backdrop.hidden = false;
    document.body.classList.add("sheet-open");
  }

  function closeSheet() {
    const panel = $("panel");
    const backdrop = $("sheetBackdrop");
    if (panel) panel.hidden = true;
    if (backdrop) backdrop.hidden = true;
    document.body.classList.remove("sheet-open");
  }

  function openDay(key, focus) {
    selected = key;
    const copy = t();
    const entry = state.entries[key];
    openSheet();
    setText("panelTitle", copy.write + " · " + key);
    const ta = $("entryText");
    if (ta) ta.value = entry ? entry.text : "";

    const existingCount = Object.keys(state.entries).length;
    const isFirstEver = existingCount === 0 || (existingCount === 1 && !!entry);
    const linkBox = $("linkBox");
    if (linkBox) {
      linkBox.innerHTML = "";
      if (!entry && !isFirstEver) {
        const title = document.createElement("div");
        title.id = "linkQuestion";
        title.textContent = copy.linkQ;
        linkBox.appendChild(title);
        const fresh = document.createElement("label");
        fresh.innerHTML = "<input type=\"radio\" name=\"linkMode\" value=\"fresh\" checked> " + copy.fresh;
        linkBox.appendChild(fresh);
        priorDays(key).forEach(function (d) {
          const lab = document.createElement("label");
          const snippet = state.entries[d].text ? " — " + state.entries[d].text.slice(0, 18) : "";
          lab.innerHTML = "<input type=\"checkbox\" name=\"linkDay\" value=\"" + d + "\"> " + d + snippet;
          linkBox.appendChild(lab);
        });
      } else if (entry && entry.linkedDays && entry.linkedDays.length) {
        const note = document.createElement("p");
        note.className = "note";
        note.textContent = (state.lang === "zh" ? "已关联：" : "Linked: ") + entry.linkedDays.join(", ");
        linkBox.appendChild(note);
      }
    }

    if (entry && entry.text) showOracle(entry.text, entry);
    else {
      setText("oracle", "");
      const bg = $("panelBg");
      if (bg) bg.style.backgroundImage = "";
    }

    if (focus && ta) {
      setTimeout(function () { ta.focus(); }, 180);
    }
  }

  function showOracle(text, entry) {
    const spoken = entry && entry.category
      ? ClarityOracle.pickLine(entry.category, state.lang, text.length)
      : ClarityOracle.speak(text, state.lang);
    const line = entry
      ? (state.lang === "en" ? (entry.oracleEn || spoken.line) : (entry.oracleZh || spoken.line))
      : spoken.line;
    setText("oracle", line);
    const cat = entry ? entry.category : spoken.category;
    const bg = $("panelBg");
    if (bg) bg.style.backgroundImage = "url(\"./backgrounds/" + bgFile(cat) + "\")";
  }

  function collectLinks(key) {
    const boxes = Array.prototype.slice.call(document.querySelectorAll('input[name="linkDay"]:checked'))
      .map(function (el) { return el.value; });
    const fresh = document.querySelector('input[name="linkMode"][value="fresh"]');
    if (boxes.length) return boxes;
    if (fresh && fresh.checked) return [];
    if (Object.keys(state.entries).length === 0 || state.entries[key]) return [];
    return null;
  }

  function canUseChain() {
    return !!(
      walletAddr &&
      ClarityConfig.calendarAddress &&
      window.ClarityWallet &&
      ClarityWallet.ethersReady() &&
      ClarityWallet.getContract()
    );
  }

  async function saveEntry() {
    const copy = t();
    if (!selected) return;
    const ta = $("entryText");
    const text = ta ? ta.value.trim() : "";
    if (!text) {
      setStatus(copy.needText);
      return;
    }
    const isNew = !state.entries[selected];
    let linked = [];
    if (isNew && Object.keys(state.entries).length > 0) {
      linked = collectLinks(selected);
      if (linked === null) {
        setStatus(copy.pickLink);
        return;
      }
    } else if (!isNew) {
      linked = state.entries[selected].linkedDays || [];
    }

    const spokenZh = ClarityOracle.speak(text, "zh");
    const spokenEn = ClarityOracle.pickLine(spokenZh.category, "en", text.length);
    let threadLocalId = null;
    if (linked.length) {
      const ids = linked.map(function (d) { return state.entries[d].threadLocalId; }).filter(function (x) { return x != null; });
      threadLocalId = ids.length ? Math.min.apply(null, ids) : localThreadSeq++;
      linked.forEach(function (d) { state.entries[d].threadLocalId = threadLocalId; });
    } else {
      threadLocalId = (state.entries[selected] && state.entries[selected].threadLocalId) || localThreadSeq++;
    }

    const prev = state.entries[selected] || {};
    state.entries[selected] = {
      dayKey: selected,
      text: text,
      linkedDays: linked,
      threadLocalId: threadLocalId,
      category: spokenZh.category,
      oracleZh: spokenZh.line,
      oracleEn: spokenEn.line,
      createdAt: prev.createdAt || Date.now(),
      released: !!prev.released,
      chainThreadId: prev.chainThreadId || null,
      pledged: !!prev.pledged
    };
    ClarityStorage.save(state);
    showOracle(text, state.entries[selected]);
    setStatus(copy.saved);
    paintUI();
    openDay(selected, false);

    if (canUseChain()) {
      try {
        await chainTouchForDay(selected);
        setStatus(copy.saved + " · " + copy.txTouch);
      } catch (e) {
        setStatus(copy.saved + " · " + (e.shortMessage || e.message || String(e)));
      }
    }
  }

  async function chainTouchForDay(key) {
    const group = ClarityGraph.threadDays(state.entries, key);
    const chainIds = ClarityGraph.onChainThreadIds(state.entries, group);
    let result;
    if (chainIds.length === 0) result = await ClarityWallet.openThread();
    else if (chainIds.length === 1) result = await ClarityWallet.touch(chainIds[0]);
    else result = await ClarityWallet.linkAndTouch(chainIds);
    let newId = result.threadId || chainIds[0] || null;
    if (!newId) {
      const n = await ClarityWallet.getContract().nextThreadId(walletAddr);
      newId = Number(n);
    }
    group.forEach(function (d) {
      if (state.entries[d]) state.entries[d].chainThreadId = newId;
    });
    ClarityStorage.save(state);
    return newId;
  }

  async function pledge() {
    const copy = t();
    if (!selected || !state.entries[selected]) {
      setStatus(copy.needText);
      return;
    }
    const group = ClarityGraph.threadDays(state.entries, selected);
    group.forEach(function (d) {
      if (state.entries[d]) state.entries[d].pledged = true;
    });
    ClarityStorage.save(state);

    if (state.demo || !canUseChain()) {
      setStatus(copy.pledgedDemo);
      paintUI();
      openDay(selected, false);
      return;
    }
    try {
      let id = state.entries[selected].chainThreadId;
      if (!id) id = await chainTouchForDay(selected);
      await ClarityWallet.pledgeLetGo(id);
      setStatus(copy.txPledge);
    } catch (e) {
      setStatus(e.shortMessage || e.message || String(e));
    }
    paintUI();
    openDay(selected, false);
  }

  function demoRelease() {
    const copy = t();
    if (!selected || !state.entries[selected]) {
      setStatus(copy.needText);
      return;
    }
    const group = ClarityGraph.threadDays(state.entries, selected);
    group.forEach(function (d) {
      if (state.entries[d]) state.entries[d].released = true;
    });
    ClarityStorage.save(state);
    setStatus(copy.releasedDemo);
    paintUI();
    openDay(selected, false);
  }

  function enterDemo(opts) {
    opts = opts || {};
    state.demo = true;
    walletAddr = null;
    ClarityStorage.save(state);
    view = new Date();
    paintUI();
    const today = dayKey(new Date());
    openDay(today, !!opts.focus);
    setStatus(t().demoEntered);
  }

  function makeEntry(key, text, extra) {
    const spokenZh = ClarityOracle.speak(text, "zh");
    const spokenEn = ClarityOracle.pickLine(spokenZh.category, "en", text.length);
    return Object.assign({
      dayKey: key,
      text: text,
      linkedDays: [],
      threadLocalId: 1,
      category: spokenZh.category,
      oracleZh: spokenZh.line,
      oracleEn: spokenEn.line,
      createdAt: Date.now(),
      released: false,
      chainThreadId: null,
      pledged: false
    }, extra || {});
  }

  function seedSample() {
    const today = new Date();
    const d1 = shiftDay(today, -5);
    const d2 = shiftDay(today, -3);
    const d3 = shiftDay(today, -2);
    const calm = shiftDay(today, -8);
    // 一团纠缠：d1-d2-d3 相连；另有一团已彻底放下
    state.entries = {};
    state.entries[d1] = makeEntry(d1, "他已读不回，是不是不爱我了", {
      threadLocalId: 1,
      linkedDays: []
    });
    state.entries[d2] = makeEntry(d2, "想主动发消息，又怕显得很着急", {
      threadLocalId: 1,
      linkedDays: [d1]
    });
    state.entries[d3] = makeEntry(d3, "看到他朋友圈，有点嫉妒", {
      threadLocalId: 1,
      linkedDays: [d1, d2],
      pledged: true
    });
    state.entries[calm] = makeEntry(calm, "以前想复合，现在决定好好生活", {
      threadLocalId: 2,
      linkedDays: [],
      pledged: true,
      released: true,
      category: "reunion"
    });
    localThreadSeq = 3;
    state.demo = true;
    ClarityStorage.save(state);
    view = new Date();
    paintUI();
    openDay(dayKey(today), true);
    setStatus(t().seeded);
  }

  async function connect() {
    const copy = t();
    if (!window.ClarityWallet || !ClarityWallet.ethersReady()) {
      setStatus(copy.noEthers);
      return;
    }
    try {
      walletAddr = await ClarityWallet.connect(ClarityConfig);
      state.demo = false;
      ClarityStorage.save(state);
      setStatus(ClarityConfig.calendarAddress ? copy.connected : copy.noContract);
      paintUI();
    } catch (e) {
      if (e.message === "NO_METAMASK") setStatus(copy.noMeta);
      else if (e.message === "NO_ETHERS") setStatus(copy.noEthers);
      else setStatus(e.message || String(e));
    }
  }

  function on(id, event, handler) {
    const el = $(id);
    if (el) el.addEventListener(event, handler);
  }

  function bind() {
    on("langZh", "click", function () {
      state.lang = "zh";
      ClarityStorage.save(state);
      paintUI();
    });
    on("langEn", "click", function () {
      state.lang = "en";
      ClarityStorage.save(state);
      paintUI();
    });
    on("prevMonth", "click", function () {
      view = new Date(view.getFullYear(), view.getMonth() - 1, 1);
      paintUI();
    });
    on("nextMonth", "click", function () {
      view = new Date(view.getFullYear(), view.getMonth() + 1, 1);
      paintUI();
    });
    on("btnDemo", "click", function () { enterDemo({ focus: true }); });
    on("btnSeed", "click", function () { seedSample(); });
    on("btnConnect", "click", function () { connect(); });
    on("btnSave", "click", function () { saveEntry(); });
    on("btnPledge", "click", function () { pledge(); });
    on("btnDemoRelease", "click", function () { demoRelease(); });
    on("btnCloseSheet", "click", function () { closeSheet(); });
    on("sheetBackdrop", "click", function () { closeSheet(); });
    on("entryText", "input", function () {
      const ta = $("entryText");
      const text = ta ? ta.value.trim() : "";
      if (text.length > 8) showOracle(text, null);
    });
  }

  function init() {
    Object.keys(state.entries).forEach(function (k) {
      const e = state.entries[k];
      if (e && e.threadLocalId && e.threadLocalId >= localThreadSeq) localThreadSeq = e.threadLocalId + 1;
    });
    // 不 fetch；背景来自 ClarityConfig.backgrounds
    bind();
    paintUI();
    // 首次打开：若已是演示偏好，显示徽章但不强制弹层；用户点演示才弹
    if (state.demo) paintDemoBadge();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
