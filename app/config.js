// 部署后把 calendarAddress 填进来。演示模式不需要地址。
// 背景配置内联，避免 file:// 下 fetch 失败。
window.ClarityConfig = {
  chainId: 11155111,
  chainName: "Sepolia",
  rpcUrl: "https://ethereum-sepolia-rpc.publicnode.com",
  explorer: "https://sepolia.etherscan.io",
  calendarAddress: "",
  demoWindowMinutes: 5,
  backgrounds: {
    ignored: "ignored.svg",
    rumination: "rumination.svg",
    urgeToText: "urgeToText.svg",
    jealousy: "jealousy.svg",
    reunion: "reunion.svg",
    selfDoubt: "selfDoubt.svg",
    fallback: "fallback.svg"
  }
};
