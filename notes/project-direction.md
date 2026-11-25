# 双向小信号唱片 / Mutual Signal Record

这是要提交的方向。更早的两个池价差练习还留在仓库里，见 `docs/spread-first-path.md`，但那不是这次要交的项目。

全部使用测试网。不做实盘。链上不写名字、句子或私人笔记。运行时没有 AI。

## 1. 事件、条件和目标链动作

两个人在 Ethereum Sepolia 上对同一个 `pairId` 调用 `SignalBoard.sendSignal`。事件是 `SignalSent(address indexed sender, bytes32 indexed pairId, uint256 timestamp)`。

Lasna 上的 `SignalReactive.react()` 记下这个人在这个房间里的最近一次信号时间。时间窗比较的是事件里的 Sepolia 时间，不是 Lasna 的区块时间。两个不同地址都到了，并且较晚的时间减去较早的时间不超过窗口（默认 1 小时），才 `SYSTEM.requestCallbackV_1_0`。凑不齐就 return，不 revert。

目标链动作在同一条 Sepolia 上：`EncounterLedger.recordEncounter` 把这次相遇压进一个存储槽，发出 `EncounterUnlocked`。网页读到这次记录之后，显示一张图、一首短诗和一声很短的提示音。图、诗和声音不在合约里。

## 2. 赛道

赛道 2：Set It and Forget It。

源链和目标链都是 Ethereum Sepolia（11155111），Reactive 在 Lasna（5318007）。同一条链同时当源和目标，是一条完整链路。没有运行时 AI，不选赛道 3。不把「秒级必须」当作这条演示的条件，也不选赛道 1。

## 3. 本人和现在的做法

Lavie 一个人做。这是一个浪漫的小演示：两个人各自挥一下手，时间对上了，就留下一张很小的唱片。它不筛选交易机会，也不承诺收益。

## 4. 作业要跑通的链路

- 自己的三个合约：信号板、Reactive、账本。不是改名的官方示例，不是 D5 Cron，也不是价差路径。
- 一次源链 `SignalSent` → `react()` 判断 → 一次目标链 `recordEncounter`。
- 窗口没对上就跳过。次数有上限，用完就退订。
- 脚本能在 Windows 上部署，并在真的广播之后给出三笔交易链接。哈希不提前编。
- 网页能在链下预览，部署之后也能读账本。

## 5. 分工

按单人项目写。Lavie 负责需求、窗口和次数这些参数、合约测试和部署、验收、演示和文档。AI 只辅助开发，不出现在运行时循环里。

## 报名

DoraHacks 活动页已显示 Unregister（取消报名），报名已经成功。报名截图作为课程附件另行上传。BUIDL 还没有提交。
