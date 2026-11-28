// 钱包模块：ethers 未加载时仍可安全存在，演示模式不调用 connect。
window.ClarityWallet = (function () {
  let provider = null;
  let signer = null;
  let contract = null;

  const ABI = [
    "function CLARITY_DEMO() view returns (bool)",
    "function reactive() view returns (address)",
    "function nextThreadId(address user) view returns (uint256)",
    "function openThread() returns (uint256)",
    "function touch(uint256 threadId)",
    "function linkAndTouch(uint256[] threadIds) returns (uint256)",
    "function pledgeLetGo(uint256 threadId)",
    "function isReleased(address user, uint256 threadId) view returns (bool)",
    "function isPledged(address user, uint256 threadId) view returns (bool)",
    "event ThreadTouched(address indexed user, uint256 indexed threadId, uint256 timestamp)"
  ];

  function ethersReady() {
    return typeof window.ethers !== "undefined" && window.ethers && window.ethers.BrowserProvider;
  }

  function threadIdFromReceipt(receipt) {
    if (!contract || !receipt) return null;
    for (const log of receipt.logs || []) {
      try {
        const parsed = contract.interface.parseLog(log);
        if (parsed && parsed.name === "ThreadTouched") return Number(parsed.args.threadId);
      } catch (_) {}
    }
    return null;
  }

  async function connect(cfg) {
    if (!ethersReady()) throw new Error("NO_ETHERS");
    if (!window.ethereum) throw new Error("NO_METAMASK");
    provider = new ethers.BrowserProvider(window.ethereum);
    await provider.send("eth_requestAccounts", []);
    const net = await provider.getNetwork();
    if (Number(net.chainId) !== cfg.chainId) {
      try {
        await window.ethereum.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: "0x" + cfg.chainId.toString(16) }]
        });
      } catch (e) {
        if (e.code === 4902) {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [{
              chainId: "0x" + cfg.chainId.toString(16),
              chainName: cfg.chainName,
              rpcUrls: [cfg.rpcUrl],
              nativeCurrency: { name: "SepoliaETH", symbol: "ETH", decimals: 18 },
              blockExplorerUrls: [cfg.explorer]
            }]
          });
        } else throw e;
      }
      provider = new ethers.BrowserProvider(window.ethereum);
    }
    signer = await provider.getSigner();
    if (cfg.calendarAddress) {
      contract = new ethers.Contract(cfg.calendarAddress, ABI, signer);
    }
    return await signer.getAddress();
  }

  function getContract() { return contract; }
  function getSigner() { return signer; }

  async function openThread() {
    const tx = await contract.openThread();
    const receipt = await tx.wait();
    return { tx, receipt, threadId: threadIdFromReceipt(receipt) };
  }

  async function linkAndTouch(ids) {
    const tx = await contract.linkAndTouch(ids);
    const receipt = await tx.wait();
    return { tx, receipt, threadId: threadIdFromReceipt(receipt) };
  }

  async function touch(id) {
    const tx = await contract.touch(id);
    const receipt = await tx.wait();
    return { tx, receipt, threadId: threadIdFromReceipt(receipt) || Number(id) };
  }

  async function pledgeLetGo(id) {
    const tx = await contract.pledgeLetGo(id);
    return { tx, receipt: await tx.wait() };
  }

  return {
    ethersReady,
    connect,
    getContract,
    getSigner,
    openThread,
    linkAndTouch,
    touch,
    pledgeLetGo,
    threadIdFromReceipt
  };
})();
