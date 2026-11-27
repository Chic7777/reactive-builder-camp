window.ClarityStorage = (function () {
  const KEY = "love-brain-clarity-v1";

  function load() {
    try {
      const raw = localStorage.getItem(KEY);
      if (!raw) return { entries: {}, lang: "zh", demo: true };
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
    const payload = {
      entries: state.entries || {},
      lang: state.lang === "en" ? "en" : "zh",
      demo: !!state.demo
    };
    localStorage.setItem(KEY, JSON.stringify(payload));
  }

  // entry: { dayKey, text, threadId, category, oracleZh, oracleEn, createdAt, linkedDays[] }
  return { KEY, load, save };
})();
