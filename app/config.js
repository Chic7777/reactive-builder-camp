window.ClarityConfig = {
  chainId: 11155111,
  chainName: "Sepolia",
  rpcUrl: "https://ethereum-sepolia-rpc.publicnode.com",
  explorer: "https://sepolia.etherscan.io",
  calendarAddress: "",
  demoWindowMinutes: 5,
  art: {
    morning: "./art/bg-morning.webp",
    noon: "./art/bg-noon.webp",
    night: "./art/bg-night.webp",
    tea: "./art/tea-person.webp",
    icon: "./art/app-icon.webp",
    oracle: {
      wakeup: "./art/oracle-wakeup.webp",
      question: "./art/oracle-question.webp",
      roast: "./art/oracle-roast.webp",
      gentle: "./art/oracle-gentle.webp",
      life: "./art/oracle-life.webp"
    }
  },
  moods: [
    { id: "wronged", zh: "好委屈", en: "Hurt", icon: "🍓" },
    { id: "anxious", zh: "有点焦虑", en: "Anxious", icon: "👒" },
    { id: "rumination", zh: "偷偷内耗", en: "Spiraling", icon: "🫧" },
    { id: "fear", zh: "害怕分开", en: "Afraid", icon: "💔" },
    { id: "overthink", zh: "胡思乱想", en: "Overthink", icon: "☁️" },
    { id: "hug", zh: "想要抱抱", en: "Need a hug", icon: "🧸" }
  ]
};
