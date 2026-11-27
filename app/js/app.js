(function () {
  const i18n = {
    zh: {
      skip: "Skip / 跳过",
      openingSub: "— Love yourself today —",
      openingHint: "轻轻触碰，翻开属于你的清醒手账 ✦",
      morning: "清晨暖阳",
      noon: "午后清风",
      night: "夜色温柔",
      weather: "好好生活",
      kaomoji: "今天也要对自己超级心软呀 (｡♥‿♥｡)",
      blessFoot: "今日清醒猫点 · 心跳软绵绵",
      trashTitle: "情绪碎碎念垃圾桶",
      trashNote: "把心里的小波浪丢进来，轻一点继续走。",
      startWrite: "写下今天的「恋爱脑」小泡泡",
      seed: "填入示例数据",
      fastFwd: "⏩ 时间快进",
      badge: "演示中",
      homeOracleTitle: "毒舌神谕 · 恋爱脑粉碎机",
      openOracle: "戳戳看大卡 ✨",
      monthSub: "情绪漫游手账本",
      todayBtn: "回到今天",
      detailPrefix: "清醒手账存根",
      willing: "🌷 愿意放下",
      oracleStub: "🔖 毒舌清醒糖纸",
      swipeHome: "右滑翻开手账小日历呀 →",
      swipeCal: "← 左滑回首页抱抱自己",
      linkStep: "🧸 情绪脉络梳理 · 第 1/2 步",
      linkQ: "这次和之前的事有关吗？💭",
      linkSub: "轻轻选一选，我们帮你把心结串成线 (・ω・)ノ",
      freshTitle: "全新一件事 ✨",
      freshSub: "开一团新的念头",
      relatedTitle: "和旧心结有关 🫧",
      relatedSub: "关联之前的日子",
      priorHead: "轻按贴纸关联往昔记录",
      continueWrite: "✏️ 继续写下细节",
      linkedCount: "已关联 {n} 个心结",
      later: "稍后再记 · 先去抱抱自己 🧸",
      writeTitle: "坦诚写下这一刻的想法",
      writeSub: "这里没有批判，只有接纳与清醒",
      writePrompt: "揉揉脑袋：是事实如此，还是委屈小剧场又在偷偷加戏啦？",
      moodLabel: "为此刻的心情贴上小标签 · 可多选",
      saveOnly: "先存起来 (慢慢想)",
      pledge: "我愿意放下啦",
      oracleTag: "✦ 醒脑时刻",
      tuck: "我清醒了 · 收进月历手账",
      dismiss: "轻触任意处收起并返回",
      needText: "先写一点再保存。",
      saved: "已保存。",
      pickLink: "请选择关联的日子，或选「全新一件事」。",
      noContract: "还没有合约地址，可先演示。",
      txTouch: "已发送",
      txPledge: "已承诺放下",
      seeded: "已填入示例。",
      pledgedDemo: "已记下放下的心愿。",
      fastForwarded: "时间快进：已承诺的团变平静了。",
      fastForwardEmpty: "没有待放下的承诺。",
      noEthers: "钱包不可用，请用演示模式。",
      noMeta: "未检测到 MetaMask，请用演示模式。",
      connected: "已连接",
      connect: "连接钱包",
      week: ["一", "二", "三", "四", "五", "六", "日"],
      dow: ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
    },
    en: {
      skip: "Skip / 跳过",
      openingSub: "— Love yourself today —",
      openingHint: "Gently tap to open your clarity journal ✦",
      morning: "Morning sun",
      noon: "Afternoon breeze",
      night: "Gentle night",
      weather: "Live well",
      kaomoji: "Be soft with yourself today (｡♥‿♥｡)",
      blessFoot: "Today's clarity cat · heartbeat soft",
      trashTitle: "Emotional babble bin",
      trashNote: "Drop the little waves here. Keep walking light.",
      startWrite: "Write today's love-brain bubbles",
      seed: "Load sample data",
      fastFwd: "⏩ Fast-forward",
      badge: "Demo",
      homeOracleTitle: "Sassy oracle · love-brain smasher",
      openOracle: "Poke the big card ✨",
      monthSub: "Mood wandering journal",
      todayBtn: "Back to today",
      detailPrefix: "Clarity journal stub",
      willing: "🌷 Willing to let go",
      oracleStub: "🔖 Clarity candy wrapper",
      swipeHome: "Swipe for the calendar →",
      swipeCal: "← Swipe home for a hug",
      linkStep: "🧸 Emotion thread · step 1/2",
      linkQ: "Related to something earlier? 💭",
      linkSub: "Pick gently—we'll string the knots (・ω・)ノ",
      freshTitle: "Brand-new thing ✨",
      freshSub: "Start a fresh thread",
      relatedTitle: "Tied to an old knot 🫧",
      relatedSub: "Link earlier days",
      priorHead: "Tap stickers to link past notes",
      continueWrite: "✏️ Continue writing",
      linkedCount: "{n} knots linked",
      later: "Later · go hug yourself first 🧸",
      writeTitle: "Write this moment honestly",
      writeSub: "No judgment here—only acceptance and clarity",
      writePrompt: "Rub your head: fact—or the drama theater improvising again?",
      moodLabel: "Stick mood labels · multi-select",
      saveOnly: "Save for now (think slow)",
      pledge: "I'm willing to let go",
      oracleTag: "✦ Wake-up moment",
      tuck: "I'm clear · tuck into calendar",
      dismiss: "Tap anywhere to close",
      needText: "Write something first.",
      saved: "Saved.",
      pickLink: "Pick related days or 'brand-new'.",
      noContract: "No contract yet—demo still works.",
      txTouch: "Sent",
      txPledge: "Pledge sent",
      seeded: "Sample loaded.",
      pledgedDemo: "Let-go wish noted.",
      fastForwarded: "Fast-forward: pledged threads calmed.",
      fastForwardEmpty: "Nothing waiting to release.",
      noEthers: "Wallet unavailable—use demo.",
      noMeta: "No MetaMask—use demo.",
      connected: "Connected",
      connect: "Connect wallet",
      week: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
      dow: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    }
  };

  const state = ClarityStorage.load();
  if (typeof state.demo !== "boolean") state.demo = true;

  let view = new Date();
  let selected = null;
  let walletAddr = null;
  let localThreadSeq = 1;
  let toastTimer = null;
  let pageIndex = 0;
  let linkMode = "related";
  let pendingLinks = [];
  let writeMoods = [];
  let pendingOracleDay = null;
  let clockTimer = null;

  function $(id) { return document.getElementById(id); }
  function setText(id, value) {
    const el = $(id);
    if (el) el.textContent = value;
  }
  function t() { return i18n[state.lang] || i18n.zh; }

  function dayKey(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return y + "-" + m + "-" + day;
  }

  function parseKey(key) {
    const p = String(key).split("-").map(Number);
    return new Date(p[0], p[1] - 1, p[2]);
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
    toastTimer = setTimeout(function () { el.hidden = true; }, 2600);
  }

  function timeOfDay() {
    const h = new Date().getHours();
    if (h >= 5 && h < 11) return "morning";
    if (h >= 11 && h < 18) return "noon";
    return "night";
  }

  function artUrl(name) {
    const art = (ClarityConfig && ClarityConfig.art) || {};
    if (name === "morning" || name === "noon" || name === "night") return art[name] || ("./art/bg-" + name + ".webp");
    if (name === "tea") return art.tea || "./art/tea-person.webp";
    if (name === "icon") return art.icon || "./art/app-icon.webp";
    if (art.oracle && art.oracle[name]) return art.oracle[name];
    return "./art/oracle-" + name + ".webp";
  }

  function applyBackground() {
    const shell = $("appShell");
    if (!shell) return;
    const slot = timeOfDay();
    shell.style.backgroundImage =
      "linear-gradient(180deg, rgba(255,253,246,0.35), rgba(255,253,246,0.72)), url('" + artUrl(slot) + "')";
    const copy = t();
    setText("timeChip", slot === "morning" ? copy.morning : slot === "noon" ? copy.noon : copy.night);
    setText("weatherChip", copy.weather);
  }

  function formatHomeDate(d) {
    if (state.lang === "en") {
      return d.toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" });
    }
    return d.getFullYear() + "年 " + (d.getMonth() + 1) + "月" + d.getDate() + "日";
  }

  function formatClock(d) {
    return d.toLocaleTimeString(state.lang === "en" ? "en-US" : "zh-CN", {
      hour: "numeric",
      minute: "2-digit"
    });
  }

  function setPage(index) {
    pageIndex = index === 1 ? 1 : 0;
    const pager = $("pager");
    if (pager) pager.classList.toggle("page-1", pageIndex === 1);
    document.querySelectorAll(".dot").forEach(function (dot) {
      dot.classList.toggle("active", Number(dot.getAttribute("data-dot")) === pageIndex);
    });
    setText("swipeHint", pageIndex === 0 ? t().swipeHome : t().swipeCal);
  }

  function bindSwipe() {
    const pager = $("pager");
    if (!pager) return;
    let startX = 0;
    let startY = 0;
    let tracking = false;

    function down(x, y) {
      startX = x;
      startY = y;
      tracking = true;
    }
    function up(x, y) {
      if (!tracking) return;
      tracking = false;
      const dx = x - startX;
      const dy = y - startY;
      if (Math.abs(dx) < 48 || Math.abs(dx) < Math.abs(dy)) return;
      if (dx < 0 && pageIndex === 0) setPage(1);
      else if (dx > 0 && pageIndex === 1) setPage(0);
    }

    pager.addEventListener("touchstart", function (e) {
      if (!e.touches[0]) return;
      down(e.touches[0].clientX, e.touches[0].clientY);
    }, { passive: true });
    pager.addEventListener("touchend", function (e) {
      const tch = e.changedTouches[0];
      if (tch) up(tch.clientX, tch.clientY);
    }, { passive: true });
    pager.addEventListener("mousedown", function (e) {
      down(e.clientX, e.clientY);
    });
    window.addEventListener("mouseup", function (e) {
      up(e.clientX, e.clientY);
    });
  }

  function paintChrome() {
    const copy = t();
    setText("btnSkip", copy.skip);
    setText("openingSub", copy.openingSub);
    setText("openingHint", copy.openingHint);
    setText("homeKaomoji", copy.kaomoji);
    setText("blessFoot", copy.blessFoot);
    setText("trashTitle", copy.trashTitle);
    setText("trashNote", copy.trashNote);
    setText("btnStartWrite", copy.startWrite);
    setText("btnSeed", copy.seed);
    setText("btnFastForward", copy.fastFwd);
    setText("demoBadge", copy.badge);
    setText("homeOracleTitle", copy.homeOracleTitle);
    setText("btnOpenOracle", copy.openOracle);
    setText("monthSub", copy.monthSub);
    setText("btnToday", copy.todayBtn);
    setText("btnPledgeFromCal", copy.willing);
    setText("detailOracleLabel", copy.oracleStub);
    setText("btnDetailOracle", copy.openOracle);
    setText("linkStepTitle", copy.linkStep);
    setText("linkQuestion", copy.linkQ);
    setText("linkSub", copy.linkSub);
    setText("choiceFreshTitle", copy.freshTitle);
    setText("choiceFreshSub", copy.freshSub);
    setText("choiceRelatedTitle", copy.relatedTitle);
    setText("choiceRelatedSub", copy.relatedSub);
    setText("btnLinkLater", copy.later);
    setText("writeTitle", copy.writeTitle);
    setText("writeSub", copy.writeSub);
    setText("writePrompt", copy.writePrompt);
    setText("moodLabel", copy.moodLabel);
    setText("btnSaveOnly", copy.saveOnly);
    setText("btnPledge", copy.pledge);
    setText("oracleTag", copy.oracleTag);
    setText("btnTuckOracle", copy.tuck);
    setText("oracleDismiss", copy.dismiss);
    setText("swipeHint", pageIndex === 0 ? copy.swipeHome : copy.swipeCal);

    const badge = $("demoBadge");
    const fast = $("btnFastForward");
    if (badge) badge.hidden = !state.demo;
    if (fast) fast.hidden = !state.demo;

    const langBtn = $("btnLang");
    if (langBtn) langBtn.textContent = state.lang === "zh" ? "🌐 中/EN" : "🌐 EN/中";

    const walletBtn = $("btnWallet");
    if (walletBtn) {
      walletBtn.textContent = walletAddr
        ? ("👛 " + walletAddr.slice(0, 4) + "…" + walletAddr.slice(-4))
        : "👛";
      walletBtn.title = walletAddr || copy.connect;
    }

    updateLinkContinueLabel();
  }

  function paintHome() {
    const now = new Date();
    setText("homeDate", formatHomeDate(now));
    setText("homeDow", t().dow[now.getDay()]);
    setText("homeClock", formatClock(now));
    setText("blessText", ClarityBlessings.forDate(now, state.lang));
    applyBackground();

    const today = dayKey(now);
    const entry = state.entries[today];
    const card = $("homeOracleCard");
    if (card) {
      if (entry && (entry.oracleZh || entry.oracleEn)) {
        card.hidden = false;
        const label = entry.tone
          ? (ClarityOracle.LABELS[entry.tone]
            ? (state.lang === "en" ? ClarityOracle.LABELS[entry.tone].en : ClarityOracle.LABELS[entry.tone].zh)
            : "")
          : "";
        setText("homeOracleLabel", label ? ("ORACLE · " + label) : "ORACLE");
        setText("homeOracleLine", state.lang === "en" ? (entry.oracleEn || entry.oracleZh) : (entry.oracleZh || entry.oracleEn));
      } else {
        card.hidden = true;
      }
    }
  }

  function cellCenter(el, root) {
    const a = el.getBoundingClientRect();
    const b = root.getBoundingClientRect();
    return { x: a.left - b.left + a.width / 2, y: a.top - b.top + a.height / 2 };
  }

  function drawThreads() {
    const svg = $("threadSvg");
    const grid = $("grid");
    if (!svg || !grid) return;
    svg.innerHTML = "";
    const groups = ClarityGraph.components(state.entries);
    const y = view.getFullYear();
    const m = view.getMonth();
    Object.keys(groups).forEach(function (root) {
      const days = groups[root].filter(function (k) {
        const d = parseKey(k);
        return d.getFullYear() === y && d.getMonth() === m;
      }).sort();
      if (days.length < 2) return;
      const released = days.every(function (k) { return state.entries[k] && state.entries[k].released; });
      for (let i = 0; i < days.length - 1; i++) {
        const a = grid.querySelector('[data-day="' + days[i] + '"]');
        const b = grid.querySelector('[data-day="' + days[i + 1] + '"]');
        if (!a || !b) continue;
        const p1 = cellCenter(a, grid);
        const p2 = cellCenter(b, grid);
        const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
        line.setAttribute("x1", String(p1.x));
        line.setAttribute("y1", String(p1.y));
        line.setAttribute("x2", String(p2.x));
        line.setAttribute("y2", String(p2.y));
        line.setAttribute("stroke", released ? "#88b6f8" : "#2d609c");
        line.setAttribute("stroke-width", "2");
        line.setAttribute("stroke-dasharray", "5 5");
        line.setAttribute("stroke-linecap", "round");
        line.setAttribute("opacity", released ? "0.55" : "0.85");
        svg.appendChild(line);
      }
    });
  }

  function renderMonth(animate) {
    const copy = t();
    const y = view.getFullYear();
    const m = view.getMonth();
    const card = $("calCard");
    const grid = $("grid");
    if (!grid) return;

    function paintChromeMonth() {
      setText("monthTitle", state.lang === "zh"
        ? (m + 1) + "月 / " + y
        : view.toLocaleString("en", { month: "long", year: "numeric" }));
      const week = $("weekdays");
      if (week) week.innerHTML = copy.week.map(function (w) { return "<span>" + w + "</span>"; }).join("");
    }

    function paintGrid() {
      paintChromeMonth();
      grid.innerHTML = "";
      const first = new Date(y, m, 1);
      const startPad = (first.getDay() + 6) % 7;
      const daysInMonth = new Date(y, m + 1, 0).getDate();
      const today = dayKey(new Date());

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
        btn.setAttribute("data-day", key);
        if (key === today) btn.classList.add("today");
        if (selected === key) btn.classList.add("selected");
        if (entry) {
          btn.classList.add("has-entry");
          if (entry.released) btn.classList.add("calm-thread");
          const sticker = entry.sticker || ClarityOracle.stickerFor(key, entry.tone || "gentle");
          btn.innerHTML = "<span class=\"n\">" + d + "</span><span class=\"sticker\">" + sticker + "</span>";
        } else {
          btn.innerHTML = "<span class=\"n\">" + d + "</span>";
        }
        btn.addEventListener("click", function () { selectDay(key); });
        grid.appendChild(btn);
      }
      requestAnimationFrame(drawThreads);
    }

    if (animate && card) {
      card.classList.remove("flipping-in");
      card.classList.add("flipping-out");
      setTimeout(function () {
        paintGrid();
        card.classList.remove("flipping-out");
        card.classList.add("flipping-in");
        setTimeout(function () { card.classList.remove("flipping-in"); }, 560);
      }, 280);
    } else {
      paintGrid();
    }
  }

  function selectDay(key) {
    selected = key;
    renderMonth(false);
    fillDayDetail(key);
  }

  function moodLabel(id) {
    const moods = (ClarityConfig && ClarityConfig.moods) || [];
    for (let i = 0; i < moods.length; i++) {
      if (moods[i].id === id) return state.lang === "en" ? moods[i].en : moods[i].zh;
    }
    return id;
  }

  function fillDayDetail(key) {
    const detail = $("dayDetail");
    const entry = state.entries[key];
    if (!detail) return;
    if (!entry) {
      detail.hidden = true;
      return;
    }
    detail.hidden = false;
    const d = parseKey(key);
    const title = state.lang === "zh"
      ? ("📖 " + (d.getMonth() + 1) + "月" + d.getDate() + "日 · " + t().detailPrefix)
      : ("📖 " + formatHomeDate(d) + " · " + t().detailPrefix);
    setText("detailTitle", title);
    const moods = (entry.moods || []).map(moodLabel).join(" · ");
    const when = formatClock(new Date(entry.createdAt || Date.now()));
    setText("detailMeta", key + " · " + when + (moods ? " · " + moods : ""));
    setText("detailText", entry.text || "");
    const oracle = $("detailOracle");
    if (oracle) {
      if (entry.oracleZh || entry.oracleEn) {
        oracle.hidden = false;
        setText("detailOracleLine", state.lang === "en" ? (entry.oracleEn || entry.oracleZh) : (entry.oracleZh || entry.oracleEn));
      } else {
        oracle.hidden = true;
      }
    }
    const pledgeBtn = $("btnPledgeFromCal");
    if (pledgeBtn) {
      pledgeBtn.hidden = !!entry.released;
      pledgeBtn.textContent = entry.pledged && !entry.released
        ? (state.lang === "zh" ? "🌷 已承诺 · 等待平静" : "🌷 Pledged · waiting calm")
        : t().willing;
    }
  }

  function paintUI(opts) {
    opts = opts || {};
    paintChrome();
    paintHome();
    renderMonth(!!opts.flip);
    if (selected && state.entries[selected]) fillDayDetail(selected);
    else {
      const dd = $("dayDetail");
      if (dd) dd.hidden = true;
    }
  }

  function priorDays(beforeKey) {
    return Object.keys(state.entries)
      .filter(function (k) { return k < beforeKey; })
      .sort()
      .reverse();
  }

  function showSheet(id, backdropId) {
    const sheet = $(id);
    const bd = $(backdropId);
    if (sheet) sheet.hidden = false;
    if (bd) bd.hidden = false;
  }

  function hideSheet(id, backdropId) {
    const sheet = $(id);
    const bd = $(backdropId);
    if (sheet) sheet.hidden = true;
    if (bd) bd.hidden = true;
  }

  function updateLinkContinueLabel() {
    const copy = t();
    const n = linkMode === "related" ? pendingLinks.length : 0;
    const base = copy.continueWrite;
    const extra = n > 0 ? (" (" + copy.linkedCount.replace("{n}", String(n)) + ")") : "";
    setText("btnLinkContinue", base + extra + " →");
  }

  function renderPriorStickers(key) {
    const box = $("priorStickers");
    if (!box) return;
    const priors = priorDays(key);
    if (linkMode !== "related" || !priors.length) {
      box.hidden = true;
      box.innerHTML = "";
      return;
    }
    box.hidden = false;
    const colors = ["#FFF0F0", "#FFF8E7", "#EEF5FF", "#F0FFF4"];
    box.innerHTML = "<p class=\"mood-label\">" + t().priorHead + " · 多选</p>";
    const grid = document.createElement("div");
    grid.className = "prior-grid";
    priors.slice(0, 8).forEach(function (d, i) {
      const e = state.entries[d];
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "prior-sticker" + (pendingLinks.indexOf(d) >= 0 ? " sel" : "");
      btn.style.background = colors[i % colors.length];
      const date = parseKey(d);
      const label = state.lang === "zh"
        ? ((date.getMonth() + 1) + "月" + date.getDate() + "日")
        : date.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      const snippet = (e.text || "").slice(0, 28);
      const sticker = e.sticker || ClarityOracle.stickerFor(d, e.tone || "gentle");
      btn.innerHTML = "<span class=\"pi\">" + sticker + "</span><div class=\"pd\">" + label + "</div><div class=\"ps\">" + snippet + "</div>";
      btn.addEventListener("click", function () {
        const idx = pendingLinks.indexOf(d);
        if (idx >= 0) pendingLinks.splice(idx, 1);
        else pendingLinks.push(d);
        renderPriorStickers(key);
        updateLinkContinueLabel();
      });
      grid.appendChild(btn);
    });
    box.appendChild(grid);
  }

  function openLinkStep() {
    const today = dayKey(new Date());
    selected = today;
    linkMode = Object.keys(state.entries).some(function (k) { return k < today; }) ? "related" : "fresh";
    pendingLinks = [];
    const fresh = $("choiceFresh");
    const related = $("choiceRelated");
    if (fresh) fresh.classList.toggle("selected", linkMode === "fresh");
    if (related) related.classList.toggle("selected", linkMode === "related");
    renderPriorStickers(today);
    updateLinkContinueLabel();
    showSheet("sheetLink", "linkBackdrop");
  }

  function openWriteSheet() {
    hideSheet("sheetLink", "linkBackdrop");
    writeMoods = (state.entries[selected] && state.entries[selected].moods)
      ? state.entries[selected].moods.slice()
      : [];
    const ta = $("entryText");
    if (ta) ta.value = (state.entries[selected] && state.entries[selected].text) || "";
    setText("charCount", String((ta && ta.value.length) || 0));
    renderMoodChips();
    showSheet("sheetWrite", "writeBackdrop");
  }

  function renderMoodChips() {
    const box = $("moodChips");
    if (!box) return;
    const moods = (ClarityConfig && ClarityConfig.moods) || [];
    box.innerHTML = "";
    moods.forEach(function (m) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "mood-chip" + (writeMoods.indexOf(m.id) >= 0 ? " sel" : "");
      btn.textContent = m.icon + " " + (state.lang === "en" ? m.en : m.zh);
      btn.addEventListener("click", function () {
        const i = writeMoods.indexOf(m.id);
        if (i >= 0) writeMoods.splice(i, 1);
        else writeMoods.push(m.id);
        renderMoodChips();
      });
      box.appendChild(btn);
    });
  }

  function closeWrite() {
    hideSheet("sheetWrite", "writeBackdrop");
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

  function assignOracle(entry, seed) {
    const revealed = ClarityOracle.reveal(seed);
    entry.tone = revealed.tone;
    entry.category = revealed.tone;
    entry.oracleZh = revealed.oracleZh;
    entry.oracleEn = revealed.oracleEn;
    entry.oracleArt = revealed.art;
    entry.sticker = ClarityOracle.stickerFor(entry.dayKey, revealed.tone);
    return revealed;
  }

  async function persistEntry(opts) {
    opts = opts || {};
    const copy = t();
    if (!selected) selected = dayKey(new Date());
    const ta = $("entryText");
    const text = ta ? ta.value.trim() : "";
    if (!text) {
      toast(copy.needText);
      return null;
    }

    const isNew = !state.entries[selected];
    let linked = [];
    if (isNew) {
      if (linkMode === "related") {
        linked = pendingLinks.slice();
        if (Object.keys(state.entries).length > 0 && linked.length === 0 && priorDays(selected).length > 0) {
          // allow related with zero only if user switched? require pick when related selected & priors exist
          toast(copy.pickLink);
          return null;
        }
      } else {
        linked = [];
      }
    } else {
      linked = state.entries[selected].linkedDays || [];
    }

    let threadLocalId = null;
    if (linked.length) {
      const ids = linked.map(function (d) {
        return state.entries[d] && state.entries[d].threadLocalId;
      }).filter(function (x) { return x != null; });
      threadLocalId = ids.length ? Math.min.apply(null, ids) : localThreadSeq++;
      linked.forEach(function (d) {
        if (state.entries[d]) state.entries[d].threadLocalId = threadLocalId;
      });
    } else {
      threadLocalId = (state.entries[selected] && state.entries[selected].threadLocalId) || localThreadSeq++;
    }

    const prev = state.entries[selected] || {};
    const entry = {
      dayKey: selected,
      text: text,
      linkedDays: linked,
      threadLocalId: threadLocalId,
      moods: writeMoods.slice(),
      tone: prev.tone || null,
      category: prev.category || null,
      oracleZh: prev.oracleZh || null,
      oracleEn: prev.oracleEn || null,
      oracleArt: prev.oracleArt || null,
      sticker: prev.sticker || null,
      createdAt: prev.createdAt || Date.now(),
      released: !!prev.released,
      chainThreadId: prev.chainThreadId || null,
      pledged: !!prev.pledged
    };

    if (!entry.oracleZh || opts.freshOracle) {
      assignOracle(entry, Date.now() + text.length * 17);
    }

    state.entries[selected] = entry;
    ClarityStorage.save(state);
    return entry;
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

  function showOracleReveal(dayKeyStr) {
    const entry = state.entries[dayKeyStr];
    if (!entry) return;
    pendingOracleDay = dayKeyStr;
    const reveal = $("oracleReveal");
    const card = $("oracleCard");
    if (!reveal || !card) return;
    const tone = entry.tone || "roast";
    const art = entry.oracleArt || ClarityOracle.ART[tone] || "oracle-roast.webp";
    card.style.backgroundImage = "url('./art/" + art + "')";
    const label = ClarityOracle.LABELS[tone]
      ? (state.lang === "en" ? ClarityOracle.LABELS[tone].en : ClarityOracle.LABELS[tone].zh)
      : "";
    setText("oracleCardLabel", label);
    setText("oracleCardLine", state.lang === "en" ? (entry.oracleEn || entry.oracleZh) : (entry.oracleZh || entry.oracleEn));
    reveal.hidden = false;
  }

  function hideOracleReveal() {
    const reveal = $("oracleReveal");
    if (reveal) reveal.hidden = true;
    pendingOracleDay = null;
    paintUI();
  }

  async function saveOnly() {
    const entry = await persistEntry({ freshOracle: !state.entries[selected] });
    if (!entry) return;
    toast(t().saved);
    closeWrite();
    showOracleReveal(selected);
    if (canUseChain()) {
      try {
        await chainTouchForDay(selected);
        toast(t().saved + " · " + t().txTouch);
      } catch (e) {
        toast(t().saved + " · " + (e.shortMessage || e.message || String(e)));
      }
    }
  }

  async function pledgeFromWrite() {
    const entry = await persistEntry({ freshOracle: !state.entries[selected] });
    if (!entry) return;
    await doPledge(selected);
    closeWrite();
    showOracleReveal(selected);
  }

  async function doPledge(key) {
    const copy = t();
    if (!key || !state.entries[key]) {
      toast(copy.needText);
      return;
    }
    const group = ClarityGraph.threadDays(state.entries, key);
    group.forEach(function (d) {
      if (state.entries[d]) state.entries[d].pledged = true;
    });
    ClarityStorage.save(state);

    if (state.demo || !canUseChain()) {
      toast(copy.pledgedDemo);
      paintUI();
      return;
    }
    try {
      let id = state.entries[key].chainThreadId;
      if (!id) id = await chainTouchForDay(key);
      await ClarityWallet.pledgeLetGo(id);
      toast(copy.txPledge);
    } catch (e) {
      toast(e.shortMessage || e.message || String(e));
    }
    paintUI();
  }

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
    toast(touched ? copy.fastForwarded : copy.fastForwardEmpty);
  }

  function makeEntry(key, text, extra) {
    const entry = Object.assign({
      dayKey: key,
      text: text,
      linkedDays: [],
      threadLocalId: 1,
      moods: [],
      tone: null,
      category: null,
      oracleZh: null,
      oracleEn: null,
      oracleArt: null,
      sticker: null,
      createdAt: Date.now(),
      released: false,
      chainThreadId: null,
      pledged: false
    }, extra || {});
    if (!entry.oracleZh) assignOracle(entry, key.split("").reduce(function (s, c) { return s + c.charCodeAt(0); }, 0) + text.length);
    return entry;
  }

  function seedSample() {
    const today = new Date();
    const d1 = shiftDay(today, -5);
    const d2 = shiftDay(today, -3);
    const d3 = shiftDay(today, -2);
    const calm = shiftDay(today, -8);
    state.entries = {};
    state.entries[d1] = makeEntry(d1, "他已读不回，是不是不爱我了", { threadLocalId: 1, moods: ["anxious", "rumination"] });
    state.entries[d2] = makeEntry(d2, "想主动发消息，又怕显得很着急", { threadLocalId: 1, linkedDays: [d1], moods: ["overthink"] });
    state.entries[d3] = makeEntry(d3, "看到他朋友圈，有点嫉妒", {
      threadLocalId: 1,
      linkedDays: [d1, d2],
      pledged: true,
      moods: ["wronged"]
    });
    state.entries[calm] = makeEntry(calm, "以前想复合，现在决定好好生活", {
      threadLocalId: 2,
      linkedDays: [],
      pledged: true,
      released: true,
      moods: ["hug"]
    });
    localThreadSeq = 3;
    state.demo = true;
    ClarityStorage.save(state);
    view = new Date();
    selected = d3;
    paintUI();
    fillDayDetail(d3);
    toast(t().seeded);
  }

  async function connectWallet() {
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

  function finishOpening() {
    ClarityStorage.markOpeningSeen();
    const opening = $("opening");
    const shell = $("appShell");
    if (opening) opening.hidden = true;
    if (shell) shell.hidden = false;
    paintUI();
    setPage(0);
  }

  function startOpening() {
    const opening = $("opening");
    const shell = $("appShell");
    if (ClarityStorage.openingSeenToday()) {
      if (opening) opening.hidden = true;
      if (shell) shell.hidden = false;
      return;
    }
    if (shell) shell.hidden = true;
    if (opening) opening.hidden = false;
  }

  function on(id, event, handler) {
    const el = $(id);
    if (el) el.addEventListener(event, handler);
  }

  function bind() {
    on("btnSkip", "click", finishOpening);
    on("opening", "click", function (e) {
      if (e.target && e.target.id === "btnSkip") return;
      finishOpening();
    });

    on("btnLang", "click", function () {
      state.lang = state.lang === "zh" ? "en" : "zh";
      ClarityStorage.save(state);
      paintUI();
      if (!$("sheetWrite").hidden) renderMoodChips();
      if (!$("sheetLink").hidden) renderPriorStickers(selected || dayKey(new Date()));
    });
    on("btnWallet", "click", function () { connectWallet(); });

    document.querySelectorAll(".dot").forEach(function (dot) {
      dot.addEventListener("click", function () {
        setPage(Number(dot.getAttribute("data-dot")));
      });
    });
    on("swipeHint", "click", function () { setPage(pageIndex === 0 ? 1 : 0); });
    bindSwipe();

    on("btnStartWrite", "click", function () {
      const today = dayKey(new Date());
      selected = today;
      if (state.entries[today]) {
        openWriteSheet();
      } else if (priorDays(today).length === 0) {
        linkMode = "fresh";
        pendingLinks = [];
        openWriteSheet();
      } else {
        openLinkStep();
      }
    });
    on("btnSeed", "click", seedSample);
    on("btnFastForward", "click", fastForward);

    on("choiceFresh", "click", function () {
      linkMode = "fresh";
      pendingLinks = [];
      $("choiceFresh").classList.add("selected");
      $("choiceRelated").classList.remove("selected");
      renderPriorStickers(selected || dayKey(new Date()));
      updateLinkContinueLabel();
    });
    on("choiceRelated", "click", function () {
      linkMode = "related";
      $("choiceRelated").classList.add("selected");
      $("choiceFresh").classList.remove("selected");
      renderPriorStickers(selected || dayKey(new Date()));
      updateLinkContinueLabel();
    });
    on("btnLinkContinue", "click", function () {
      if (linkMode === "related" && pendingLinks.length === 0 && priorDays(selected || dayKey(new Date())).length > 0) {
        toast(t().pickLink);
        return;
      }
      openWriteSheet();
    });
    on("btnLinkLater", "click", function () { hideSheet("sheetLink", "linkBackdrop"); });
    on("btnCloseLink", "click", function () { hideSheet("sheetLink", "linkBackdrop"); });
    on("linkBackdrop", "click", function () { hideSheet("sheetLink", "linkBackdrop"); });

    on("btnCloseWrite", "click", closeWrite);
    on("writeBackdrop", "click", closeWrite);
    on("entryText", "input", function () {
      const ta = $("entryText");
      setText("charCount", String((ta && ta.value.length) || 0));
    });
    on("btnSaveOnly", "click", function () { saveOnly(); });
    on("btnPledge", "click", function () { pledgeFromWrite(); });

    on("btnOpenOracle", "click", function () {
      showOracleReveal(dayKey(new Date()));
    });
    on("btnDetailOracle", "click", function () {
      if (selected) showOracleReveal(selected);
    });
    on("btnTuckOracle", "click", function (e) {
      e.stopPropagation();
      const k = pendingOracleDay || selected || dayKey(new Date());
      hideOracleReveal();
      setPage(1);
      selectDay(k);
    });
    on("oracleReveal", "click", function (e) {
      if (e.target && e.target.id === "btnTuckOracle") return;
      hideOracleReveal();
    });

    on("prevMonth", "click", function () {
      view = new Date(view.getFullYear(), view.getMonth() - 1, 1);
      paintUI({ flip: true });
    });
    on("nextMonth", "click", function () {
      view = new Date(view.getFullYear(), view.getMonth() + 1, 1);
      paintUI({ flip: true });
    });
    on("btnToday", "click", function () {
      view = new Date();
      selected = dayKey(view);
      paintUI({ flip: true });
      if (state.entries[selected]) fillDayDetail(selected);
    });
    on("btnPledgeFromCal", "click", function () {
      if (selected) doPledge(selected);
    });
  }

  function init() {
    Object.keys(state.entries).forEach(function (k) {
      const e = state.entries[k];
      if (e && e.threadLocalId && e.threadLocalId >= localThreadSeq) localThreadSeq = e.threadLocalId + 1;
      // migrate old category→tone if needed
      if (e && !e.tone && e.oracleZh) {
        e.tone = "roast";
        e.sticker = ClarityOracle.stickerFor(k, e.tone);
      }
    });
    bind();
    startOpening();
    if (!$("appShell").hidden) paintUI();
    clockTimer = setInterval(function () {
      if ($("appShell") && !$("appShell").hidden) {
        setText("homeClock", formatClock(new Date()));
        applyBackground();
      }
    }, 30000);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
