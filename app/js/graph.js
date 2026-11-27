// Connected components over day links. One component = one thread (一团).
window.ClarityGraph = (function () {
  function components(entries) {
    const days = Object.keys(entries || {});
    const parent = {};
    days.forEach((d) => { parent[d] = d; });

    function find(x) {
      if (parent[x] !== x) parent[x] = find(parent[x]);
      return parent[x];
    }
    function union(a, b) {
      const ra = find(a);
      const rb = find(b);
      if (ra === rb) return;
      if (ra < rb) parent[rb] = ra;
      else parent[ra] = rb;
    }

    days.forEach((d) => {
      const links = entries[d].linkedDays || [];
      links.forEach((other) => {
        if (entries[other]) union(d, other);
      });
      if (entries[d].threadLocalId != null) {
        days.forEach((o) => {
          if (entries[o].threadLocalId === entries[d].threadLocalId) union(d, o);
        });
      }
    });

    const groups = {};
    days.forEach((d) => {
      const r = find(d);
      if (!groups[r]) groups[r] = [];
      groups[r].push(d);
    });
    return groups;
  }

  function threadDays(entries, dayKey) {
    const groups = components(entries);
    for (const root of Object.keys(groups)) {
      if (groups[root].includes(dayKey)) return groups[root].slice().sort();
    }
    return [dayKey];
  }

  function onChainThreadIds(entries, dayKeys) {
    const ids = new Set();
    dayKeys.forEach((d) => {
      const e = entries[d];
      if (e && e.chainThreadId) ids.add(Number(e.chainThreadId));
    });
    return Array.from(ids).filter((n) => n > 0);
  }

  return { components, threadDays, onChainThreadIds };
})();
