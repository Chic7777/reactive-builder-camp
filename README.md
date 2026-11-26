# Reactive Builder Camp

ETHPanda × Reactive Network 两周共学（2026-11-16 → 11-29），对接 Reactive Omni Buildathon。

要提交的项目是「双向小信号唱片 / Mutual Signal Record」：两个人在测试网上各发一个小信号，时间对上了就记下一次相遇。赛道 2，单人，运行时没有 AI。

- `starter/src/signal/` — 这次要交的合约：信号板、Lasna 判断、Sepolia 账本
- `docs/signal-first-path.md` — 第一条完整链路、部署和尚未上链的三笔交易
- `demo/mutual-signal/` — 图、短诗和一声很短的提示音。预览模式是链下的
- `starter/` — 共学模板（Foundry）。`src/Camp*.sol` 不是提交路径
- `docs/cheatsheet.md` — 网络 / 地址 / 费用 / Omni 写法速查表
- `docs/faq.md` — 学员 FAQ
- `docs/d5-2026-11-20-cron.md` — D5（11/20）定时任务，更早的练习
- `docs/spread-first-path.md` — Phase A 价差练习，留在仓库里，不是这次要交的项目

## 双向小信号唱片（教学/演示，不是 DeFi）

这不是官方 CampOrigin / CampReactive / CampCallback，也不是 D5 Cron，也不是价差路径。链上只有地址、房间号和时间。没有名字，没有句子。诗、图片和声音在网页里。

```
Sepolia SignalBoard
  sendSignal(pairId)
        |
        |  emit SignalSent(sender, pairId, timestamp)
        v
Lasna SignalReactive.react(log)
  remember this person's signal time
  if the other person also signaled within the window: SYSTEM.requestCallbackV_1_0
  else: return (no revert)
        |
        |  Sepolia Callback Proxy
        v
Sepolia EncounterLedger.recordEncounter(...)
  write one slot, emit EncounterUnlocked
        |
        v
Web page shows image / poem / short music
```

两个人必须是两个地址。同一个人发两次不会相遇。部署和本地测试见 `docs/signal-first-path.md`。三笔链上交易要等本机用 gitignored `.env` 跑完 `starter/script/signal-lab.ps1` 再填，这里不编造哈希。

## 出问题怎么办

三条保护：

1. 只有两个不同的地址在时间窗里都发出信号，才会触发回调。
2. 同一个钱包挥两次不会解锁。同一对地址、同一个房间、同样的两个时间也不会解锁第二次。
3. 相遇次数有上限，默认 3 次，最多 5 次。Reactive 合约预存 0.10 lREACT。次数或这笔预算用完，就退订并停下来。

欠款时，给合约转测试币，或调用 `coverDebt()`。目标链回调失败也收费，所以「这次不用记」用 return，不用 revert。

完整的失败表在 [`docs/signal-first-path.md`](docs/signal-first-path.md) 的「失败时会发生什么」。本地测试是 [`starter/test/SignalPath.t.sol`](starter/test/SignalPath.t.sol)。

```bash
cd starter && forge test --match-path test/SignalPath.t.sol --evm-version cancun -vv
```

## 更早的练习（留在仓库里，不是这次要交的项目）

### Phase A 价差路径（教学模拟，非真实市场）

两个池都在 `SimDualAmm` 里，用内部储备记账，没有真实 ERC-20，也没有 swap。Phase A 只检测价差并记录。同链原子套利和跨链套利都还没做。

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

部署和本地测试见 `docs/spread-first-path.md`。

报名：https://web3career.build/zh/programs/reactive-builder-camp
黑客松：https://dorahacks.io/hackathon/reactive-omni-buildathon/detail

本仓库的模板和文档由 AI 辅助编写，经人工审阅与链上实测。
