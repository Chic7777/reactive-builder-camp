// Daily self-love blessings. Deterministic by local date. No network.
window.ClarityBlessings = (function () {
  const LIST = [
    { zh: "你值得被好好对待，先从拥抱自己开始呀 🍰", en: "You deserve gentle care—start by hugging yourself 🍰" },
    { zh: "今天的心软一点，世界会跟着松一点。", en: "Soften your heart today; the world softens with it." },
    { zh: "你不是别人的回信速度，你是一整杯温茶。", en: "You are not a reply speed—you are a warm cup of tea." },
    { zh: "把委屈放进手账，留给自己一个轻轻的晚安。", en: "Park the ache in the journal. Keep a soft goodnight for yourself." },
    { zh: "清醒不是冷漠，是先把自己抱紧。", en: "Clarity isn't coldness—it's holding yourself first." },
    { zh: "小情绪也配被听见，像小猫配被摸摸头。", en: "Small feelings deserve to be heard, like a kitten deserves a head pat." },
    { zh: "今天不赶着证明什么，只认真过好这一格。", en: "No proving today—just live this square well." },
    { zh: "你已经在学着放下，这本身就很勇敢。", en: "You're already practicing letting go. That alone is brave." },
    { zh: "阳光会来，你先把窗帘轻轻拉开就好。", en: "Sunlight will come; just ease the curtain open." },
    { zh: "心跳软绵绵 · 恋爱脑退散。", en: "Heartbeat soft · love-brain, please step aside." },
    { zh: "允许自己慢半拍，也不耽误好好生活。", en: "Permission to be half a beat slow—and still live well." },
    { zh: "你不是戏剧的配角，你是自己的主角。", en: "You're not a side character in drama—you're the lead of you." },
    { zh: "把手机翻面，把温柔留给镜子里的人。", en: "Flip the phone. Save tenderness for the person in the mirror." },
    { zh: "今天也要对自己超级心软呀 (｡♥‿♥｡)", en: "Be super soft with yourself today (｡♥‿♥｡)" },
    { zh: "情绪来访可以开门，留下过夜要收租金。", en: "Feelings may visit; overnight stays need rent." },
    { zh: "你配有边界，也配有甜甜的休息。", en: "You deserve boundaries—and sweet rest." },
    { zh: "写下来的泡泡会破，留下的是更轻的你。", en: "Written bubbles pop; what's left is a lighter you." },
    { zh: "不必一次痊愈，慢慢清醒也算赢。", en: "No need to heal in one go—slow clarity still counts." },
    { zh: "把比较放下，把早饭端起来。", en: "Put comparison down. Pick breakfast up." },
    { zh: "你的敏感是雷达，学会调小声就好。", en: "Sensitivity is radar—just learn the volume knob." },
    { zh: "今日清醒猫点：先对自己眨眨眼。", en: "Today's clarity cat tip: wink at yourself first." },
    { zh: "世界很大，但你的手账只装你在意的事。", en: "The world is big; your journal only holds what you care about." },
    { zh: "把「万一」收进抽屉，把「今天」摆上桌。", en: "Drawer the what-ifs. Set today on the table." },
    { zh: "温柔不是纵容别人，是先不苛责自己。", en: "Gentleness isn't indulging others—it's not scolding yourself." },
    { zh: "你正在好好爱自己，这比任何回信都重要。", en: "Loving yourself well matters more than any reply." },
    { zh: "眼泪可以有，明天也依旧可以有光。", en: "Tears are allowed. Tomorrow can still hold light." },
    { zh: "把戏剧留给剧场，把平静留给床铺。", en: "Leave drama to the stage; leave calm to your bed." },
    { zh: "小步离开纠缠，也是华丽的逃亡。", en: "Leaving entanglement in small steps is still a grand escape." },
    { zh: "你不是难搞，你是在学着被好好对待。", en: "You're not difficult—you're learning to be treated well." },
    { zh: "今天，也在好好爱自己。", en: "Today, love yourself well again." }
  ];

  function dayIndex(date) {
    const d = date || new Date();
    const key = d.getFullYear() * 372 + (d.getMonth() + 1) * 31 + d.getDate();
    return Math.abs(key) % LIST.length;
  }

  function forDate(date, lang) {
    const item = LIST[dayIndex(date)];
    return lang === "en" ? item.en : item.zh;
  }

  return { LIST, forDate, dayIndex };
})();
