(function () {
  const i18n = {
    zh: {
      brand: "恋爱脑清醒日历",
      brandEn: "Love-Brain Clarity Calendar",
      lead: "一张软软的月历，安静见证你把恋爱脑念头放下，继续好好生活。日记只留在这台浏览器里。",
      living: "恭喜你，依旧在好好生活",
      livingStrong: "恭喜你，依旧在好好生活 · 越来越多格子安静了",
      demo: "演示模式（无需钱包）",
      connect: "连接 MetaMask",
      connected: "已连接",
      write: "写下今天",
      linkQ: "这次和之前哪一天有关？",
      fresh: "全新的一件事",
      save: "保存到本地",
      pledge: "我愿意彻底放下，继续好好生活",
      needText: "先写一点再保存。",
      saved: "已保存到浏览器。正文不会上链。",
      pickLink: "从第二条起，请选择关联的日子，或选「全新的一件事」。",
      oracleTitle: "毒舌神谕",
      chainHint: "链上只会发送无内容的 touch / 放下承诺。",
      noContract: "还没有填写合约地址：可继续演示。部署后把地址写入 app/config.js。",
      txTouch: "已发送 touch / link",
      txPledge: "已发送放下承诺",
      week: ["一", "二", "三", "四", "五", "六", "日"]
    },
    en: {
      brand: "Love-Brain Clarity Calendar",
      brandEn: "恋爱脑清醒日历",
      lead: "A soft month view that quietly witnesses you letting go. Diary text stays in this browser only.",
      living: "Congrats, you're still living well",
      livingStrong: "Congrats, you're still living well · more quiet squares now",
      demo: "Demo mode (no wallet)",
      connect: "Connect MetaMask",
      connected: "Connected",
      write: "Write this day",
      linkQ: "Which earlier day is this about?",
      fresh: "A brand-new thing",
      save: "Save locally",
      pledge: "I choose to let go and keep living well",
      needText: "Write something first.",
      saved: "Saved in the browser. Text never goes on-chain.",
      pickLink: "From the second entry on, pick related days or 'brand-new'.",
      oracleTitle: "Sassy oracle",
      chainHint: "On-chain: content-free touch / let-go pledge only.",
      noContract: "No contract address yet—demo still works. After deploy, set app/config.js.",
      txTouch: "Sent touch / link",
      txPledge: "Sent let-go pledge",
      week: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }
  };

  const state = ClarityStorage.load();
  let view = new Date();
  let selected = null;
  let walletAddr = null;
  let bgConfig = null;
  let localThreadSeq = 1;

  const $ = (id) => document.getElementById(id);

  function t() { return i18n[state.lang] || i18n.zh; }

  function dayKey(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
  }

  function parseKey(key) {
    const [y, m, d] = key.split("-").map(Number);
    return new Date(y, m - 1, d);
  }

  function applyPalette() {
    const entries = Object.values(state.entries);
    const total = entries.length || 1;
    const calm = entries.filter((e) => e.released).length;
    const drama = entries.filter((e) => !e.released).reduce((s, e) => s + Math.min(1, (e.text || "").length / 80), 0);
    const calmness = Math.min(1, calm / total);
    document.documentElement.style.setProperty("--calmness", String(calmness));
    document.documentElement.style.setProperty("--drama", String(Math.min(1, drama / Math.max(1, entries.length))));
    const el = $("livingWell");
    el.textContent = calmness > 0.45 ? t().livingStrong : t().living;
  }

  function paintUI() {
    const copy = t();
    $("brand").innerHTML = `${copy.brand}<span>${copy.brandEn}</span>`;
    $("lead").textContent = copy.lead;
    $("btnDemo").textContent = copy.demo;
    $("btnConnect").textContent = walletAddr ? `${copy.connected}: ${walletAddr.slice(0, 6)}…` : copy.connect;
    $("btnSave").textContent = copy.save;
    $("btnPledge").textContent = copy.pledge;
    $("linkQuestion").textContent = copy.linkQ;
    $("oracleLabel").textContent = copy.oracleTitle;
    $("chainHint").textContent = copy.chainHint;
    document.getElementById("langZh").setAttribute("aria-pressed", state.lang === "zh" ? "true" : "false");
    document.getElementById("langEn").setAttribute("aria-pressed", state.lang === "en" ? "true" : "false");
    renderMonth();
    applyPalette();
    if (selected) openDay(selected, false);
  }

  function renderMonth() {
    const copy = t();
    const y = view.getFullYear();
    const m = view.getMonth();
    $("monthTitle").textContent = state.lang === "zh"
      ? `${y}年${m + 1}月`
      : view.toLocaleString("en", { month: "long", year: "numeric" });
    const week = $("weekdays");
    week.innerHTML = copy.week.map((w) => `<span>${w}</span>`).join("");
    const first = new Date(y, m, 1);
    const startPad = (first.getDay() + 6) % 7; // Monday-first
    const daysInMonth = new Date(y, m + 1, 0).getDate();
    const grid = $("grid");
    grid.innerHTML = "";
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
      btn.innerHTML = `<span class="n">${d}</span>`;
      btn.addEventListener("click", () => openDay(key, true));
      grid.appendChild(btn);
    }
  }

  function priorDays(beforeKey) {
    return Object.keys(state.entries)
      .filter((k) => k < beforeKey)
      .sort()
      .reverse();
  }

  function openDay(key, scroll) {
    selected = key;
    const copy = t();
    const entry = state.entries[key];
    const panel = $("panel");
    panel.classList.add("open");
    $("panelTitle").textContent = `${copy.write} · ${key}`;
    $("entryText").value = entry ? entry.text : "";
    const existingCount = Object.keys(state.entries).length;
    const isFirstEver = existingCount === 0 || (existingCount === 1 && entry);
    const linkBox = $("linkBox");
    linkBox.innerHTML = "";
    if (!entry && !isFirstEver) {
      const title = document.createElement("div");
      title.textContent = copy.linkQ;
      linkBox.appendChild(title);
      const fresh = document.createElement("label");
      fresh.innerHTML = `<input type="radio" name="linkMode" value="fresh" checked> ${copy.fresh}`;
      linkBox.appendChild(fresh);
      priorDays(key).forEach((d) => {
        const lab = document.createElement("label");
        lab.innerHTML = `<input type="checkbox" name="linkDay" value="${d}"> ${d}${state.entries[d].text ? " — " + state.entries[d].text.slice(0, 18) : ""}`;
        linkBox.appendChild(lab);
      });
    } else if (entry && entry.linkedDays && entry.linkedDays.length) {
      const note = document.createElement("p");
      note.className = "note";
      note.textContent = (state.lang === "zh" ? "已关联：" : "Linked: ") + entry.linkedDays.join(", ");
      linkBox.appendChild(note);
    }

    const textForOracle = entry ? entry.text : "";
    if (textForOracle) showOracle(textForOracle, entry);
    else {
      $("oracle").textContent = "";
      $("panelBg").style.backgroundImage = "";
    }
    if (scroll) panel.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  function showOracle(text, entry) {
    const spoken = entry && entry.category
      ? ClarityOracle.pickLine(entry.category, state.lang, ClarityOracle.detectCategory(text) + text.length)
      : ClarityOracle.speak(text, state.lang);
    const line = entry
      ? (state.lang === "en" ? (entry.oracleEn || spoken.line) : (entry.oracleZh || spoken.line))
      : spoken.line;
    $("oracle").textContent = line;
    const cat = entry ? entry.category : spoken.category;
    const file = (bgConfig && bgConfig.categories[cat] && bgConfig.categories[cat].file) || "fallback.svg";
    $("panelBg").style.backgroundImage = `url("./backgrounds/${file}")`;
  }

  function collectLinks(key) {
    const boxes = [...document.querySelectorAll('input[name="linkDay"]:checked')].map((el) => el.value);
    const fresh = document.querySelector('input[name="linkMode"][value="fresh"]');
    if (boxes.length) return boxes;
    if (fresh && fresh.checked) return [];
    if (Object.keys(state.entries).length === 0 || state.entries[key]) return [];
    return null;
  }

  async function saveEntry() {
    const copy = t();
    if (!selected) return;
    const text = $("entryText").value.trim();
    if (!text) {
      $("status").textContent = copy.needText;
      return;
    }
    const isNew = !state.entries[selected];
    let linked = [];
    if (isNew && Object.keys(state.entries).length > 0) {
      linked = collectLinks(selected);
      if (linked === null) {
        $("status").textContent = copy.pickLink;
        return;
      }
    } else if (!isNew) {
      linked = state.entries[selected].linkedDays || [];
    }

    const spokenZh = ClarityOracle.speak(text, "zh");
    const spokenEn = ClarityOracle.pickLine(spokenZh.category, "en", text.length);
    let threadLocalId = null;
    if (linked.length) {
      const ids = linked.map((d) => state.entries[d].threadLocalId).filter((x) => x != null);
      threadLocalId = ids.length ? Math.min(...ids) : localThreadSeq++;
      linked.forEach((d) => { state.entries[d].threadLocalId = threadLocalId; });
    } else {
      threadLocalId = state.entries[selected]?.threadLocalId || localThreadSeq++;
    }

    const prev = state.entries[selected] || {};
    state.entries[selected] = {
      ...prev,
      dayKey: selected,
      text,
      linkedDays: linked,
      threadLocalId,
      category: spokenZh.category,
      oracleZh: spokenZh.line,
      oracleEn: spokenEn.line,
      createdAt: prev.createdAt || Date.now(),
      released: prev.released || false,
      chainThreadId: prev.chainThreadId || null,
      pledged: prev.pledged || false
    };
    ClarityStorage.save(state);
    showOracle(text, state.entries[selected]);
    $("status").textContent = copy.saved;
    paintUI();

    // On-chain touch when wallet + contract available and not demo-only preference
    if (walletAddr && ClarityConfig.calendarAddress && ClarityWallet.getContract()) {
      try {
        await chainTouchForDay(selected);
        $("status").textContent = copy.saved + " · " + copy.txTouch;
      } catch (e) {
        $("status").textContent = copy.saved + " · " + (e.shortMessage || e.message || String(e));
      }
    }
  }

  async function chainTouchForDay(key) {
    const group = ClarityGraph.threadDays(state.entries, key);
    const chainIds = ClarityGraph.onChainThreadIds(state.entries, group);
    let result;
    if (chainIds.length === 0) {
      result = await ClarityWallet.openThread();
    } else if (chainIds.length === 1) {
      result = await ClarityWallet.touch(chainIds[0]);
    } else {
      result = await ClarityWallet.linkAndTouch(chainIds);
    }
    let newId = result.threadId || chainIds[0] || null;
    if (!newId) {
      const c = ClarityWallet.getContract();
      const n = await c.nextThreadId(walletAddr);
      newId = Number(n);
    }
    group.forEach((d) => {
      if (state.entries[d]) state.entries[d].chainThreadId = newId;
    });
    ClarityStorage.save(state);
    return newId;
  }

  async function pledge() {
    const copy = t();
    if (!selected || !state.entries[selected]) {
      $("status").textContent = copy.needText;
      return;
    }
    state.entries[selected].pledged = true;
    const group = ClarityGraph.threadDays(state.entries, selected);
    group.forEach((d) => {
      if (state.entries[d]) state.entries[d].pledged = true;
    });
    ClarityStorage.save(state);

    if (state.demo && !(walletAddr && ClarityConfig.calendarAddress)) {
      // Demo: after "window", mark released locally so user sees calm palette
      $("status").textContent = (state.lang === "zh"
        ? `演示：已记下放下承诺。约 ${ClarityConfig.demoWindowMinutes} 分钟后可点「演示：标记彻底放下」。`
        : `Demo pledge saved. After ~${ClarityConfig.demoWindowMinutes} min, use “Demo: mark released”.`);
      paintUI();
      return;
    }
    if (!(walletAddr && ClarityConfig.calendarAddress && ClarityWallet.getContract())) {
      $("status").textContent = copy.noContract;
      return;
    }
    try {
      let id = state.entries[selected].chainThreadId;
      if (!id) id = await chainTouchForDay(selected);
      await ClarityWallet.pledgeLetGo(id);
      $("status").textContent = copy.txPledge;
    } catch (e) {
      $("status").textContent = e.shortMessage || e.message || String(e);
    }
    paintUI();
  }

  function demoRelease() {
    if (!selected || !state.entries[selected]) return;
    const group = ClarityGraph.threadDays(state.entries, selected);
    group.forEach((d) => {
      if (state.entries[d]) state.entries[d].released = true;
    });
    ClarityStorage.save(state);
    $("status").textContent = state.lang === "zh" ? "演示：这团已彻底放下，格子变平静。" : "Demo: thread released; cells calm.";
    paintUI();
  }

  async function connect() {
    try {
      walletAddr = await ClarityWallet.connect(ClarityConfig);
      state.demo = false;
      ClarityStorage.save(state);
      if (!ClarityConfig.calendarAddress) $("status").textContent = t().noContract;
      else $("status").textContent = t().connected;
      paintUI();
    } catch (e) {
      $("status").textContent = e.message === "NO_METAMASK"
        ? (state.lang === "zh" ? "未检测到 MetaMask，请用演示模式。" : "No MetaMask—use demo mode.")
        : (e.message || String(e));
    }
  }

  function bind() {
    $("langZh").onclick = () => { state.lang = "zh"; ClarityStorage.save(state); paintUI(); };
    $("langEn").onclick = () => { state.lang = "en"; ClarityStorage.save(state); paintUI(); };
    $("prevMonth").onclick = () => { view = new Date(view.getFullYear(), view.getMonth() - 1, 1); paintUI(); };
    $("nextMonth").onclick = () => { view = new Date(view.getFullYear(), view.getMonth() + 1, 1); paintUI(); };
    $("btnDemo").onclick = () => {
      state.demo = true;
      ClarityStorage.save(state);
      $("status").textContent = t().demo;
    };
    $("btnConnect").onclick = connect;
    $("btnSave").onclick = () => saveEntry();
    $("btnPledge").onclick = () => pledge();
    $("btnDemoRelease").onclick = demoRelease;
    $("entryText").addEventListener("input", () => {
      const text = $("entryText").value.trim();
      if (text.length > 8) showOracle(text, null);
    });
  }

  async function init() {
    Object.values(state.entries).forEach((e) => {
      if (e.threadLocalId && e.threadLocalId >= localThreadSeq) localThreadSeq = e.threadLocalId + 1;
    });
    try {
      bgConfig = await fetch(ClarityConfig.backgroundsConfig).then((r) => r.json());
    } catch {
      bgConfig = null;
    }
    bind();
    paintUI();
    // Open today on first load
    openDay(dayKey(new Date()), false);
  }

  init();
})();
