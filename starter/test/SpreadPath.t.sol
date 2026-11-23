// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test, Vm } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { SimDualAmm } from "../src/spread/SimDualAmm.sol";
import { SpreadReactive } from "../src/spread/SpreadReactive.sol";
import { OpportunityLedger } from "../src/spread/OpportunityLedger.sol";
import { SpreadGuard } from "../src/spread/SpreadGuard.sol";

/// @dev 放在 0x8888…8888 上，记录订阅、退订和回调请求。不广播，也不持有私钥。
contract SpreadMockSystem {
    struct Criteria {
        uint256 chainId;
        address contract_;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    Criteria[] public subs;
    Criteria[] public unsubs;
    ISystemContract.CallbackConfiguration_V_1_0[] internal requests;

    function subscribe(uint256 chainId, address contract_, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3)
        external
    {
        subs.push(Criteria(chainId, contract_, topic0, topic1, topic2, topic3));
    }

    function unsubscribe(uint256 chainId, address contract_, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3)
        external
    {
        unsubs.push(Criteria(chainId, contract_, topic0, topic1, topic2, topic3));
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory cfg) external {
        requests.push(cfg);
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    function subCount() external view returns (uint256) {
        return subs.length;
    }

    function unsubCount() external view returns (uint256) {
        return unsubs.length;
    }

    function requestCount() external view returns (uint256) {
        return requests.length;
    }

    function requestAt(uint256 index) external view returns (ISystemContract.CallbackConfiguration_V_1_0 memory) {
        return requests[index];
    }

    receive() external payable {}
}

/// @dev 模仿 Callback Proxy：把 payload 第一个 address 换成 reactive 地址再调用。
contract SpreadMockProxy {
    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable {}

    function deliver(address recipient, address reactive, bytes memory payload) external returns (bool ok, bytes memory ret) {
        assembly {
            mstore(add(payload, 36), reactive)
        }
        (ok, ret) = recipient.call(payload);
    }
}

/// @notice 本地走完「教学池事件 → react() → 记一条机会」。不连测试网，也不用测试钱包的私钥。
contract SpreadPathTest is Test {
    uint256 constant SEPOLIA = 11155111;
    uint256 constant LASNA = 5318007;
    uint256 constant THRESHOLD = 100;
    uint256 constant LIMIT = 5;
    uint256 constant IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    bytes32 constant TOPIC0 = keccak256("ReservesUpdated(uint8,uint112,uint112)");
    bytes32 constant DEPRECATED_CALLBACK_TOPIC = keccak256("Callback(uint256,address,uint64,bytes)");

    SpreadMockSystem system;
    SpreadMockProxy proxy;
    SimDualAmm amm;
    SpreadReactive reactive;
    OpportunityLedger ledger;
    SpreadSstoreProbe probe;

    function setUp() public {
        vm.chainId(LASNA);
        SpreadMockSystem impl = new SpreadMockSystem();
        vm.etch(0x8888888888888888888888888888888888888888, address(impl).code);
        system = SpreadMockSystem(payable(0x8888888888888888888888888888888888888888));
        proxy = new SpreadMockProxy();
        amm = new SimDualAmm();
        probe = new SpreadSstoreProbe();
        reactive = new SpreadReactive{ value: 1 ether }(SEPOLIA, address(amm), SEPOLIA, THRESHOLD, LIMIT);
        ledger = new OpportunityLedger{ value: 0.1 ether }(IPayable(payable(address(proxy))), address(reactive));
    }

    function _arm() internal {
        reactive.setRecipient(address(ledger));
    }

    function _nudgeAndReact(uint8 poolId, uint112 r0, uint112 r1) internal returns (uint256 newRequests) {
        uint256 before = system.requestCount();
        vm.recordLogs();
        amm.nudgeReserves(poolId, r0, r1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 found = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != TOPIC0) continue;
            found += 1;
            assertEq(logs[i].topics.length, 2);
            assertEq(uint256(logs[i].topics[1]), poolId);
            IReactive.LogRecord memory log_;
            log_.chainId = SEPOLIA;
            log_.contractAddress = address(amm);
            log_.topic0 = uint256(logs[i].topics[0]);
            log_.topic1 = uint256(logs[i].topics[1]);
            log_.data = logs[i].data;
            log_.blockNumber = block.number;
            log_.txHash = uint256(keccak256(abi.encodePacked(poolId, r0, r1, i)));
            vm.prank(address(system));
            reactive.react(log_);
        }
        assertEq(found, 1);
        return system.requestCount() - before;
    }

    function _deliverLatest() internal {
        uint256 index = system.requestCount() - 1;
        (bool ok,) = proxy.deliver(address(ledger), address(reactive), system.requestAt(index).payload);
        assertTrue(ok);
    }

    function test_spreadMath_boundary() public view {
        assertEq(reactive.spreadBpsOf(10_000, 10_000, 10_000, 10_099), 99);
        assertEq(reactive.spreadBpsOf(10_000, 10_000, 10_000, 10_100), 100);
        assertEq(reactive.spreadBpsOf(10_000, 10_100, 10_000, 10_000), 100);
        assertEq(reactive.spreadBpsOf(10_000, 10_000, 10_000, 10_000), 0);
    }

    function test_belowThreshold_noCallback() public {
        _arm();
        assertEq(_nudgeAndReact(1, 10_000, 10_000), 0);
        assertEq(_nudgeAndReact(2, 10_000, 10_099), 0);

        assertEq(system.requestCount(), 0);
        assertEq(reactive.remaining(), LIMIT);
        assertEq(reactive.lastSpreadBps(), 99);
        (uint256 spread, bool ready) = reactive.previewSpreadBps();
        assertTrue(ready);
        assertEq(spread, 99);
        assertEq(ledger.count(), 0);
        assertEq(vm.load(address(ledger), 0), bytes32(0));
    }

    function test_atThreshold_recordsOneSlot() public {
        _arm();
        assertEq(_nudgeAndReact(1, 10_000, 10_000), 0);
        assertEq(_nudgeAndReact(2, 10_000, 10_100), 1);

        ISystemContract.CallbackConfiguration_V_1_0 memory cfg = system.requestAt(0);
        assertEq(cfg.chainId, SEPOLIA);
        assertEq(cfg.recipient, address(ledger));
        assertEq(cfg.gasLimit, 400_000);
        (address placeholder, uint256 spread, uint256 price0, uint256 price1, uint256 srcBlock, uint8 cheap) =
            _decode(cfg.payload);
        assertEq(placeholder, address(0));
        assertEq(spread, 100);
        assertEq(price0, 1e18);
        assertEq(price1, 1.01e18);
        assertEq(srcBlock, block.number);
        assertEq(cheap, 1);

        vm.recordLogs();
        _deliverLatest();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("OpportunityRecorded(address,uint256,uint256,uint256,uint256,uint8,uint256)"));

        assertEq(ledger.count(), 1);
        assertEq(ledger.spreadBps(), 100);
        assertEq(ledger.srcBlock(), block.number);
        assertEq(ledger.price0E6(), 1_000_000);
        assertEq(ledger.price1E6(), 1_010_000);
        assertEq(ledger.cheapPoolId(), 1);
        assertEq(ledger._CALLBACK_SENDER(), address(reactive));

        uint256 slot = uint256(vm.load(address(ledger), 0));
        assertEq(uint32(slot), 1);
        assertEq(uint32(slot >> 32), 100);
        assertEq(uint64(slot >> 64), block.number);
        assertEq(uint56(slot >> 128), 1_000_000);
        assertEq(uint56(slot >> 184), 1_010_000);
        assertEq(uint8(slot >> 240), 1);
        assertEq(uint8(slot >> 248), 1);
        assertEq(vm.load(address(ledger), bytes32(uint256(1))), bytes32(0));
        assertEq(vm.load(address(ledger), bytes32(uint256(2))), bytes32(0));
    }

    function test_aboveThreshold_cheapPoolIsTheLowerPrice() public {
        _arm();
        assertEq(_nudgeAndReact(1, 10_000, 12_000), 0);
        assertEq(_nudgeAndReact(2, 10_000, 10_000), 1);
        (, uint256 spread, uint256 price0, uint256 price1,, uint8 cheap) = _decode(system.requestAt(0).payload);
        assertEq(spread, 2000);
        assertEq(price0, 1.2e18);
        assertEq(price1, 1e18);
        assertEq(cheap, 2);
        _deliverLatest();
        assertEq(ledger.cheapPoolId(), 2);
        assertEq(ledger.count(), 1);
    }

    function test_onlyOnePool_noCallback() public {
        _arm();
        assertEq(_nudgeAndReact(1, 10_000, 10_000), 0);
        assertEq(_nudgeAndReact(1, 10_000, 50_000), 0);
        (uint112 r0, uint112 r1, bool seen1) = reactive.quote1();
        (, , bool seen2) = reactive.quote2();
        assertTrue(seen1);
        assertFalse(seen2);
        assertEq(r0, 10_000);
        assertEq(r1, 50_000);
        assertEq(system.requestCount(), 0);
        assertEq(reactive.remaining(), LIMIT);
        assertEq(reactive.lastSpreadBps(), 0);
        assertEq(ledger.count(), 0);
    }

    function test_unchangedReserves_doNotConsumeCap() public {
        _arm();
        assertEq(_nudgeAndReact(1, 10_000, 10_000), 0);
        assertEq(_nudgeAndReact(2, 10_000, 10_100), 1);
        _deliverLatest();
        assertEq(_nudgeAndReact(2, 10_000, 10_100), 0);
        assertEq(system.requestCount(), 1);
        assertEq(reactive.remaining(), LIMIT - 1);
        assertEq(ledger.count(), 1);
    }

    function test_directLedgerCall_rejected() public {
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(proxy)));
        ledger.recordOpportunity(address(reactive), 100, 1e18, 1.01e18, 1, 1);
        assertEq(ledger.count(), 0);
    }

    function test_auth_wrongReactiveRejected() public {
        bytes memory payload = abi.encodeWithSignature(
            "recordOpportunity(address,uint256,uint256,uint256,uint256,uint8)", address(0), uint256(100), 1e18, 1.01e18, 1, uint8(1)
        );
        (bool ok,) = proxy.deliver(address(ledger), address(0xBEEF), payload);
        assertFalse(ok);
        assertEq(ledger.count(), 0);
    }

    function test_auth_reactOnlySystem() public {
        _arm();
        IReactive.LogRecord memory log_;
        log_.chainId = SEPOLIA;
        log_.contractAddress = address(amm);
        log_.topic0 = uint256(TOPIC0);
        log_.topic1 = 1;
        log_.data = abi.encode(uint112(10_000), uint112(10_000));
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(system)));
        reactive.react(log_);
    }

    function test_subscribeOnce_topicIgnoresPoolId() public {
        assertEq(system.subCount(), 0);
        assertFalse(reactive.subscribed());
        _arm();
        assertEq(system.subCount(), 1);
        (uint256 chainId, address origin, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3) = system.subs(0);
        assertEq(chainId, SEPOLIA);
        assertEq(origin, address(amm));
        assertEq(topic0, uint256(TOPIC0));
        assertEq(topic1, IGNORE);
        assertEq(topic2, IGNORE);
        assertEq(topic3, IGNORE);

        reactive.setRecipient(address(ledger));
        assertEq(system.subCount(), 1);
    }

    function test_cap_unsubscribesAndSecondHitDoesNotRequest() public {
        SpreadReactive small = new SpreadReactive{ value: 1 ether }(SEPOLIA, address(amm), SEPOLIA, THRESHOLD, 1);
        OpportunityLedger smallLedger =
            new OpportunityLedger{ value: 0.1 ether }(IPayable(payable(address(proxy))), address(small));
        small.setRecipient(address(smallLedger));

        assertEq(_nudgeOn(small, 1, 10_000, 10_000), 0);
        assertEq(_nudgeOn(small, 2, 10_000, 10_100), 1);
        assertEq(small.remaining(), 0);
        assertTrue(small.stopped());
        assertFalse(small.subscribed());
        assertEq(system.unsubCount(), 1);
        _assertUnsubMatchesSub();

        uint256 requests = system.requestCount();
        assertEq(_nudgeOn(small, 2, 10_000, 20_000), 0);
        assertEq(system.requestCount(), requests);
    }

    function _assertUnsubMatchesSub() internal view {
        (uint256 chainId, address origin, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3) = system.subs(0);
        (uint256 uChain, address uOrigin, uint256 u0, uint256 u1, uint256 u2, uint256 u3) = system.unsubs(0);
        assertEq(uChain, chainId);
        assertEq(uOrigin, origin);
        assertEq(u0, topic0);
        assertEq(u1, topic1);
        assertEq(u2, topic2);
        assertEq(u3, topic3);
    }

    function test_ledgerCap_returnsWithoutRevert() public {
        _arm();
        assertEq(_nudgeAndReact(1, 10_000, 10_000), 0);
        assertEq(_nudgeAndReact(2, 10_000, 10_100), 1);
        bytes memory payload = system.requestAt(0).payload;
        for (uint256 i = 0; i < 5; i++) {
            (bool ok,) = proxy.deliver(address(ledger), address(reactive), payload);
            assertTrue(ok);
        }
        assertEq(ledger.count(), 5);
        (bool again,) = proxy.deliver(address(ledger), address(reactive), payload);
        assertTrue(again);
        assertEq(ledger.count(), 5);
        assertEq(vm.load(address(ledger), bytes32(uint256(1))), bytes32(0));
    }

    function test_record_oneSlotAndUnderStipend() public {
        _arm();
        assertEq(_nudgeAndReact(1, 10_000, 10_000), 0);
        assertEq(_nudgeAndReact(2, 10_000, 10_100), 1);

        uint256 probeBefore = gasleft();
        probe.store();
        uint256 sstoreGas = probeBefore - gasleft();

        // 直接从 Proxy 地址调用，量的是回调本身，不含外层 deliver 的再包一层。
        vm.prank(address(proxy));
        uint256 before = gasleft();
        ledger.recordOpportunity(address(reactive), 100, 1e18, 1.01e18, block.number, 1);
        uint256 used = before - gasleft();
        emit log_named_uint("sstore probe", sstoreGas);
        emit log_named_uint("record gas", used);

        // Proxy 从 400000 里大约转出 155800。这里留一点余量给真实 Proxy 的调用开销。
        assertLt(used, 150_000, "recordOpportunity exceeds the Sepolia callback stipend");
        if (sstoreGas > 50_000) {
            assertGt(used, 90_000, "amsterdam run did not pay the expensive SSTORE");
        }
        assertEq(vm.load(address(ledger), bytes32(uint256(1))), bytes32(0));

        vm.prank(address(proxy));
        uint256 secondBefore = gasleft();
        ledger.recordOpportunity(address(reactive), 100, 1e18, 1.01e18, block.number, 1);
        uint256 second = secondBefore - gasleft();
        emit log_named_uint("second record gas", second);
        assertLt(second, used);
        assertEq(ledger.count(), 2);
    }

    function test_wrongTopic_doesNotRequest() public {
        _arm();
        IReactive.LogRecord memory log_;
        log_.chainId = SEPOLIA;
        log_.contractAddress = address(amm);
        log_.topic0 = uint256(keccak256("Sync(uint112,uint112)"));
        log_.data = abi.encode(uint112(10_000), uint112(10_000));
        vm.prank(address(system));
        reactive.react(log_);
        assertEq(system.requestCount(), 0);
        assertEq(reactive.lastReactBlock(), 0);
    }

    function test_doesNotEmitDeprecatedCallback() public {
        _arm();
        assertEq(_nudgeAndReact(1, 10_000, 10_000), 0);
        vm.recordLogs();
        assertEq(_nudgeAndReact(2, 10_000, 10_100), 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGt(logs.length, 0);
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != DEPRECATED_CALLBACK_TOPIC);
        }
    }

    function test_refuseOfficialAndD5Addresses() public {
        vm.expectRevert(abi.encodeWithSelector(SpreadGuard.ForbiddenAddress.selector, SpreadGuard.CAMP_ORIGIN));
        new SpreadReactive(SEPOLIA, SpreadGuard.CAMP_ORIGIN, SEPOLIA, THRESHOLD, LIMIT);

        vm.expectRevert(abi.encodeWithSelector(SpreadGuard.ForbiddenAddress.selector, SpreadGuard.D5_REACTIVE));
        new OpportunityLedger(IPayable(payable(address(proxy))), SpreadGuard.D5_REACTIVE);

        _arm();
        vm.expectRevert(abi.encodeWithSelector(SpreadGuard.ForbiddenAddress.selector, SpreadGuard.CAMP_CALLBACK));
        reactive.setRecipient(SpreadGuard.CAMP_CALLBACK);
        vm.expectRevert(abi.encodeWithSelector(SpreadGuard.ForbiddenAddress.selector, SpreadGuard.D5_CALLBACK));
        reactive.setRecipient(SpreadGuard.D5_CALLBACK);
    }

    function test_constructor_revertsOnWrongChain() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(SpreadReactive.WrongChain.selector, uint256(1), uint256(LASNA)));
        new SpreadReactive(SEPOLIA, address(amm), SEPOLIA, THRESHOLD, LIMIT);
    }

    function test_auth_nudgeOnlyOwner() public {
        vm.expectRevert(SimDualAmm.NotOwner.selector);
        vm.prank(address(0xBEEF));
        amm.nudgeReserves(1, 10_000, 10_000);

        vm.expectRevert(abi.encodeWithSelector(SimDualAmm.BadPool.selector, uint8(0)));
        amm.nudgeReserves(0, 10_000, 10_000);
        vm.expectRevert(SimDualAmm.ZeroReserve.selector);
        amm.nudgeReserves(1, 0, 10_000);
    }

    function test_stop_thenUpdateDoesNotRequest() public {
        _arm();
        reactive.stop();
        assertTrue(reactive.stopped());
        assertFalse(reactive.subscribed());
        assertEq(_nudgeAndReact(1, 10_000, 10_000), 0);
        assertEq(_nudgeAndReact(2, 10_000, 10_100), 0);
        assertEq(system.requestCount(), 0);
        vm.expectRevert(SpreadReactive.Stopped.selector);
        reactive.setRecipient(address(ledger));
    }

    function test_coverDebt_whenClear() public {
        reactive.coverDebt();
        ledger.coverDebt();
    }

    /// @dev 部署交易还要再加上 21000 和 init code 的 calldata。这里只卡住 CREATE 本身别突然变大。
    function test_createGas_staysWithinDeployBudget() public {
        uint256 before = gasleft();
        new SimDualAmm();
        uint256 ammGas = before - gasleft();

        before = gasleft();
        new SpreadReactive{ value: 0 }(SEPOLIA, address(amm), SEPOLIA, THRESHOLD, LIMIT);
        uint256 reactiveGas = before - gasleft();

        before = gasleft();
        new OpportunityLedger{ value: 0 }(IPayable(payable(address(proxy))), address(reactive));
        uint256 ledgerGas = before - gasleft();

        emit log_named_uint("amm create", ammGas);
        emit log_named_uint("reactive create", reactiveGas);
        emit log_named_uint("ledger create", ledgerGas);
        assertLt(ammGas, 600_000);
        assertLt(reactiveGas, 2_000_000);
        assertLt(ledgerGas, 900_000);
    }

    function test_topic1MustBeExactPoolId() public {
        _arm();
        IReactive.LogRecord memory log_;
        log_.chainId = SEPOLIA;
        log_.contractAddress = address(amm);
        log_.topic0 = uint256(TOPIC0);
        log_.topic1 = 257;
        log_.data = abi.encode(uint112(10_000), uint112(10_000));
        vm.prank(address(system));
        reactive.react(log_);
        (, , bool seen) = reactive.quote1();
        assertFalse(seen);
        assertEq(system.requestCount(), 0);
    }

    function test_teachingSimConstant() public view {
        assertTrue(amm.TEACHING_SIM());
        assertEq(reactive.RESERVES_TOPIC0(), uint256(TOPIC0));
        assertEq(reactive.CALLBACK_GAS_LIMIT(), 400_000);
    }

    function _nudgeOn(SpreadReactive which, uint8 poolId, uint112 r0, uint112 r1) internal returns (uint256 newRequests) {
        uint256 before = system.requestCount();
        vm.recordLogs();
        amm.nudgeReserves(poolId, r0, r1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != TOPIC0) continue;
            IReactive.LogRecord memory log_;
            log_.chainId = SEPOLIA;
            log_.contractAddress = address(amm);
            log_.topic0 = uint256(logs[i].topics[0]);
            log_.topic1 = uint256(logs[i].topics[1]);
            log_.data = logs[i].data;
            log_.blockNumber = block.number;
            vm.prank(address(system));
            which.react(log_);
        }
        return system.requestCount() - before;
    }

    function _decode(bytes memory payload)
        internal
        pure
        returns (address placeholder, uint256 spread, uint256 price0, uint256 price1, uint256 srcBlock, uint8 cheap)
    {
        assembly {
            placeholder := mload(add(payload, 36))
            spread := mload(add(payload, 68))
            price0 := mload(add(payload, 100))
            price1 := mload(add(payload, 132))
            srcBlock := mload(add(payload, 164))
            cheap := mload(add(payload, 196))
        }
    }

}

contract SpreadSstoreProbe {
    uint256 internal slot;

    function store() external {
        slot = 1;
    }
}
