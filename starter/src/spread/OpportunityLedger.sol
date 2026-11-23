// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { SpreadGuard } from "./SpreadGuard.sol";

/// @title OpportunityLedger — Sepolia 上把一次教学价差记下来
/// @notice 只接受 Sepolia Callback Proxy 的调用，并且 payload 里注入的地址必须等于部署时填的 SpreadReactive。
///         这一步是目标链动作：记录机会，不是下单，也不是套利。
/// @dev    教学模拟，非真实市场。上游两个池也是模拟的。
///
///         Sepolia 在 Amsterdam 计价下，一个从 0 写成非 0 的 SSTORE 大约 108000 gas。
///         官方 Callback Proxy 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4 从 gasLimit 400000 里
///         扣下 _extraGas 150000 和 _maxChargeGas 50000，留给回调的大约是 155800。
///         所以整次机会只能写一个存储槽。再加一个槽，第一次回调会在 Proxy 里面 out of gas。
///         不要在这个合约里新增状态变量。
contract OpportunityLedger is AbstractCallback {
    /// @dev 满 5 次之后再进来就 return，不 revert。revert 的回调一样收费。
    ///      正常情况下 Lasna 侧的 MAX_RECORDS 会先退订，这里是第二道上限。
    uint256 public constant MAX_RECORDS = 5;

    /// @notice 事件里的 price0 / price1 是 1e18 精度的原值（每个 token0 值多少 token1）。
    ///         存储槽里只留得下压缩后的 1e6 精度，链上证据以这条事件为准。
    event OpportunityRecorded(
        address indexed reactive,
        uint256 spreadBps,
        uint256 price0,
        uint256 price1,
        uint256 srcBlock,
        uint8 cheapPoolId,
        uint256 count
    );

    /// @dev 唯一的状态变量，占用 slot 0。布局从低位开始：
    ///      [0, 32)    uint32 count
    ///      [32, 64)   uint32 spreadBps，超过 uint32 就饱和
    ///      [64, 128)  uint64 srcBlock
    ///      [128, 184) uint56 price0，1e6 精度，超过就饱和
    ///      [184, 240) uint56 price1，1e6 精度，超过就饱和
    ///      [240, 248) uint8  cheapPoolId
    ///      [248, 256) uint8  标记。第一次写入因此一定从 0 变成非 0
    uint256 private _record;

    error ZeroAddress();

    /// @param proxy_    Ethereum Sepolia Callback Proxy：0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4
    /// @param reactive_ Lasna 上的 SpreadReactive。填错只能重新部署。
    constructor(IPayable proxy_, address reactive_) payable AbstractCallback(proxy_, reactive_) {
        if (address(proxy_) == address(0) || reactive_ == address(0)) revert ZeroAddress();
        SpreadGuard.refuse(reactive_);
    }

    function count() external view returns (uint256) {
        return uint32(_record);
    }

    function spreadBps() external view returns (uint256) {
        return uint32(_record >> 32);
    }

    function srcBlock() external view returns (uint256) {
        return uint64(_record >> 64);
    }

    /// @notice 池 1 的价格摘要，1e6 精度。事件里的 price0 才是 1e18 原值。
    function price0E6() external view returns (uint256) {
        return uint56(_record >> 128);
    }

    /// @notice 池 2 的价格摘要，1e6 精度。事件里的 price1 才是 1e18 原值。
    function price1E6() external view returns (uint256) {
        return uint56(_record >> 184);
    }

    function cheapPoolId() external view returns (uint8) {
        return uint8(_record >> 240);
    }

    /// @notice Proxy 调用的入口。第一个 address 由网络注入，不是 payload 里那个 address(0)。
    /// @param reactive_    注入后的 Lasna 合约地址
    /// @param spreadBps_   abs(p1-p2)*10000/min(p1,p2)
    /// @param price0_      池 1 的价格，1e18 精度，token1 / token0
    /// @param price1_      池 2 的价格，同样的精度
    /// @param srcBlock_    源链发出 ReservesUpdated 的区块
    /// @param cheapPoolId_ 价格更低的那个池，1 或 2
    function recordOpportunity(
        address reactive_,
        uint256 spreadBps_,
        uint256 price0_,
        uint256 price1_,
        uint256 srcBlock_,
        uint8 cheapPoolId_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        uint32 n = uint32(_record);
        if (n >= MAX_RECORDS) return;
        unchecked {
            n += 1;
        }
        // 一次赋值，一个 SSTORE。不要拆成多个状态变量。
        _record = _pack(n, _sat32(spreadBps_), _sat64(srcBlock_), _e6(price0_), _e6(price1_), cheapPoolId_);
        emit OpportunityRecorded(reactive_, spreadBps_, price0_, price1_, srcBlock_, cheapPoolId_, n);
    }

    /// @notice 用本合约的 ETH 补上 Callback Proxy 记录的欠款。
    function coverDebt() external {
        _coverDebt();
    }

    function _pack(uint32 n, uint32 spread, uint64 blockNo, uint56 p0, uint56 p1, uint8 cheap)
        internal
        pure
        returns (uint256)
    {
        return uint256(n) | (uint256(spread) << 32) | (uint256(blockNo) << 64) | (uint256(p0) << 128)
            | (uint256(p1) << 184) | (uint256(cheap) << 240) | (uint256(1) << 248);
    }

    function _sat32(uint256 v) internal pure returns (uint32) {
        return v > type(uint32).max ? type(uint32).max : uint32(v);
    }

    function _sat64(uint256 v) internal pure returns (uint64) {
        return v > type(uint64).max ? type(uint64).max : uint64(v);
    }

    /// @dev 1e18 精度去掉 12 位，变成 1e6。教学默认储备下这个值和原价对齐。
    function _e6(uint256 priceE18) internal pure returns (uint56) {
        uint256 scaled = priceE18 / 1e12;
        return scaled > type(uint56).max ? type(uint56).max : uint56(scaled);
    }
}
