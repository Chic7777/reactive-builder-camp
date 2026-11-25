# 双向小信号唱片：第一条完整链路

教学/演示，不是社交网络，也不是 DeFi。两个人各自在 Ethereum Sepolia 上对同一个 `pairId` 发一个小信号。Lasna 上的 `react()` 只比较这两次信号的时间。相差不超过窗口，才请求 Sepolia 回调，把这次相遇压进一个存储槽。网页再显示一张图、一首短诗和一声很短的提示音。诗、图和声音不在链上。链上没有名字、句子或私人笔记。

这是要提交的项目，赛道 2：Set It and Forget It。单人。只使用测试网。运行时没有 AI，AI 只帮助写代码。

这不是官方 CampOrigin / CampReactive / CampCallback，也不是 D5 Cron，也不是 `src/spread/` 里的价差练习。不要把下面这些地址填进 `SIGNAL_*`：

| 角色 | 地址 | 为什么不能用 |
|---|---|---|
| CampOrigin | `0x6cfe6d08F328b5f067B9ba7F10dc08ca515De950` | 官方共学模板 |
| CampReactive | `0x9a30c9bc9c6dC4101679A735e121e3856cC12FB6` | 官方共学模板 |
| CampCallback | `0x9bebaFE458DaF45faB88Abd42A2Efc36B38A7A32` | 官方共学模板 |
| D5 Reactive | `0xC436b8445cBf6ce233ce83873B3Ac19F5ace04fD` | Cron 实验，已经停 |
| D5 Callback | `0x245FBD3aC14Eb117F6587E7E5e64A8d79AA684a2` | Cron 实验，已经停 |
| 失败的 D5 Reactive | `0x0F3441F4a1302965AeA144885A8242b57350A3d5` | 第一轮 out of gas |
| 失败的 D5 Callback | `0x7665c61e81d98576Cf6eec70Ba9A76961C650e69` | 第一轮 out of gas |

脚本还会拒绝 `.env` 里已经写着的 `SPREAD_*`、`D5_*`、`ORIGIN_ADDR`、`REACTIVE_ADDR`、`CALLBACK_ADDR`。不要从这些旧合约里转测试币。

源链和目标链都是 Ethereum Sepolia（11155111）。Reactive 在 Lasna（5318007，`https://lasna-rpc.rnk.dev/`）。同一条链同时当源和目标，是一条完整的「事件 → react() → 回调」。

生产编译和 Lasna 部署固定 `evm_version = cancun`（`starter/foundry.toml` 里的 solc 0.8.29）。Amsterdam 只用来量 Sepolia 回调的 SSTORE gas，不能拿去部署。

## 三段链路

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

事件是 `SignalSent(address indexed sender, bytes32 indexed pairId, uint256 timestamp)`。`sender` 在 topic1，`pairId` 在 topic2，`timestamp` 在 data 里。至少有一个 indexed 参数。

`topic0 = keccak256("SignalSent(address,bytes32,uint256)") = 0xc24d07b043cb84a067fca0d14cc2bcb222434a9874ee4f1781a0beac5a5d1b69`

`timestamp` 是信号板所在区块的 `block.timestamp`，也就是 Sepolia 时间。时间窗比较的是两条事件里的这个数，不是 Lasna 的区块时间。两条链的钟不一样。较晚的时间减去较早的时间 `<= WINDOW` 才算遇见，正好等于窗口也算。默认 `WINDOW` 是 3600 秒。差一秒就 `return`，不 `revert`：revert 一样扣 lREACT。

同一个人挥两次只更新自己的时间，不会变成两个人。一个房间只记最近的两个不同地址；第三人到来时，替换更早的那一个。遇见并请求回调之后，这两格记忆会清掉，下一次要两个人重新发。同一对地址、同一个 `pairId`、同样的两个时间再被送进来，不再扣次数。

系统合约和仓库里其他路径一样，是 `0x8888888888888888888888888888888888888888`。payload 的第一个参数是 `address(0)`，Callback Proxy 会把它换成 Lasna 合约地址。

`CALLBACK_GAS_LIMIT` 是 400000。Sepolia Proxy `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` 从这里扣掉 `_extraGas` 150000 和 `_maxChargeGas` 50000，留给 `recordEncounter` 的大约是 155800。两个地址再加一个 `bytes32` 放不进 32 字节，所以账本把次数、两个时间和 `pairId` 的低 88 位打进一个槽。事件 `EncounterUnlocked` 里才有完整地址和完整 `pairId`。链上证据以事件为准。

本地 Amsterdam 测量：第一次写入大约 138801 gas，第二次改同一个槽大约 40893 gas。冷 SSTORE 探针大约 130703 gas。138801 低于测试里留出的 150000，也低于 Proxy 转出的大约 155800。

最多请求 3 次回调（脚本默认，构造参数不能超过 5）。最后一次在同一笔 `react()` 里按订阅时的六个参数 `unsubscribe`。账本自己也有一道 5 次上限：满了就 `return`，不 `revert`。

默认房间暗号是 `mutual-signal`。链上只放它的哈希，不放这段文字：

`keccak256("mutual-signal") = 0x23365b7b7f9f4867a6d0a355957e84dec93920a11d04b48ab7789415b30b55b6`

换成别的暗号时，两边都用 `cast keccak 你的暗号`，并且在 `SIGNAL_WINDOW` 秒内各发一次。

## 两个人怎么发

相遇要两个不同的 `msg.sender`。同一个钱包连发两次不会解锁唱片。

本地测试不连测试网，也不读私钥。`starter/test/SignalPath.t.sol` 用 `vm.prank` 让 `0xA11CE` 和 `0xB0B` 各发一次。覆盖：窗口内两个人会记一条；只有一个人不回调；超出窗口不回调；直接调用账本被拒绝；次数用完后退订，账本满了再进来也 return。

Windows 脚本不生成私钥，也不把私钥打出来：

1. `waveA` 用 `.env` 里的 `PRIVATE_KEY`。这是第一个人。
2. `waveB` 用同一份 gitignored `.env` 里的 `PRIVATE_KEY_2`。这是第二个人，也是作业要交的源链交易。
3. 如果没有 `PRIVATE_KEY_2`，`waveB` 停下来，不广播。把第二个测试账户的私钥写进 `PRIVATE_KEY_2`，给那个地址一点 Sepolia ETH 当 gas，然后再跑。不要把私钥贴进命令行，不要提交 `.env`，也不要从旧实验合约里转钱。

第二下必须落在第一下之后的 `SIGNAL_WINDOW` 秒以内。隔太久就先重跑 `waveA`，再跑 `waveB`。

## 失败时会发生什么

| 情况 | 结果 |
|---|---|
| 只有一个人发过信号 | `react()` return。不回调，不扣次数 |
| 同一个人发两次 | 同上 |
| 两个人的 Sepolia 时间差大于窗口 | return，并发出 `WindowMissed`。不扣次数 |
| 直接调用账本，或 reactive 地址不对 | `onlyServiceProvider` / `onlyCallbackSender` 拒绝 |
| 坏的 payload（地址没排序、pairId 为 0） | 账本 return，不 revert |
| 欠款 `debt > 0` | 网络静默停止投递。给对应合约转测试币，或调用 `coverDebt()` |
| 回调 revert | 失败也收费。所以「已经记够了」用 return，不用 revert |
| 次数用完 | Lasna 退订。之后的 `SignalSent` 不再进来 |

订阅在 `setRecipient`，不在构造函数里。Ledger 还没部署的那几分钟不会烧 lREACT。`stop()` 可以手动退订。每个进来的 `SignalSent` 在退订之前都会让 `react()` 扣一次 lREACT，所以默认只留 3 次相遇，并且预存 0.10 lREACT 当预算。

## 文件

| 作用 | 路径 |
|---|---|
| Sepolia 信号板 | `starter/src/signal/SignalBoard.sol` |
| Lasna 判断 | `starter/src/signal/SignalReactive.sol` |
| Sepolia 账本 | `starter/src/signal/EncounterLedger.sol` |
| 拒绝官方地址和 D5 地址 | `starter/src/signal/SignalGuard.sol` |
| 部署 / 绑定 / 两下信号 / 停止 | `starter/script/DeploySignal.s.sol` |
| 分阶段脚本 | `starter/script/signal-lab.ps1` |
| 只读核对 | `starter/script/verify-signal.ps1` |
| 本地测试 | `starter/test/SignalPath.t.sol` |
| 网页、图、提示音 | `demo/mutual-signal/` |

```bash
cd starter
forge test --match-path test/SignalPath.t.sol --evm-version cancun -vv
forge test --match-path test/SignalPath.t.sol --evm-version amsterdam --match-test test_record_oneSlotAndUnderStipend -vv
forge build --evm-version cancun
```

最后一条把产物留在 Cancun。Amsterdam 那条只证明回调 gas，不能拿它的 bytecode 去 Lasna。

Cancun 上 CREATE 本身大约是：信号板 144555 gas（init code 287 字节），Reactive 1422481 gas（6999 字节），账本 498140 gas（2435 字节）。脚本的余额上限还要加上 21000、init code 的 calldata，以及 forge 默认 130% 的 gas 上限。

## 网页

用浏览器打开 `demo/mutual-signal/index.html`。

预览模式在浏览器里模拟两个人。两下都点过，并且间隔不超过一小时，就显示出图、诗和提示音，并标明这是链下预览。图是仓库里的 SVG。提示音是一段大约 0.8 秒的正弦波，`demo/mutual-signal/assets/chime.wav`，没有歌词，也不是别人的录音。诗是为这个演示写的。

部署之后，把 `SIGNAL_LEDGER_ADDR` 填进「链上唱片」。`count > 0` 就打开同一张唱片，并写明图、诗和声音仍然不在合约里。如果浏览器拦住了 RPC，预览模式还是可用。有钱包时可以让当前账户发一次 `sendSignal`；第二下要换账户。没有钱包就用下面的 PowerShell。

## 部署顺序

在 `starter` 目录。脚本自己把 `C:\Users\laven\.foundry\bin` 加进 PATH，只读 `starter\.env`，命令行不出现私钥。它只用 UTF-8（无 BOM）改 `SIGNAL_BOARD_ADDR`、`SIGNAL_REACTIVE_ADDR`、`SIGNAL_LEDGER_ADDR`，以及窗口、次数、房间号和两个金额。金额如果写成 `0.002 ether`，会在调用 forge 之前只把那一行改成 wei。

建议金额：Reactive 合约里放 **0.10 lREACT**（`100000000000000000` wei），Ledger 里放 **0.002 ETH**（`2000000000000000` wei）。`CALLBACK_GAS_LIMIT` 固定 400000。0.10 是预存在合约里的余额，不含部署交易本身的 gas。

```powershell
Set-Location -LiteralPath "D:\reactive camp\reactive-builder-camp\starter"
powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage preflight
powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage deployBoard
powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage deployReactive
powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage deployLedger
powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage bind
powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage waveA
powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage waveB
powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage verify
```

1. `preflight`：编译、测试、只读余额。不广播。余额不够就停。
2. `deployBoard`：Sepolia 部署 `SignalBoard`。
3. `deployReactive`：Lasna 部署并给 `SignalReactive` 转入 lREACT。这一步还不订阅。
4. `deployLedger`：Sepolia 部署 `EncounterLedger`。构造参数是 Proxy `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` 和上一步的地址，并转入 ETH。
5. `bind`：回到 Lasna 调 `setRecipient`。这一步才订阅 `SignalSent`。
6. `waveA`：主钱包发出第一下。
7. `waveB`：另一个地址发出第二下。这一笔才是作业里的源链交易。
8. 等 10–60 秒。
9. `verify`：只读订阅状态、`pairMemory`、`count` 和 `EncounterUnlocked`。不发交易。

浏览器：<https://sepolia.etherscan.io> 和 <https://lasna.reactscan.net>。

要重来时，只归档本路径的回执，并清空三个 `SIGNAL_` 地址。不碰 D5 或价差路径的 broadcast，也不删其他 `.env` 键：

```powershell
powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage prepareRerun
```

紧急退订不在自动化阶段里。只有 `subscribed` 仍是 true 时才需要：

```powershell
forge script script/DeploySignal.s.sol:StopSignal --rpc-url https://lasna-rpc.rnk.dev/ --broadcast --chain 5318007 --evm-version cancun
```

## 作业要交的三笔交易

尚未上链。下面三格等本机部署成功后再填，不要提前编哈希。

| 项目 | 链接 |
|---|---|
| 源链：第二个人的 `sendSignal`（两个人都在窗口内） | `https://sepolia.etherscan.io/tx/` |
| Reactive：这笔日志对应的 Lasna `react` | `https://lasna.reactscan.net/tx/` |
| 目标链：`EncounterUnlocked` 所在的 Sepolia 交易 | `https://sepolia.etherscan.io/tx/` |

核对：

- Ledger `count` 为 1（或不超过 5）。`earlierAt` 和 `laterAt` 相差不超过 `WINDOW`。
- Lasna `requested` 增加，`debt` 为 0。若默认 3 次还没用完，`subscribed` 仍为 true。
- 事件里的两个地址不同，`pairId` 等于 `SIGNAL_PAIR_ID`。

`verify` 只打印链上已经存在的交易。脚本不会编造 Lasna react 或 Sepolia 回调的哈希。

## 2026-11-25 只读余额

没有发交易。钱包 `0x5576d42Fe13888b7f084190934abD07F061225fe`：

| 链 | 余额 | base fee | 区块 |
|---|---|---|---|
| Sepolia | 0.015924628343412724 ETH | 15 wei | 12207646 |
| Lasna | 0.134699899997346999 lREACT | 100 gwei | 9195414 |

Sepolia 这边 0.002 ETH 的账本预存，加上信号板、账本和第一下信号的 gas 上限，按 1 gwei 的检查下限大约是 0.0035 ETH，还在 0.0159 ETH 里面。第二个人的 gas 要由 `PRIVATE_KEY_2` 那个地址自己出，主钱包的检查不含这一笔。

Lasna 这边不够。`SignalReactive` 的 CREATE 大约 1.42M gas。脚本按 2,200,000 gas 检查部署，再按 600,000 gas 检查 `bind`，费用上限是 2 倍 base fee。100 gwei 的 2 倍是 200 gwei，这两笔上限大约 0.56 lREACT，再加进合约的 0.10，大约要 0.66 lREACT。钱包只有约 0.135。`preflight` 会停下来，不广播。不要把费用倍数降到 2 以下，也不要去动已经部署的 D5 合约。

补 lREACT 的办法在 `docs/cheatsheet.md` 第 3 节：给水龙头 `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` 转 Sepolia ETH，1 ETH 换 100 lREACT。转出 0.01 ETH 大约能换 1 lREACT，主钱包还留下大约 0.006 ETH，够上面的 Sepolia 开支。这是可选的下一步，本仓库没有代发这笔兑换。
