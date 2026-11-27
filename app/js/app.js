(function () {
  const i18n = {
    zh: {
      brand: "恋爱脑清醒日历",
      brandEn: "Love-Brain Clarity Calendar",
      lead: "一张软软的月历，安静见证你把恋爱脑念头放下，继续好好生活。",
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
      save: "保存",
      pledge: "我愿意彻底放下，继续好好生活",
      fastFwd: "⏩ 时间快进",
      needText: "先写一点再保存。",
      saved: "已保存。",
      pickLink: "请选择关联的日子，或选「全新的一件事」。",
      oracleTitle: "毒舌神谕",
      noContract: "还没有合约地址，可先演示。",
      txTouch: "已发送",
      txPledge: "已承诺放下",
      demoEntered: "演示模式已开启。",
      seeded: "已填入示例。",
      pledgedDemo: "已记下放下的心愿。",
      fastForwarded: "时间快进：已承诺的团变平静了。",
      fastForwardEmpty: "没有待放下的承诺。",
      badge: "演示中",
      noEthers: "钱包不可用，请用演示模式。",
      noMeta: "未检测到 MetaMask，请用演示模式。",
      week: ["一", "二", "三", "四", "五", "六", "日"]
    },
    en: {
      brand: "Love-Brain Clarity Calendar",
      brandEn: "恋爱脑清醒日历",
      lead: "A soft month view that quietly witnesses you letting go and living well.",
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
      save: "Save",
      pledge: "I choose to let go and keep living well",
      fastFwd: "⏩ Fast-forward",
      needText: "Write something first.",
      saved: "Saved.",
      pickLink: "Pick related days or 'brand-new'.",
      oracleTitle: "Sassy oracle",
      noContract: "No contract address yet—demo still works.",
      txTouch: "Sent",
      txPledge: "Pledge sent",
      demoEntered: "Demo mode on.",
      seeded: "Sample loaded.",
      pledgedDemo: "Let-go wish noted.",
      fastForwarded: "Fast-forward: pledged threads calmed.",
      fastForwardEmpty: "Nothing waiting to release.",
      badge: "Demo",
      noEthers: "Wallet unavailable—use demo mode.",
      noMeta: "No MetaMask—use demo mode.",
      week: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }
  };

  const state = ClarityStorage.load();
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
    if (!el || !msg) return;
    el.textContent = msg;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      el.hidden = true;
    }, 2600);
  }

  function bgFile(category) {
    const map = (window.ClarityConfig && ClarityConfig.backgrounds) || {};
    return map[category] || map.fallback || "fallback.svg";
  }

  function isSheetOpen() {
    const panel = $("panel");
    return !!(panel && !panel.hidden);
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

  function paintDemoChrome() {
    const badge = $("demoBadge");
    const btn = $("btnDemo");
    const fast = $("btnFastForward");
    if (badge) {
      badge.hidden = !state.demo;
      badge.textContent = t().badge;
    }
    if (btn) {
      btn.textContent = state.demo ? t().demoOn : t().demo;
      btn.classList.toggle("is-demo", !!state.demo);
    }
    if (fast) {
      fast.hidden = !state.demo;
      fast.textContent = t().fastFwd;
    }
  }

  // 翻月 / 语言切换只重绘月历，绝不打开弹层。
  function paintUI() {
    const copy = t();
    setHtml("brand", copy.brand + "<span>" + copy.brandEn + "</span>");
    setText("lead", copy.lead);
    setText("btnSeed", copy.seed);
    setText("btnConnect", walletAddr ? (copy.connected + ": " + walletAddr.slice(0, 6) + "…") : copy.connect);
    setText("btnSave", copy.save);
    setText("btnPledge", copy.pledge);
    setText("oracleLabel", copy.oracleTitle);
    paintDemoChrome();

    const zh = $("langZh");
    const en = $("langEn");
    if (zh) zh.setAttribute("aria-pressed", state.lang === "zh" ? "true" : "false");
    if (en) en.setAttribute("aria-pressed", state.lang === "en" ? "true" : "false");

    renderMonth();
    applyPalette();
    if (selected && isSheetOpen()) fillDayPanel(selected);
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

  function fillDayPanel(key) {
    const copy = t();
    const entry = state.entries[key];
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
  }

  function openDay(key, focus) {
    selected = key;
    openSheet();
    fillDayPanel(key);
    const ta = $("entryText");
    if (focus && ta) setTimeout(function () { ta.focus(); }, 160);
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
      toast(copy.needText);
      return;
    }
    const isNew = !state.entries[selected];
    let linked = [];
    if (isNew && Object.keys(state.entries).length > 0) {
      linked = collectLinks(selected);
      if (linked === null) {
        toast(copy.pickLink);
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
    toast(copy.saved);
    paintUI();
    if (isSheetOpen()) fillDayPanel(selected);

    if (canUseChain()) {
      try {
        await chainTouchForDay(selected);
        toast(copy.saved + " · " + copy.txTouch);
      } catch (e) {
        toast(copy.saved + " · " + (e.shortMessage || e.message || String(e)));
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
      toast(copy.needText);
      return;
    }
    const group = ClarityGraph.threadDays(state.entries, selected);
    group.forEach(function (d) {
      if (state.entries[d]) state.entries[d].pledged = true;
    });
    ClarityStorage.save(state);

    if (state.demo || !canUseChain()) {
      toast(copy.pledgedDemo);
      paintUI();
      if (isSheetOpen()) fillDayPanel(selected);
      return;
    }
    try {
      let id = state.entries[selected].chainThreadId;
      if (!id) id = await chainTouchForDay(selected);
      await ClarityWallet.pledgeLetGo(id);
      toast(copy.txPledge);
    } catch (e) {
      toast(e.shortMessage || e.message || String(e));
    }
    paintUI();
    if (isSheetOpen()) fillDayPanel(selected);
  }

  // 演示：把已承诺、尚未平静的团当作窗口到期，全部变平静。
  function fastForward() {
    if (!state.demo) return;
    const copy = t();
    let touched = 0;
    Object.keys(state.entries).forEach(function (k) {
      const e = state.entries[k];
      if (e && e.pledged && !e.released) {
        const group = ClarityGraph.threadDays(state.entries, k);
        group.forEach(function (d) {
          if (state.entries[d] && !state.entries[d].released) {
            state.entries[d].released = true;
            touched += 1;
          }
        });
      }
    });
    ClarityStorage.save(state);
    paintUI();
    if (selected && isSheetOpen()) fillDayPanel(selected);
    toast(touched ? copy.fastForwarded : copy.fastForwardEmpty);
  }

  function enterDemo(opts) {
    opts = opts || {};
    state.demo = true;
    walletAddr = null;
    ClarityStorage.save(state);
    view = new Date();
    paintUI();
    if (opts.focus) openDay(dayKey(new Date()), true);
    toast(t().demoEntered);
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
    state.entries = {};
    state.entries[d1] = makeEntry(d1, "他已读不回，是不是不爱我了", { threadLocalId: 1, linkedDays: [] });
    state.entries[d2] = makeEntry(d2, "想主动发消息，又怕显得很着急", { threadLocalId: 1, linkedDays: [d1] });
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
    toast(t().seeded);
  }

  async function connect() {
    const copy = t();
    if (!window.ClarityWallet || !ClarityWallet.ethersReady()) {
      toast(copy.noEthers);
      return;
    }
    try {
      walletAddr = await ClarityWallet.connect(ClarityConfig);
      state.demo = false;
      ClarityStorage.save(state);
      toast(ClarityConfig.calendarAddress ? copy.connected : copy.noContract);
      paintUI();
    } catch (e) {
      if (e.message === "NO_METAMASK") toast(copy.noMeta);
      else if (e.message === "NO_ETHERS") toast(copy.noEthers);
      else toast(e.message || String(e));
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
    on("btnFastForward", "click", function () { fastForward(); });
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
    bind();
    paintUI();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
