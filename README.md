# Reactive Builder Camp

ETHPanda × Reactive Network 两周共学（2026-11-16 → 11-29），对接 Reactive Omni Buildathon。

- `starter/` — clone 即用的「事件 → react() → 回调」三步走模板（Foundry），已在 Sepolia ↔ Lasna 实测跑通
- `docs/cheatsheet.md` — 网络 / 地址 / 费用 / Omni 写法速查表
- `docs/faq.md` — 学员 FAQ
- `docs/d5-2026-11-20-cron.md` — D5（11/20）定时任务：Cron100 → Sepolia，最多 2 次后退订
- `docs/spread-first-path.md` — Phase A：两个教学模拟池的价差检测，并在 Sepolia 记下机会。尚未上链

## Phase A 价差路径（教学模拟，非真实市场）

这不是官方 CampOrigin / CampReactive / CampCallback，也不是 D5 Cron 实验。两个池都在 `SimDualAmm` 里，用内部储备记账，没有真实 ERC-20，也没有 swap。Phase A 只检测价差并记录。同链原子套利和跨链套利都还没做。

```
Sepolia 教学模拟双池 SimDualAmm（非真实市场）
  调用 nudgeReserves(poolId, r0, r1)
        │  emit ReservesUpdated(poolId, r0, r1)
        ▼
Lasna SpreadReactive.react(log)
  更新该池储备，比较两个池的价差
  价差 < 阈值：直接 return（不回调、不 revert）
  价差 >= 阈值：SYSTEM.requestCallbackV_1_0
        │  Sepolia Callback Proxy 投递
        ▼
Sepolia OpportunityLedger.recordOpportunity(...)
  把机会打包写入一个存储槽，发出 OpportunityRecorded
```

部署和本地测试见 `docs/spread-first-path.md`。三笔链上交易要等本机用 gitignored `.env` 跑完 `starter/script/spread-lab.ps1` 再填，这里不编造哈希。

报名：https://web3career.build/zh/programs/reactive-builder-camp
黑客松：https://dorahacks.io/hackathon/reactive-omni-buildathon/detail

本仓库的模板和文档由 AI 辅助编写，经人工审阅与链上实测。
