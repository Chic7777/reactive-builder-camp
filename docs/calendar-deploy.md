# 恋爱脑清醒日历：本地部署指南（新手）

项目路径按你的机器：`D:\reactive camp\reactive-builder-camp`。

只使用测试网。**不要把私钥发给任何人，也不要提交 `starter/.env`。** 本仓库脚本和文档不会读取或打印私钥。AI 只参与开发，运行时没有 AI。

产品说明与三分钟演示稿：[`docs/product-brief.md`](product-brief.md)。

## 你要跑通的三笔交易（作业）

| 顺序 | 种类 | 链 | 你怎么得到 |
|---|---|---|---|
| 1 | 源链 tx | Sepolia | `demoPledge` 或网页里 pledge/touch |
| 2 | Lasna react tx | Lasna | Reactive 自动响应事件 / Cron；用 Reactscan 查合约 |
| 3 | 目标链回调 tx | Sepolia | 窗口过后出现 `ThreadReleased`；用 Etherscan 查日历合约 |

哈希等你本机广播成功后再抄，**不要提前编造**。

## 部署前准备

1. 安装 Foundry，确认 `forge` / `cast` 可用。
2. 打开 `starter/.env`（已 gitignore）。确认有 `PRIVATE_KEY=`（测试钱包）。本项目**只需要一个钱包**。
3. 确认有：
   - `SEPOLIA_RPC_URL`、`LASNA_RPC_URL`
   - `CALLBACK_PROXY=0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4`
   - `ORIGIN_CHAIN_ID=11155111`、`DEST_CHAIN_ID=11155111`
4. 可选日历参数（脚本会写入缺省值）：
   - `CALENDAR_WINDOW=300`（**录 demo 建议 300 秒 = 5 分钟**，方便等完整释放；正式/真实生活约 3 天 = `259200`。合约允许任意正秒数，只要不是 0）
   - `CALENDAR_CRON_CAP=8`
   - `CALENDAR_FUND=1000000000000000`（0.001 ETH，付回调 gas）
   - `CALENDAR_REACTIVE_FUND=50000000000000000`（0.05 lREACT）

金额请写成 **wei 整数**，或 `0.001 ether` 这种形式；不要写裸小数，否则 Foundry 可能丢掉整份 `.env`。

## 一步一步（PowerShell）

在 `starter` 目录：

```powershell
cd "D:\reactive camp\reactive-builder-camp\starter"

powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage preflight
powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage deployCalendar
powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage deployReactive
powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage bind
powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage demoPledge
# 等 CALENDAR_WINDOW 秒之后（录 demo 建议 300；网页演示模式也可用「⏩ 时间快进」）
powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage verify
# 或
powershell -ExecutionPolicy Bypass -File .\script\verify-calendar.ps1
```

`preflight` 会跑 `forge test --match-path test/CalendarPath.t.sol --evm-version cancun`，并检查余额；**余额不够会停住，不会广播**。

把 `.env` 里的 `CALENDAR_ADDR` 抄到 `app/config.js` 的 `calendarAddress`。

网页可直接双击 `app/index.html`（`file://`）预览：点「进入演示模式」会出「演示中」徽章并弹出写日记层；也可「填入示例数据」。演示模式里有不显眼的「⏩ 时间快进」，把已承诺的团当作窗口到期变平静（录屏不必真等 300 秒）。不依赖 `fetch`，ethers CDN 失败也不影响演示。手机宽度优先；电脑上会居中成约 430px 卡片。

## 链上在记什么

- **会记**：thread 的 touch、放下承诺（事件含义：我愿意好好生活）、合并、彻底放下。
- **不记**：日记正文、姓名、聊天记录。正文只在浏览器 `localStorage`。

用户 touch / 新的关联写入会把整团打回「没放下」（清除 pledged 与 released）。只有再次 `pledgeLetGo` 才进入「放下中」；窗口内无新关联写入才「已放下」。未承诺的团不会被 cron 释放。

## 和旧练习的关系

`src/signal/`、`src/spread/`、`src/d5/` 以及官方 `Camp*` **都留在仓库里**，不要删。日历脚本会拒绝把那些地址填进 `CALENDAR_*`。

## 本地测试

```bash
cd starter
forge test --match-path test/CalendarPath.t.sol --evm-version cancun -vv
forge test --match-path test/CalendarPath.t.sol --evm-version amsterdam --match-test test_markReleased_oneSlotAndUnderStipend -vv
```

Amsterdam 只用来对照 Sepolia 回调 gas；**部署字节码用 cancun**。
