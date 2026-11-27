// 部署后把地址填进来。演示模式不需要地址。
window.ClarityConfig = {
  chainId: 11155111,
  chainName: "Sepolia",
  rpcUrl: "https://ethereum-sepolia-rpc.publicnode.com",
  explorer: "https://sepolia.etherscan.io",
  // 本地部署后填写；留空则只能用演示模式发链上操作提示
  calendarAddress: "",
  // 演示默认窗口说明（真实窗口以链上 WINDOW 为准）
  demoWindowMinutes: 30,
  backgroundsConfig: "./backgrounds/config.json"
};
