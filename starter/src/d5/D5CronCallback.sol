// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title D5CronCallback — 11/20 定时任务的 Ethereum Sepolia 回调合约
/// @notice 只接受「Sepolia Callback Proxy 调用」且「payload 里注入的地址等于部署时填的 Reactive 合约」。
///         每次 onTick 把次数加一，并发出 Ticked。这笔 Sepolia 交易就是定时任务的链上证据。
/// @dev    回调 gas 由本合约里的 ETH 支付，失败也收费。所以这里不 revert 来表达「已经够了」：
///         停不停，由 Lasna 上的 D5CronReactive 退订决定。本合约填错 reactive 地址只能重新部署。
contract D5CronCallback is AbstractCallback {
    event Ticked(address indexed reactive, uint256 indexed tickIndex, uint256 cronNumber, uint256 count);

    uint256 public count;
    uint256 public lastCronNumber;
    uint256 public lastTickIndex;

    /// @param proxy_    Ethereum Sepolia Callback Proxy：0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4
    /// @param reactive_ Lasna 上的 D5CronReactive 地址
    constructor(IPayable proxy_, address reactive_) payable AbstractCallback(proxy_, reactive_) {}

    /// @notice Proxy 调用的入口。第一个 address 由网络注入，不是 payload 里那个 address(0)。
    /// @param reactive_   注入后的 Lasna 合约地址，交给 onlyCallbackSender 核对
    /// @param cronNumber_ Cron100 事件里的区块号
    /// @param tickIndex_  第几次执行，从 1 开始
    function onTick(address reactive_, uint256 cronNumber_, uint256 tickIndex_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        count += 1;
        lastCronNumber = cronNumber_;
        lastTickIndex = tickIndex_;
        emit Ticked(reactive_, tickIndex_, cronNumber_, count);
    }

    /// @notice 用本合约的 ETH 补上 Callback Proxy 记录的欠款。
    function coverDebt() external {
        _coverDebt();
    }
}
