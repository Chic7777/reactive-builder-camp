# 恋爱脑清醒日历 / Love-Brain Clarity Calendar

这是要提交的方向（赛道 2）。更早的双向小信号、价差练习、D5 Cron 仍留在仓库里，但不是这次要交的项目。

全部使用测试网。链上不写日记正文。运行时没有 AI。

## 1. 事件与回调

用户在 Sepolia `ClarityCalendar` 上 open / touch / merge / pledge。Lasna `ClarityReactive` 用事件里的 Sepolia 时间戳起算窗口，Cron100 检查是否安静够久，再回调 `markReleased`。

## 2. 赛道

赛道 2：Set It and Forget It。源链与目标链都是 Sepolia，Reactive 在 Lasna。无运行时 AI。

## 3. 本人

Lavie 一个人做。一个钱包即可。

## 4. AI

只辅助开发。见 `docs/ai-usage.md`。
