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

    /// @dev 2026-11-20 Sepolia 上，一个从 0 写成非 0 的 SSTORE 大约 108000 gas，不是旧的 20000。
    ///      三个独立槽大约 326000 gas。Proxy 从 gasLimit=400000 的交易里只转给 onTick 约 155800，
    ///      所以三次写入会 out of gas。这三个数打包进同一个槽，只付一次 SSTORE。
    uint64 private _count;
    uint64 private _lastTickIndex;
    uint128 private _lastCronNumber;

    /// @param proxy_    Ethereum Sepolia Callback Proxy：0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4
    /// @param reactive_ Lasna 上的 D5CronReactive 地址
    constructor(IPayable proxy_, address reactive_) payable AbstractCallback(proxy_, reactive_) {}

    function count() external view returns (uint256) { return _count; }
    function lastCronNumber() external view returns (uint256) { return _lastCronNumber; }
    function lastTickIndex() external view returns (uint256) { return _lastTickIndex; }

    /// @notice Proxy 调用的入口。第一个 address 由网络注入，不是 payload 里那个 address(0)。
    /// @param reactive_   注入后的 Lasna 合约地址，交给 onlyCallbackSender 核对
    /// @param cronNumber_ Cron100 事件里的区块号
    /// @param tickIndex_  第几次执行，从 1 开始
    function onTick(address reactive_, uint256 cronNumber_, uint256 tickIndex_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        _count += 1;
        _lastCronNumber = uint128(cronNumber_);
        _lastTickIndex = uint64(tickIndex_);
        emit Ticked(reactive_, tickIndex_, cronNumber_, _count);
    }

    /// @notice 用本合约的 ETH 补上 Callback Proxy 记录的欠款。
    function coverDebt() external {
        _coverDebt();
    }
}
