# Reactive Builder Camp

ETHPanda × Reactive Network 两周共学（2026-11-16 → 11-29），对接 Reactive Omni Buildathon。

## 本次要交：恋爱脑清醒日历 / Love-Brain Clarity Calendar

赛道 2：Set It and Forget It。单人（Lavie）。测试网。日记正文只在浏览器，永不 on-chain。运行时没有 AI。

> 一张软软的月历，安静见证你把恋爱脑念头放下，继续好好生活。  
> 点日期写恋爱脑 →（第二条起）选择和哪一天有关 → 毒舌神谕 → 「我愿意彻底放下，继续好好生活」→ 安静一段时间后，Reactive 回调把这团标成彻底放下，格子变平静。

完整三分钟演示稿与产品说明：[`docs/product-brief.md`](docs/product-brief.md)

| 路径 | 作用 |
|---|---|
| `app/` | 静态网页（可本地打开 / GitHub Pages），含演示模式 |
| `starter/src/calendar/` | Sepolia 日历 + Lasna Reactive |
| `starter/script/calendar-lab.ps1` | Windows 部署助手（不打印私钥、不代发） |
| `docs/calendar-deploy.md` | 新手逐步部署 |
| `docs/calendar-troubleshoot.md` | 失败对照表 |
| `docs/ai-usage.md` | AI 仅用于开发 |

```
Sepolia ClarityCalendar
  open / touch / linkAndTouch / pledgeLetGo
        |
        |  ThreadTouched / LetGoPledged / ThreadsMerged
        v
Lasna ClarityReactive.react(log)
  记下 Sepolia 事件时间；Cron100 检查窗口
  安静够久 → SYSTEM.requestCallbackV_1_0
        |
        |  Sepolia Callback Proxy
        v
Sepolia ClarityCalendar.markReleased(...)
  标记彻底放下，emit ThreadReleased
```

作业三笔交易：Sepolia 源链（pledge/touch）→ Lasna react → Sepolia 回调。哈希等本机广播后再填，不要编造。

本地测试：

```bash
cd starter && forge test --match-path test/CalendarPath.t.sol --evm-version cancun -vv
```

## 更早的练习（留在仓库里，不是这次要交的项目）

不要删除。日历脚本会拒绝误用这些地址。

- **双向小信号唱片** — `starter/src/signal/`、`docs/signal-first-path.md`、`demo/mutual-signal/`
- **Phase A 价差路径** — `starter/src/spread/`、`docs/spread-first-path.md`
- **D5 Cron** — `starter/src/d5/`、`docs/d5-2026-11-20-cron.md`
- **官方共学模板** — `starter/src/Camp*.sol`

速查表：[`docs/cheatsheet.md`](docs/cheatsheet.md) · FAQ：[`docs/faq.md`](docs/faq.md)

报名：https://web3career.build/zh/programs/reactive-builder-camp  
黑客松：https://dorahacks.io/hackathon/reactive-omni-buildathon/detail
