// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title SignalBoard — Sepolia 上的小信号板
/// @notice 两个人各自调用 sendSignal(pairId)。合约只发出事件，不保存名字、句子或私人笔记。
///         pairId 应该是双方约定暗号的 keccak256，不是明文。
/// @dev    教学/演示。浪漫的是网页上的诗和图，链上只有「这个地址在这个时刻挥了一下手」。
///         源链和目标链都是 Ethereum Sepolia。这里不检查 chainId，方便本地测试；
///         部署脚本会把这笔交易发到 Sepolia。
contract SignalBoard {
    /// @notice 给脚本和网页一个固定标记，避免把信号发到别的合约上。
    bool public constant ROMANTIC_DEMO = true;

    /// @dev topic0 = keccak256("SignalSent(address,bytes32,uint256)")。
    ///      sender 在 topic1，pairId 在 topic2，timestamp 在 data 里。
    ///      至少有一个 indexed 参数，Reactive 才能按主题订阅。
    event SignalSent(address indexed sender, bytes32 indexed pairId, uint256 timestamp);

    error EmptyPair();

    /// @notice 发出一次小信号。同一个人连续调用只是更新自己的时间，不会变成两个人。
    /// @param pairId 双方约定的房间号。用 keccak256(bytes(roomCode))，不要把名字写进来。传 0 会失败。
    function sendSignal(bytes32 pairId) external {
        if (pairId == bytes32(0)) revert EmptyPair();
        emit SignalSent(msg.sender, pairId, block.timestamp);
    }
}
