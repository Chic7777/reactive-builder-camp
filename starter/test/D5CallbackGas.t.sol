// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { D5CronCallback } from "../src/d5/D5CronCallback.sol";

/// @notice 在 Sepolia 公开状态的分叉上，走真实 Callback Proxy，而不是本地 Mock。
///         分叉块 12175552 是失败回调 0x5b94fa24 的前一块。
///         生产编译保持 cancun。这个文件要在 Amsterdam 执行环境下跑：
///         forge test --evm-version amsterdam --match-path test/D5CallbackGas.t.sol
contract SstorePriceProbe {
    uint256 internal slot;
    function store() external { slot = 1; }
}

contract D5CallbackGasForkTest is Test {
    address payable constant PROXY = payable(0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4);
    address constant OPERATOR = 0xF7E866D726658F6C3F14B8EE537fe268a4D91DDb;
    address constant OLD_CALLBACK = 0x7665c61e81d98576Cf6eec70Ba9A76961C650e69;
    address constant OLD_REACTIVE = 0x0F3441F4a1302965AeA144885A8242b57350A3d5;
    /// @dev debug_trace 里 Proxy 这一帧实际拿到的 gas。外层交易 gasLimit 是 400000。
    uint256 constant PROXY_FRAME_GAS = 382552;

    function setUp() public {
        SstorePriceProbe probe = new SstorePriceProbe();
        uint256 before = gasleft();
        probe.store();
        // Cancun 的冷 SSTORE 大约 2 万 gas。Amsterdam 大约 10 万。
        // 默认 cancun 套件不能复现这次 out of gas，所以跳过，而不是当成通过。
        // 先判断再分叉：公开节点已经修剪掉固定区块 12175552 时，cancun 套件不该在 setUp 里失败。
        if (before - gasleft() < 50_000) {
            vm.skip(true, "forge test --evm-version amsterdam --match-path test/D5CallbackGas.t.sol");
            return;
        }
        vm.createSelectFork(
            vm.envOr("D5_SEPOLIA_FORK_URL", string("https://ethereum-sepolia-rpc.publicnode.com")),
            12_175_552
        );
    }

    function test_fork_oldCallback_outOfGasThroughRealProxy() public {
        assertEq(D5CronCallback(payable(OLD_CALLBACK)).count(), 0);
        bool ok = _deliver(OLD_CALLBACK, _tickPayload(8_816_068, 1), PROXY_FRAME_GAS);
        assertTrue(ok, "proxy catches the inner out-of-gas and still returns success");
        assertEq(D5CronCallback(payable(OLD_CALLBACK)).count(), 0);
    }

    function test_fork_packedCallback_sameGasSucceeds() public {
        D5CronCallback fresh = new D5CronCallback{ value: 0.002 ether }(IPayable(PROXY), OLD_REACTIVE);
        bool ok = _deliver(address(fresh), _tickPayload(8_816_068, 1), PROXY_FRAME_GAS);
        assertTrue(ok);
        assertEq(fresh.count(), 1);
        assertEq(fresh.lastCronNumber(), 8_816_068);
        assertEq(fresh.lastTickIndex(), 1);

        // 三个值在同一个槽里。
        uint256 packed = uint256(vm.load(address(fresh), 0));
        assertEq(uint64(packed), 1);
        assertEq(uint64(packed >> 64), 1);
        assertEq(uint128(packed >> 128), 8_816_068);
    }

    function _tickPayload(uint256 cronNumber, uint256 tickIndex) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("onTick(address,uint256,uint256)", OLD_REACTIVE, cronNumber, tickIndex);
    }

    function _deliver(address recipient, bytes memory tickPayload, uint256 frameGas) internal returns (bool ok) {
        // 和系统合约 requestCallbackV_1_0 一样：abi.encode(struct) 会在动态字段前多一个 0x20。
        bytes memory config = abi.encode(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: 11_155_111,
                recipient: recipient,
                gasLimit: 400_000,
                payload: tickPayload
            })
        );
        bytes memory data = abi.encodeWithSignature("deliverCallback(uint8,bytes)", uint8(0), config);
        vm.prank(OPERATOR);
        (ok,) = PROXY.call{ gas: frameGas }(data);
    }
}
