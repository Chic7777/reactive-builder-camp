// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { SignalGuard } from "./SignalGuard.sol";

/// @title EncounterLedger — Sepolia 上把一次相遇压进一个存储槽
/// @notice 只接受 Sepolia Callback Proxy 的调用，并且 payload 里注入的地址必须等于部署时填的 SignalReactive。
///         这一步是目标链动作：记下「这两个人在时间窗里都挥过手」，不是转账，也不是发消息。
/// @dev    教学/演示。诗、图片和声音不在这个合约里。
///
///         Sepolia 在 Amsterdam 计价下，一个从 0 写成非 0 的 SSTORE 大约 108000 gas。
///         官方 Callback Proxy 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4 从 gasLimit 400000 里
///         扣下 _extraGas 150000 和 _maxChargeGas 50000，留给 recordEncounter 的大约是 155800。
///         两个 address 加一个 bytes32 放不进 32 字节，所以槽里只留次数、两个时间、pairId 的低 88 位。
///         完整的地址和 pairId 在 EncounterUnlocked 事件里。链上证据以事件为准。
///         不要在这个合约里新增状态变量。
contract EncounterLedger is AbstractCallback {
    /// @dev 满 5 次之后再进来就 return，不 revert。revert 的回调一样收费。
    ///      正常情况下 Lasna 侧的 MAX_ENCOUNTERS 会先退订，这里是第二道上限。
    uint256 public constant MAX_ENCOUNTERS = 5;

    /// @notice personLow / personHigh 按地址从小到大排过。timeLow 是 personLow 的信号时间，不是更早的那个时间。
    ///         两个时间的先后存在槽里的 earlierAt / laterAt。地址本身只出现在这条事件里。
    event EncounterUnlocked(
        address indexed reactive,
        bytes32 indexed pairId,
        address personLow,
        uint64 timeLow,
        address personHigh,
        uint64 timeHigh,
        uint32 count
    );

    /// @dev 唯一的状态变量，占用 slot 0。布局从低位开始：
    ///      [0, 32)     uint32 count
    ///      [32, 96)    uint64 earlierAt   两条信号里更早的 Sepolia 时间
    ///      [96, 160)   uint64 laterAt     两条信号里更晚的 Sepolia 时间
    ///      [160, 248)  uint88 pairTag     pairId 的低 88 位
    ///      [248, 256)  uint8  标记。第一次写入因此一定从 0 变成非 0
    uint256 private _record;

    error ZeroAddress();

    /// @param proxy_    Ethereum Sepolia Callback Proxy：0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4
    /// @param reactive_ Lasna 上的 SignalReactive。填错只能重新部署。
    constructor(IPayable proxy_, address reactive_) payable AbstractCallback(proxy_, reactive_) {
        if (address(proxy_) == address(0) || reactive_ == address(0)) revert ZeroAddress();
        SignalGuard.refuse(reactive_);
    }

    function count() external view returns (uint256) {
        return uint32(_record);
    }

    function earlierAt() external view returns (uint256) {
        return uint64(_record >> 32);
    }

    function laterAt() external view returns (uint256) {
        return uint64(_record >> 96);
    }

    /// @notice pairId 的低 88 位。完整 pairId 以事件为准。
    function pairTag() external view returns (uint256) {
        return uint88(_record >> 160);
    }

    /// @notice Proxy 调用的入口。第一个 address 由网络注入，不是 payload 里那个 address(0)。
    /// @param reactive_    注入后的 Lasna 合约地址
    /// @param pairId_      双方的房间号
    /// @param personLow_   地址较小的那个人
    /// @param timeLow_     这个人的 SignalSent 时间（Sepolia block.timestamp）
    /// @param personHigh_  地址较大的那个人
    /// @param timeHigh_    这个人的 SignalSent 时间
    function recordEncounter(
        address reactive_,
        bytes32 pairId_,
        address personLow_,
        uint64 timeLow_,
        address personHigh_,
        uint64 timeHigh_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        uint32 n = uint32(_record);
        if (n >= MAX_ENCOUNTERS) return;
        // 坏的 payload 用 return，不用 revert。失败的回调一样收费。
        if (pairId_ == bytes32(0) || personLow_ == address(0) || personHigh_ == address(0) || personLow_ >= personHigh_) {
            return;
        }
        unchecked {
            n += 1;
        }
        uint64 earlier = timeLow_ < timeHigh_ ? timeLow_ : timeHigh_;
        uint64 later = timeLow_ > timeHigh_ ? timeLow_ : timeHigh_;
        // 一次赋值，一个 SSTORE。不要拆成多个状态变量。
        _record = _pack(n, earlier, later, uint88(uint256(pairId_)));
        emit EncounterUnlocked(reactive_, pairId_, personLow_, timeLow_, personHigh_, timeHigh_, n);
    }

    /// @notice 用本合约的 ETH 补上 Callback Proxy 记录的欠款。
    function coverDebt() external {
        _coverDebt();
    }

    function _pack(uint32 n, uint64 earlier, uint64 later, uint88 tag) internal pure returns (uint256) {
        return uint256(n) | (uint256(earlier) << 32) | (uint256(later) << 96) | (uint256(tag) << 160)
            | (uint256(1) << 248);
    }
}
