// Original copy bank. Not copied from any existing oracle deck.
// Runtime: local keyword match only. No AI, no network.

window.ClarityOracle = (function () {
  const BANK = {
    ignored: {
      zh: [
        "已读不回不是考题，你不必交卷。",
        "他把聊天挂起，世界没有因此停转。",
        "冷淡可以是答案，也可以只是他忙。你先把自己暖着。",
        "等回信的那几分钟，请先喝口水。",
        "你的价值不由他的回复速度计价。",
        "静音对方之前，先静音催促自己的那句『快看看』。",
        "没有回，不代表你写错了。有时只是他没写。",
        "把手机翻面。屏幕不会比你更着急。"
      ],
      en: [
        "Unread is not a test. You don't owe an answer to silence.",
        "He paused the chat. The planet kept spinning.",
        "Cold can mean busy, or mean no. Warm yourself first.",
        "While you wait, drink water like it's a tiny rebellion.",
        "Your worth is not priced by his reply speed.",
        "Mute the urge to refresh before you mute anyone else.",
        "No reply doesn't mean you wrote it wrong.",
        "Flip the phone. The screen isn't more urgent than you."
      ]
    },
    rumination: {
      zh: [
        "脑内法庭休庭。证据不足，驳回『他是不是不爱我』。",
        "胡思乱想很勤快，真相通常很懒。",
        "把『万一』写成购物清单，你会发现它一件也买不到。",
        "爱不爱不是脑内直播能播清楚的。",
        "你在排练一千种结局，现实还没开场。",
        "怀疑很吵，事实很安静。先听安静的。",
        "同一段聊天重播三遍，不会多出一句台词。",
        "把问号放下。它不会自己变成句号。"
      ],
      en: [
        "Court adjourned. Insufficient evidence for 'does he love me'.",
        "Overthinking works overtime. Truth is often lazy.",
        "Write your what-ifs as a shopping list—you can't buy any of them.",
        "Love isn't clear from a private brain livestream.",
        "You're rehearsing endings. Reality hasn't started.",
        "Doubt is loud. Facts are quiet. Prefer quiet.",
        "Replaying the chat won't add a new line.",
        "Put the question mark down. It won't become a period alone."
      ]
    },
    urgeToText: {
      zh: [
        "想发的那句，先存草稿箱过夜。",
        "主动一次可以，连环追问像给焦虑加班。",
        "手指比心快时，先坐回去。",
        "你不是客服，不必秒回自己的不安。",
        "发之前问：这是连接，还是止痒？",
        "空白气泡也是一种边界。",
        "把『在吗』换成『我先好好过今晚』。",
        "想联系时，先联系一下自己的晚饭。"
      ],
      en: [
        "Park that text in drafts overnight.",
        "One reach-out is fine. A chase is unpaid overtime for anxiety.",
        "When fingers outrun the heart, sit back down.",
        "You're not customer support for your own panic.",
        "Ask first: connection, or itch-scratch?",
        "An empty bubble can be a boundary.",
        "Swap 'you there?' for 'I'll have a good night first'.",
        "Before you text him, text your dinner plans to yourself."
      ]
    },
    jealousy: {
      zh: [
        "比较是偷走今天的小偷。",
        "她的故事不是你的成绩单。",
        "嫉妒来访时，请它坐一下，别让它开车。",
        "别人被看见，不减少你被爱的配额。",
        "屏幕里的甜蜜常常是精修。",
        "把『凭什么』改成『我还缺什么对自己好』。",
        "吃醋可以承认，不必变成行动号召。",
        "你的生活不是他的社交动态附庸。"
      ],
      en: [
        "Comparison is a pickpocket for today.",
        "Her story isn't your report card.",
        "When jealousy visits, offer a chair—don't hand it the keys.",
        "Someone else being seen doesn't shrink your love quota.",
        "Feed-perfect romance is often retouched.",
        "Trade 'why them' for 'what kindness do I owe myself'.",
        "Admit the envy. Don't elect it as campaign manager.",
        "Your life is not a footnote to his feed."
      ]
    },
    reunion: {
      zh: [
        "复合是选项，不是默认按钮。",
        "回去之前，先数清离开时放下的那些疼。",
        "旧消息翻出来，不会变成新答案。",
        "想复合时，先复合一下和自己的作息。",
        "同一扇门敲第三次，门很少变得更温柔。",
        "怀念的是温度，还是熟悉的伤？",
        "『再试一次』需要新条件，不是旧惯性。",
        "把复合愿望写成：我愿先把今天过完。"
      ],
      en: [
        "Getting back together is an option, not a default button.",
        "Before you return, count what leaving already taught you.",
        "Old threads don't mint new answers.",
        "Miss him? First reunite with your sleep schedule.",
        "Knocking the same door rarely makes it kinder.",
        "Are you missing warmth—or a familiar bruise?",
        "'One more try' needs new terms, not old inertia.",
        "Rewrite the wish as: I will finish living today first."
      ]
    },
    selfDoubt: {
      zh: [
        "你不需要更懂事，才配被好好对待。",
        "自我怀疑很会化妆，打扮成『理性』。",
        "不够好？证据请出示，传闻无效。",
        "你的敏感不是缺陷，是雷达。学会调音量。",
        "把骂自己的话，换成你会对朋友说的话。",
        "被冷落不等于你多余。",
        "你已经在学着放下，这本身就很清醒。",
        "好好生活不是奖赏，是你本来就可以。"
      ],
      en: [
        "You don't need to be easier to deserve care.",
        "Self-doubt wears a costume labeled 'rational'.",
        "Not enough? Show evidence. Rumors don't count.",
        "Sensitivity is radar. Learn the volume knob.",
        "Replace the insult you'd never say to a friend.",
        "Being overlooked doesn't make you extra.",
        "You're already practicing letting go. That's clarity.",
        "Living well isn't a prize. It's allowed."
      ]
    },
    fallback: {
      zh: [
        "今天这一格，先写下来，再决定要不要放。",
        "恋爱脑来访不可耻，留宿太久才贵。",
        "你有权混乱，也有权第二天更轻一点。",
        "把情绪放进日历，比放进他的对话框安全。",
        "毒舌一点：戏剧很贵，平静打折。",
        "先呼吸。格子不会跑。",
        "你在见证自己，不是在审判自己。",
        "继续好好生活——这句可以重复盖章。"
      ],
      en: [
        "Write the square first. Decide release later.",
        "Love-brain visits aren't shameful. Long stays are expensive.",
        "You're allowed to spiral—and to be lighter tomorrow.",
        "A calendar is safer storage than his chat thread.",
        "Sassy truth: drama is pricey; calm is on sale.",
        "Breathe. The cell isn't going anywhere.",
        "You're witnessing yourself, not prosecuting yourself.",
        "Keep living well—stamp that line again."
      ]
    }
  };

  const RULES = [
    { cat: "ignored", keys: ["已读不回", "不回我", "已读", "冷淡", "无视", "seen", "left on read", "ignoring", "cold"] },
    { cat: "rumination", keys: ["胡思乱想", "他爱不爱", "是不是不爱", "会不会不爱", "想多了", "overthink", "does he love", "ruminat"] },
    { cat: "urgeToText", keys: ["想发消息", "想联系", "想找他", "要不要发", "主动", "text him", "message him", "reach out", "should i text"] },
    { cat: "jealousy", keys: ["嫉妒", "吃醋", "比较", "她有", "别人", "jealous", "envy", "compare"] },
    { cat: "reunion", keys: ["复合", "挽回", "再试试", "回到", "ex", "get back", "reunion", "win him"] },
    { cat: "selfDoubt", keys: ["我是不是", "我不够", "嫌弃", "自我", "讨厌自己", "not enough", "insecure", "self doubt", "worthless"] }
  ];

  function detectCategory(text) {
    const t = String(text || "").toLowerCase();
    for (const rule of RULES) {
      for (const k of rule.keys) {
        if (t.includes(k.toLowerCase())) return rule.cat;
      }
    }
    return "fallback";
  }

  function pickLine(category, lang, seed) {
    const pack = BANK[category] || BANK.fallback;
    const lines = pack[lang] || pack.zh;
    const i = Math.abs(Number(seed) || Date.now()) % lines.length;
    return { category, line: lines[i], index: i };
  }

  function speak(text, lang) {
    return pickLine(detectCategory(text), lang === "en" ? "en" : "zh", hash(text));
  }

  function hash(s) {
    let h = 0;
    const str = String(s || "");
    for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) | 0;
    return h;
  }

  return { BANK, detectCategory, pickLine, speak };
})();
