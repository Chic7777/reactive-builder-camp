window.ClarityStorage = (function () {
  const KEY = "love-brain-clarity-v2";

  function load() {
    try {
      const raw = localStorage.getItem(KEY);
      if (!raw) {
        // migrate v1 if present
        const v1 = localStorage.getItem("love-brain-clarity-v1");
        if (v1) {
          const old = JSON.parse(v1);
          return {
            entries: old.entries || {},
            lang: old.lang === "en" ? "en" : "zh",
            demo: old.demo !== false
          };
        }
        return { entries: {}, lang: "zh", demo: true };
      }
      const data = JSON.parse(raw);
      return {
        entries: data.entries || {},
        lang: data.lang === "en" ? "en" : "zh",
        demo: data.demo !== false
      };
    } catch {
      return { entries: {}, lang: "zh", demo: true };
    }
  }

  function save(state) {
    localStorage.setItem(KEY, JSON.stringify({
      entries: state.entries || {},
      lang: state.lang === "en" ? "en" : "zh",
      demo: !!state.demo
    }));
  }

  function todayKey() {
    const d = new Date();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return d.getFullYear() + "-" + m + "-" + day;
  }

  // Clear legacy once-per-day opening flag if present
  try {
    localStorage.removeItem("love-brain-opening-date");
  } catch (_) {}

  return { KEY, load, save, todayKey };
})();
