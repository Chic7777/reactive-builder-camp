// Oracle by REPLY TONE class (not entry keyword). Original copy. No AI / network.
window.ClarityOracle = (function () {
  const TONES = ["wakeup", "question", "roast", "gentle", "life"];

  const ART = {
    wakeup: "oracle-wakeup.webp",
    question: "oracle-question.webp",
    roast: "oracle-roast.webp",
    gentle: "oracle-gentle.webp",
    life: "oracle-life.webp"
  };

  const LABELS = {
    wakeup: { zh: "当头棒喝", en: "Wake-up call" },
    question: { zh: "反问清醒", en: "Clearing question" },
    roast: { zh: "毒舌吐槽", en: "Sassy roast" },
    gentle: { zh: "温柔托底", en: "Gentle hold" },
    life: { zh: "拉回生活", en: "Back to life" }
  };

  const BANK = {
    wakeup: {
      zh: [
        "他不是忙，是不想。",
        "别在垃圾堆里找安全感。",
        "已读不回不是考题，你不必交卷。",
        "冷淡可以是答案。先把自己暖着。",
        "你在等人的回信，生活在等你回来。",
        "把手机翻面。屏幕不会比你更着急。",
        "清醒的第一秒：他没有你想象中那么在意。",
        "别把沉默翻译成深情。"
      ],
      en: [
        "He's not busy—he doesn't want to.",
        "Don't dig for safety in a trash pile.",
        "Unread is not a test. You don't owe silence an essay.",
        "Cold can be an answer. Warm yourself first.",
        "You're waiting on a reply. Life is waiting on you.",
        "Flip the phone. The screen isn't more urgent than you.",
        "Clarity second one: he cares less than your mind claims.",
        "Don't translate silence into devotion."
      ]
    },
    question: {
      zh: [
        "是事实如此，还是委屈小剧场又在加戏？",
        "你想要的是他，还是「被选择」的感觉？",
        "如果朋友经历同样的事，你会怎么劝？",
        "这份紧张，有多少来自他，有多少来自旧伤口？",
        "你是在连接，还是在止痒？",
        "明天的你会感谢今晚的催促吗？",
        "不回你的人，配占用你的睡眠吗？",
        "你愿意为不确定再付多少情绪租金？"
      ],
      en: [
        "Is it true—or is the drama theater improvising again?",
        "Do you want him, or the feeling of being chosen?",
        "If a friend lived this, what would you tell her?",
        "How much of this ache is him—and how much is an old wound?",
        "Is this connection, or itch-scratching?",
        "Will tomorrow-you thank tonight's urgency?",
        "Does someone who won't reply deserve your sleep?",
        "How much emotional rent will you keep paying for maybe?"
      ]
    },
    roast: {
      zh: [
        "别脑补了，他只是无聊，不是爱你。",
        "回得慢不是在忙，是在想怎么敷衍。",
        "你的价值不由他的回复速度计价。",
        "比较是偷走今天的小偷。",
        "屏幕里的甜蜜常常是精修。",
        "同一个人连发三次「在吗」，焦虑会给你加班费吗？",
        "他把聊天挂起，地球照转。",
        "你不是客服，不必秒回自己的不安。"
      ],
      en: [
        "Stop the fanfic—he's bored, not in love.",
        "Slow replies aren't busy; they're drafting brush-offs.",
        "Your worth isn't priced by his reply speed.",
        "Comparison is a pickpocket for today.",
        "Feed-perfect romance is often retouched.",
        "Three 'you there?' texts don't pay anxiety overtime.",
        "He paused the chat. The planet kept spinning.",
        "You're not customer support for your own panic."
      ]
    },
    gentle: {
      zh: [
        "你已经很努力了，先喝口水吧。",
        "敏感不是缺陷，是雷达。学会调音量。",
        "允许混乱，也允许明天更轻一点。",
        "你配被好好对待，从对自己开始。",
        "眼泪可以有，拥抱也可以有。",
        "把骂自己的话，换成你会跟朋友说的话。",
        "慢慢来，清醒是温柔的事。",
        "今晚先把自己安顿好，明天的太阳会等你。"
      ],
      en: [
        "You've tried hard enough. Drink water.",
        "Sensitivity is radar—learn the volume knob.",
        "You're allowed to spiral—and to be lighter tomorrow.",
        "You deserve care. Start with yourself.",
        "Tears are allowed. So are hugs.",
        "Replace the insult you'd never say to a friend.",
        "Go slow. Clarity can be gentle.",
        "Settle yourself tonight. Morning will wait."
      ]
    },
    life: {
      zh: [
        "先联系一下自己的晚饭。",
        "把「再试一次」换成「先把今天过完」。",
        "出去走走，风比对话框诚实。",
        "整理一下桌面，也是在整理心。",
        "给自己定一个小小的、立刻能做的好事。",
        "睡觉、洗澡、拉伸——比刷新聊天有用。",
        "把能量花在会回应你的人与事上。",
        "继续好好生活——这句可以盖章重复。"
      ],
      en: [
        "Text your dinner plans to yourself first.",
        "Swap 'one more try' for 'finish living today'.",
        "Take a walk. Wind is more honest than chat.",
        "Tidy the desk—you're tidying the mind too.",
        "Do one tiny kindness you can finish now.",
        "Sleep, shower, stretch—better than refreshing chat.",
        "Spend energy on what answers you back.",
        "Keep living well—stamp that line again."
      ]
    }
  };

  const STICKERS = ["🌱", "☁️", "🍓", "🌻", "🩹", "🍵", "⭐", "🌙", "🍬", "🌷", "🫧", "💊"];

  function pickTone(seed) {
    const i = Math.abs(Number(seed) || Date.now()) % TONES.length;
    return TONES[i];
  }

  function pickLine(tone, lang, seed) {
    const pack = BANK[tone] || BANK.roast;
    const lines = pack[lang === "en" ? "en" : "zh"];
    const i = Math.abs(Number(seed) || 1) % lines.length;
    return { tone: tone, line: lines[i], index: i, label: LABELS[tone], art: ART[tone] };
  }

  function reveal(seed) {
    const tone = pickTone(seed);
    const zh = pickLine(tone, "zh", seed);
    const en = pickLine(tone, "en", seed + 17);
    return {
      tone: tone,
      art: ART[tone],
      labelZh: LABELS[tone].zh,
      labelEn: LABELS[tone].en,
      oracleZh: zh.line,
      oracleEn: en.line
    };
  }

  function stickerFor(dayKey, tone) {
    const n = String(dayKey || "").split("").reduce(function (s, c) { return s + c.charCodeAt(0); }, 0);
    const idx = Math.abs(n + (TONES.indexOf(tone) + 1) * 3) % STICKERS.length;
    return STICKERS[idx];
  }

  return { TONES, ART, LABELS, BANK, reveal, pickLine, stickerFor };
})();
