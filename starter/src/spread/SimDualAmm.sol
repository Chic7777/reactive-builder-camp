// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title SimDualAmm — 一个合约里的两个教学模拟池
/// @notice 教学模拟，非真实市场。两个独立的教学模拟池（poolId 1 和 poolId 2），
///         不是真实市场，也不挂真实流动性。储备只在本合约里按恒定乘积 x * y 记账，
///         不发行、不转入、不转出真实 ERC-20。
/// @dev    Phase A 没有 swap。nudgeReserves 直接改某一池的储备，用来制造价差。
///         事件至少有一个 indexed 参数。不要照搬 Uniswap V2 的 Sync：
///         Sync(uint112,uint112) 一个 indexed 都没有，Reactive 订阅时分不清是哪一个池。
contract SimDualAmm {
    error BadPool(uint8 poolId);
    error ZeroReserve();
    error NotOwner();

    /// @notice poolId 在 topic1。reserve0、reserve1 在 data 里，各占 32 字节。
    event ReservesUpdated(uint8 indexed poolId, uint112 reserve0, uint112 reserve1);

    struct Pool {
        uint112 reserve0;
        uint112 reserve1;
    }

    /// @notice 部署脚本用来确认这不是 CampOrigin。公开常量，调用不花存储。
    bool public constant TEACHING_SIM = true;

    address public immutable OWNER;

    mapping(uint8 => Pool) private _pools;

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert NotOwner();
        _;
    }

    constructor() {
        OWNER = msg.sender;
    }

    /// @notice 恒定乘积记账。Phase A 不在这里成交。
    function k(uint8 poolId) external view returns (uint256) {
        Pool memory pool = _pool(poolId);
        return uint256(pool.reserve0) * uint256(pool.reserve1);
    }

    function reserves(uint8 poolId) external view returns (uint112 reserve0, uint112 reserve1) {
        Pool memory pool = _pool(poolId);
        return (pool.reserve0, pool.reserve1);
    }

    /// @notice 教学函数：把指定池的储备改成新值，并发出 ReservesUpdated。
    ///         只有部署者能调，避免别人把最多 5 次的记录额度用掉。
    ///         reserve0 和 reserve1 都不能为 0，否则价格没有定义。
    function nudgeReserves(uint8 poolId, uint112 reserve0, uint112 reserve1) external onlyOwner {
        if (poolId != 1 && poolId != 2) revert BadPool(poolId);
        if (reserve0 == 0 || reserve1 == 0) revert ZeroReserve();
        _pools[poolId] = Pool(reserve0, reserve1);
        emit ReservesUpdated(poolId, reserve0, reserve1);
    }

    function _pool(uint8 poolId) internal view returns (Pool memory) {
        if (poolId != 1 && poolId != 2) revert BadPool(poolId);
        return _pools[poolId];
    }
}
