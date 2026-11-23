// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @notice 这条作业链路不能误接到官方示例或 D5 Cron 实验合约上。
///         官方三件套是共学模板，D5 是定时回调实验，都不是两个教学池的价差路径。
library SpreadGuard {
    /// @notice 官方 CampOrigin / CampReactive / CampCallback（D3/D4 示例）。
    address internal constant CAMP_ORIGIN = 0x6cfe6d08F328b5f067B9ba7F10dc08ca515De950;
    address internal constant CAMP_REACTIVE = 0x9a30c9bc9c6dC4101679A735e121e3856cC12FB6;
    address internal constant CAMP_CALLBACK = 0x9bebaFE458DaF45faB88Abd42A2Efc36B38A7A32;

    /// @notice 2026-11-20 跑通的 D5 Cron 合约。次数已经用完，不能拿来当本项目的回调发送方。
    address internal constant D5_REACTIVE = 0xC436b8445cBf6ce233ce83873B3Ac19F5ace04fD;
    address internal constant D5_CALLBACK = 0x245FBD3aC14Eb117F6587E7E5e64A8d79AA684a2;

    /// @notice 第一轮 D5 回调 out of gas 的那对合约。
    address internal constant D5_FAILED_REACTIVE = 0x0F3441F4a1302965AeA144885A8242b57350A3d5;
    address internal constant D5_FAILED_CALLBACK = 0x7665c61e81d98576Cf6eec70Ba9A76961C650e69;

    error ForbiddenAddress(address addr);

    function refuse(address a) internal pure {
        if (
            a == CAMP_ORIGIN || a == CAMP_REACTIVE || a == CAMP_CALLBACK || a == D5_REACTIVE || a == D5_CALLBACK
                || a == D5_FAILED_REACTIVE || a == D5_FAILED_CALLBACK
        ) revert ForbiddenAddress(a);
    }
}
