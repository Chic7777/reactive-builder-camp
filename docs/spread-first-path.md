# Phase A：两个教学模拟池的价差检测，并记下机会

> 这是更早的练习，留在仓库里。黑客松要交的是「双向小信号唱片」，见 `docs/signal-first-path.md`。不要把这条价差路径当作提交项目。

教学模拟，非真实市场。`SimDualAmm` 里的 pool 1 和 pool 2 是两个独立的教学池，储备只在合约内部按恒定乘积记账，不持有真实 ERC-20，也没有 swap。这条路径不承诺收益。Phase A 只做到：制造价差、在 Lasna 判断、在 Sepolia 把机会写入一个存储槽。同链原子试套利和跨链套利都不是这一阶段。运行时没有 AI，AI 只帮助写代码。

这不是官方示例，也不是 D5。不要把下面这些地址填进 `SPREAD_*`：

| 角色 | 地址 | 为什么不能用 |
|---|---|---|
| CampOrigin | `0x6cfe6d08F328b5f067B9ba7F10dc08ca515De950` | 官方共学模板 |
| CampReactive | `0x9a30c9bc9c6dC4101679A735e121e3856cC12FB6` | 官方共学模板 |
| CampCallback | `0x9bebaFE458DaF45faB88Abd42A2Efc36B38A7A32` | 官方共学模板 |
| D5 Reactive | `0xC436b8445cBf6ce233ce83873B3Ac19F5ace04fD` | Cron 实验，已经停 |
| D5 Callback | `0x245FBD3aC14Eb117F6587E7E5e64A8d79AA684a2` | Cron 实验，已经停 |
| 失败的 D5 Reactive | `0x0F3441F4a1302965AeA144885A8242b57350A3d5` | 第一轮 out of gas |
| 失败的 D5 Callback | `0x7665c61e81d98576Cf6eec70Ba9A76961C650e69` | 第一轮 out of gas |

源链和目标链都是 Ethereum Sepolia（11155111）。Reactive 在 Lasna（5318007，`https://lasna-rpc.rnk.dev/`）。同一条链同时当源和目标，是一条完整的「事件 → react() → 回调」，也符合「先不做跨链套利」。

生产编译和 Lasna 部署固定 `evm_version = cancun`（`starter/foundry.toml` 里的 solc 0.8.29）。Amsterdam 只用来量 Sepolia 回调的 SSTORE gas，不能拿去部署。

## 三段链路

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

事件是 `ReservesUpdated(uint8 indexed poolId, uint112 reserve0, uint112 reserve1)`。`poolId` 在 topic1，所以 topic0 稳定，而且至少有一个 indexed 参数。不要照搬 Uniswap V2 的 `Sync`，那个事件没有 indexed，分不清是哪一个池。

`topic0 = keccak256("ReservesUpdated(uint8,uint112,uint112)") = 0x26e357f578552a0562f42bd41dff95e32ea4a3e852b56452baddebe9f4578297`

价格定义是 `reserve1 / reserve0`（每个 token0 值多少 token1）。价差是 `abs(p1 - p2) * 10000 / min(p1, p2)`，单位 bps。默认阈值 100 bps，也就是 1%。默认储备 `10000/10000` 对 `10000/10100` 正好是 100 bps。合约用交叉相乘计算，避免两次除法把这个边界算偏。

`react()` 要等两个池都出现过报价。只来了一个池，或者价差低于阈值，就 `return`。不要 `revert`：revert 一样扣 lREACT。达到阈值才 `SYSTEM.requestCallbackV_1_0`。系统合约地址和 D5 一样，是 `0x8888888888888888888888888888888888888888`。payload 的第一个参数是 `address(0)`，Callback Proxy 会把它换成 Lasna 合约地址。

`CALLBACK_GAS_LIMIT` 是 400000。Sepolia Proxy `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` 从这里扣掉 `_extraGas` 150000 和 `_maxChargeGas` 50000，留给 `recordOpportunity` 的大约是 155800。Amsterdam 计价下，一个从 0 写成非 0 的 SSTORE 大约 108000 gas，所以账本把整次机会打进一个槽。本地 Amsterdam 测量这次写入大约 138305 gas，第二次改同一个槽大约 33485 gas。事件 `OpportunityRecorded` 里的 `price0` / `price1` 是 1e18 原值；槽里的 `price0E6` / `price1E6` 是去掉 12 位之后的摘要。链上证据以事件为准。

最多请求 5 次回调。第 5 次在同一笔 `react()` 里按订阅时的六个参数 `unsubscribe`。账本自己也有一道 5 次上限：满了就 `return`，不 `revert`。同一池的储备如果没变，直接 return，避免把脚本重跑误算成新机会。价差相同但储备来回变的去重，留到 D10。

## 失败时会发生什么

| 情况 | 结果 |
|---|---|
| 价差低于阈值 | `react()` return。不回调，不扣次数 |
| 只更新了一个池 | 同上。另一个池还没有报价 |
| 同一池储备没有变化 | return。不把 5 次额度用掉 |
| 直接调用账本，或 reactive 地址不对 | `onlyServiceProvider` / `onlyCallbackSender` 拒绝 |
| 欠款 `debt > 0` | 网络静默停止投递。给对应合约转测试币，或调用 `coverDebt()` |
| 回调 revert | 失败也收费。所以「已经记够了」用 return，不用 revert |
| 次数用完 | Lasna 退订。之后的 `ReservesUpdated` 不再进来 |

订阅在 `setRecipient`，不在构造函数里。Ledger 还没部署的那几分钟不会烧 lREACT。`stop()` 可以手动退订。

## 文件

| 作用 | 路径 |
|---|---|
| 两个教学池 | `starter/src/spread/SimDualAmm.sol` |
| Lasna 判断 | `starter/src/spread/SpreadReactive.sol` |
| Sepolia 账本 | `starter/src/spread/OpportunityLedger.sol` |
| 拒绝官方地址和 D5 地址 | `starter/src/spread/SpreadGuard.sol` |
| 部署 / 绑定 / nudge / 停止 | `starter/script/DeploySpread.s.sol` |
| 分阶段脚本 | `starter/script/spread-lab.ps1` |
| 只读核对 | `starter/script/verify-spread.ps1` |
| 本地测试 | `starter/test/SpreadPath.t.sol` |

本地测试不连测试网，也不使用钱包 `0x5576d42Fe13888b7f084190934abD07F061225fe` 的私钥。覆盖：低于阈值不回调；达到或超过阈值会记一条；直接调用账本被拒绝；只更新一个池不回调。

```bash
cd starter
forge test --match-path test/SpreadPath.t.sol --evm-version cancun -vv
forge test --match-path test/SpreadPath.t.sol --evm-version amsterdam --match-test test_record_oneSlotAndUnderStipend -vv
forge build --evm-version cancun
```

最后一条把产物留在 Cancun。Amsterdam 那条只证明回调 gas，不能拿它的 bytecode 去 Lasna。

## 部署顺序

在 `starter` 目录。脚本自己把 `C:\Users\laven\.foundry\bin` 加进 PATH，只读 `starter\.env`，命令行不出现私钥。它只用 UTF-8（无 BOM）改 `SPREAD_AMM_ADDR`、`SPREAD_REACTIVE_ADDR`、`SPREAD_LEDGER_ADDR`。金额如果写成 `0.002 ether`，会在调用 forge 之前只把那一行改成 wei。

建议金额：Reactive 合约里放 **0.10 lREACT**（`100000000000000000` wei），Ledger 里放 **0.002 ETH**（`2000000000000000` wei）。0.10 是付给最多 5 次 react 的余额，不含部署交易本身的 gas。

```powershell
Set-Location -LiteralPath "D:\reactive camp\reactive-builder-camp\starter"
powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage preflight
powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage deployAmm
powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage deployReactive
powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage deployLedger
powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage bind
powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage nudge
```

1. `preflight`：编译、测试、只读余额。不广播。
2. `deployAmm`：Sepolia 部署 `SimDualAmm`。
3. `deployReactive`：Lasna 部署并给 `SpreadReactive` 转入 lREACT。这一步还不订阅。
4. `deployLedger`：Sepolia 部署 `OpportunityLedger`。构造参数是 Proxy `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` 和上一步的地址，并转入 ETH。
5. `bind`：回到 Lasna 调 `setRecipient`。这一步才订阅 `ReservesUpdated`。
6. `nudge`：Sepolia 上先改池 1，再改池 2。第二笔才是作业里的源链交易，因为第一笔只有一个池有报价，`react()` 会 return。
7. 等 10–60 秒。
8. `verify`：只读储备、价差、`count` 和 `OpportunityRecorded`。不发交易。

浏览器：<https://sepolia.etherscan.io> 和 <https://lasna.reactscan.net>。

要重来时，只归档本路径的回执，并清空三个 `SPREAD_` 地址。不碰 D5 的 broadcast，也不删其他 `.env` 键：

```powershell
powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage prepareRerun
```

紧急退订不在自动化阶段里。只有 `subscribed` 仍是 true 时才需要：

```powershell
forge script script/DeploySpread.s.sol:StopSpread --rpc-url https://lasna-rpc.rnk.dev/ --broadcast --chain 5318007 --evm-version cancun
```

## 作业要交的三笔交易

尚未上链。下面三格等本机部署成功后再填，不要提前编哈希。

| 项目 | 链接 |
|---|---|
| 源链：第二笔 `nudgeReserves`（两个池都有报价，且价差达到阈值） | `https://sepolia.etherscan.io/tx/` |
| Reactive：这笔日志对应的 Lasna `react` | `https://lasna.reactscan.net/tx/` |
| 目标链：`OpportunityRecorded` 所在的 Sepolia 交易 | `https://sepolia.etherscan.io/tx/` |

核对：

- Ledger `count` 为 1（或不超过 5），`spreadBps` 为 100，`cheapPoolId` 为 1。默认储备下池 1 更便宜。
- Lasna `requested` 增加，`lastSpreadBps` 为 100，`debt` 为 0。
- 事件里的价格是 1e18；`price0E6` 为 1000000，`price1E6` 为 1010000。

`verify` 只打印链上已经存在的交易。脚本不会编造 Lasna react 或 Sepolia 回调的哈希。

## 2026-11-23 只读余额

没有发交易。钱包 `0x5576d42Fe13888b7f084190934abD07F061225fe`：

| 链 | 余额 | base fee | 区块 |
|---|---|---|---|
| Sepolia | 0.015924628343412724 ETH | 15 wei | 12194292 |
| Lasna | 0.134699899997346999 lREACT | 100 gwei | 9039176 |

Sepolia 这边 0.002 ETH 的账本预存加上部署 gas，按 1 gwei 的检查下限也还在 0.0159 ETH 里面。

Lasna 这边不够。`SpreadReactive` 的 CREATE 大约 1.44M gas，再加上交易本身和 forge 默认 130% 的 gas 上限、以及 2 倍 base fee，脚本用 2,300,000 gas 做余额检查。100 gwei 的 2 倍是 200 gwei，这笔上限大约 0.46 lREACT，再加进合约的 0.10，大约要 0.56 lREACT。钱包只有约 0.135。`preflight` 和 `deployReactive` 会停下来，不广播。不要把费用倍数降到 2 以下，也不要去动已经部署的 D5 合约。

补 lREACT 的办法在 `docs/cheatsheet.md` 第 3 节：给水龙头 `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` 转 Sepolia ETH，1 ETH 换 100 lREACT。这是可选的下一步，本仓库没有代发这笔兑换。
