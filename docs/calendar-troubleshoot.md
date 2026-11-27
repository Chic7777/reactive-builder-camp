# 恋爱脑清醒日历：出问题对照表

| 情况 | 你会看到什么 | 怎么办 |
|---|---|---|
| `.env` 里没有 `PRIVATE_KEY` | preflight 停住，提示 key missing | 自己在本机填测试私钥；不要发给 AI 或贴到聊天 |
| Sepolia / Lasna 余额不够 | preflight 算完 need 后 Fail，**未广播** | 领测试币；Lasna 可用 cheatsheet 里的 faucet 换 lREACT |
| 误把 D5 / Camp / Signal 地址当日历 | 脚本 Fail：points at official/D5 或 matches another lab | 只用新的 `CALENDAR_*` 地址 |
| 还没 bind 就 pledge | DemoPledge 提示 reactive not bound | 先跑 `-Stage bind`（Sepolia bindReactive + Lasna setRecipient） |
| 日记出现在链上？ | 不会 | 合约没有日记字段；正文只在 `localStorage` |
| 窗口还没到就想看到释放 | `isReleased` 仍是 false；verify 没有 `ThreadReleased` | 等 `CALENDAR_WINDOW`（默认 1800 秒）。演示可先在网页点「演示：标记彻底放下」 |
| 窗口过了仍未释放 | Lasna `subscribedCron` 为 false，或 `debt > 0`，或 `pendingCount` 为 0 | 确认已 pledge；查 Reactive 余额与 debt；给合约转 lREACT 或 `coverDebt()` |
| 回调 out of gas | 极少：`markReleased` 是暖写入，通常远低于 ~155800 | 仍失败则查 Proxy debt；给日历合约补 Sepolia ETH |
| Cron 一直空转扣费 | 有待办时才订 Cron；队列空会退订 Cron | 正常。紧急可 `-Stage` 对应的 `StopCalendar` forge 脚本 |
| MetaMask 不在 Sepolia | 网页提示切链 | 允许切换到 chainId 11155111 |
| 想重新部署 | 旧 `CALENDAR_ADDR` 已占用 | `-Stage prepareRerun` 清地址行并归档 broadcast（不碰 cache） |
| AI 会不会读我的日记？ | 不会 | 运行时无 AI；神谕是本地文案库 |
