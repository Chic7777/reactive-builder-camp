// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test, Vm } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { SignalBoard } from "../src/signal/SignalBoard.sol";
import { SignalReactive } from "../src/signal/SignalReactive.sol";
import { EncounterLedger } from "../src/signal/EncounterLedger.sol";
import { SignalGuard } from "../src/signal/SignalGuard.sol";

/// @dev 放在 0x8888…8888 上，记录订阅、退订和回调请求。不广播，也不持有私钥。
contract SignalMockSystem {
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
contract SignalMockProxy {
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

/// @notice 本地走完「两个地址的小信号 → react() → 记一次相遇」。
///         两个地址用 vm.prank 区分，不读 .env，也不使用测试钱包的私钥。
contract SignalPathTest is Test {
    uint256 constant SEPOLIA = 11155111;
    uint256 constant LASNA = 5318007;
    uint256 constant WINDOW = 3600;
    uint256 constant LIMIT = 3;
    uint256 constant IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    bytes32 constant PAIR = keccak256("mutual-signal");
    bytes32 constant TOPIC0 = keccak256("SignalSent(address,bytes32,uint256)");
    bytes32 constant UNLOCK_TOPIC = keccak256("EncounterUnlocked(address,bytes32,address,uint64,address,uint64,uint32)");
    bytes32 constant DEPRECATED_CALLBACK_TOPIC = keccak256("Callback(uint256,address,uint64,bytes)");
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);

    SignalMockSystem system;
    SignalMockProxy proxy;
    SignalBoard board;
    SignalReactive reactive;
    EncounterLedger ledger;
    SignalSstoreProbe probe;

    function setUp() public {
        vm.chainId(LASNA);
        SignalMockSystem impl = new SignalMockSystem();
        vm.etch(0x8888888888888888888888888888888888888888, address(impl).code);
        system = SignalMockSystem(payable(0x8888888888888888888888888888888888888888));
        proxy = new SignalMockProxy();
        board = new SignalBoard();
        probe = new SignalSstoreProbe();
        reactive = new SignalReactive{ value: 1 ether }(SEPOLIA, address(board), SEPOLIA, WINDOW, LIMIT);
        ledger = new EncounterLedger{ value: 0.1 ether }(IPayable(payable(address(proxy))), address(reactive));
    }

    function _arm() internal {
        reactive.setRecipient(address(ledger));
    }

    function _signal(address who, uint256 ts) internal returns (uint256 newRequests) {
        return _signalOn(reactive, who, PAIR, ts);
    }

    /// @dev 板子上的 timestamp 就是这次 warp 后的 block.timestamp。react() 必须读事件里的这个数。
    function _signalOn(SignalReactive which, address who, bytes32 pairId, uint256 ts) internal returns (uint256 newRequests) {
        uint256 before = system.requestCount();
        vm.warp(ts);
        vm.recordLogs();
        vm.prank(who);
        board.sendSignal(pairId);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 found = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != TOPIC0) continue;
            found += 1;
            assertEq(logs[i].topics.length, 3);
            assertEq(address(uint160(uint256(logs[i].topics[1]))), who);
            assertEq(logs[i].topics[2], pairId);
            uint256 stamped = abi.decode(logs[i].data, (uint256));
            assertEq(stamped, ts);
            _react(which, logs[i], ts);
        }
        assertEq(found, 1);
        return system.requestCount() - before;
    }

    function _react(SignalReactive which, Vm.Log memory entry, uint256 ts) internal {
        IReactive.LogRecord memory log_;
        log_.chainId = SEPOLIA;
        log_.contractAddress = address(board);
        log_.topic0 = uint256(entry.topics[0]);
        log_.topic1 = uint256(entry.topics[1]);
        log_.topic2 = uint256(entry.topics[2]);
        log_.data = entry.data;
        log_.blockNumber = block.number;
        log_.txHash = uint256(keccak256(abi.encodePacked(entry.topics[1], ts)));
        vm.prank(address(system));
        which.react(log_);
    }

    /// @dev 事件时间和 Lasna 的 block.timestamp 分开。用来证明时间窗不看 Lasna 的钟。
    function _reactAt(address sender, bytes32 pairId, uint256 eventTime) internal returns (uint256 newRequests) {
        uint256 before = system.requestCount();
        IReactive.LogRecord memory log_;
        log_.chainId = SEPOLIA;
        log_.contractAddress = address(board);
        log_.topic0 = uint256(TOPIC0);
        log_.topic1 = uint256(uint160(sender));
        log_.topic2 = uint256(pairId);
        log_.data = abi.encode(eventTime);
        log_.blockNumber = 123;
        vm.prank(address(system));
        reactive.react(log_);
        return system.requestCount() - before;
    }

    function _deliverLatest() internal {
        uint256 index = system.requestCount() - 1;
        (bool ok,) = proxy.deliver(address(ledger), address(reactive), system.requestAt(index).payload);
        assertTrue(ok);
    }

    function test_constants_matchTheDemoRoom() public view {
        assertEq(PAIR, bytes32(uint256(0x23365b7b7f9f4867a6d0a355957e84dec93920a11d04b48ab7789415b30b55b6)));
        assertEq(reactive.SIGNAL_TOPIC0(), uint256(TOPIC0));
        assertEq(reactive.CALLBACK_GAS_LIMIT(), 400_000);
        assertEq(reactive.WINDOW(), WINDOW);
        assertTrue(board.ROMANTIC_DEMO());
        assertLt(uint160(BOB), uint160(ALICE));
    }

    function test_onlyOneSignal_noCallback() public {
        _arm();
        assertEq(_signal(ALICE, 1_000_000), 0);
        (address first, uint64 firstAt, address second, uint64 secondAt) = reactive.pairMemory(PAIR);
        assertEq(first, ALICE);
        assertEq(firstAt, 1_000_000);
        assertEq(second, address(0));
        assertEq(secondAt, 0);
        assertEq(system.requestCount(), 0);
        assertEq(reactive.remaining(), LIMIT);
        assertEq(ledger.count(), 0);
        assertEq(vm.load(address(ledger), 0), bytes32(0));
    }

    function test_sameSenderTwice_noCallback() public {
        _arm();
        assertEq(_signal(ALICE, 1_000_000), 0);
        assertEq(_signal(ALICE, 1_000_000 + WINDOW), 0);
        (address first,, address second,) = reactive.pairMemory(PAIR);
        assertEq(first, ALICE);
        assertEq(second, address(0));
        assertEq(system.requestCount(), 0);
        assertEq(reactive.remaining(), LIMIT);
    }

    function test_outsideWindow_noCallback() public {
        _arm();
        assertEq(_signal(ALICE, 1_000_000), 0);
        assertEq(_signal(BOB, 1_000_000 + WINDOW + 1), 0);

        assertEq(system.requestCount(), 0);
        assertEq(reactive.remaining(), LIMIT);
        assertEq(reactive.requested(), 0);
        (address first, uint64 firstAt, address second, uint64 secondAt) = reactive.pairMemory(PAIR);
        assertEq(first, ALICE);
        assertEq(firstAt, 1_000_000);
        assertEq(second, BOB);
        assertEq(secondAt, 1_000_000 + WINDOW + 1);
        assertEq(ledger.count(), 0);
        assertEq(vm.load(address(ledger), 0), bytes32(0));
    }

    function test_bothSignalsInWindow_recordsOneSlot() public {
        _arm();
        assertEq(_signal(ALICE, 1_700_000_000), 0);
        assertEq(_signal(BOB, 1_700_000_000 + WINDOW), 1);

        ISystemContract.CallbackConfiguration_V_1_0 memory cfg = system.requestAt(0);
        assertEq(cfg.chainId, SEPOLIA);
        assertEq(cfg.recipient, address(ledger));
        assertEq(cfg.gasLimit, 400_000);
        (bytes4 selector, address placeholder, bytes32 pairId, address low, uint64 timeLow, address high, uint64 timeHigh) =
            _decode(cfg.payload);
        assertEq(selector, bytes4(0x61491306));
        assertEq(placeholder, address(0));
        assertEq(pairId, PAIR);
        assertEq(low, BOB);
        assertEq(timeLow, 1_700_000_000 + WINDOW);
        assertEq(high, ALICE);
        assertEq(timeHigh, 1_700_000_000);
        assertTrue(low < high);

        vm.recordLogs();
        _deliverLatest();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], UNLOCK_TOPIC);
        assertEq(address(uint160(uint256(logs[0].topics[1]))), address(reactive));
        assertEq(logs[0].topics[2], PAIR);

        assertEq(ledger.count(), 1);
        assertEq(ledger.earlierAt(), 1_700_000_000);
        assertEq(ledger.laterAt(), 1_700_000_000 + WINDOW);
        assertEq(ledger.pairTag(), uint256(uint88(uint256(PAIR))));
        assertEq(ledger._CALLBACK_SENDER(), address(reactive));
        assertEq(reactive.requested(), 1);
        assertEq(reactive.remaining(), LIMIT - 1);

        uint256 slot = uint256(vm.load(address(ledger), 0));
        assertEq(uint32(slot), 1);
        assertEq(uint64(slot >> 32), 1_700_000_000);
        assertEq(uint64(slot >> 96), 1_700_000_000 + WINDOW);
        assertEq(uint88(slot >> 160), uint88(uint256(PAIR)));
        assertEq(uint8(slot >> 248), 1);
        assertEq(vm.load(address(ledger), bytes32(uint256(1))), bytes32(0));
        assertEq(vm.load(address(ledger), bytes32(uint256(2))), bytes32(0));

        (address first,, address second,) = reactive.pairMemory(PAIR);
        assertEq(first, address(0));
        assertEq(second, address(0));
    }

    function test_windowUsesEventTimestampNotLasnaTime() public {
        _arm();
        // Lasna 的钟停在很晚的时候。两条事件自己的时间仍在一小时里，应该相遇。
        vm.warp(9_000_000_000);
        assertEq(_reactAt(ALICE, PAIR, 5_000), 0);
        assertEq(_reactAt(BOB, PAIR, 5_000 + WINDOW), 1);

        // 反过来：两次 react() 发生在同一个 Lasna 时刻，但事件时间差超过窗口，不回调。
        uint256 requests = system.requestCount();
        assertEq(_reactAt(ALICE, keccak256("other-room"), 5_000), 0);
        assertEq(_reactAt(BOB, keccak256("other-room"), 5_000 + WINDOW + 1), 0);
        assertEq(system.requestCount(), requests);
    }

    function test_directLedgerCall_rejected() public {
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(proxy)));
        ledger.recordEncounter(address(reactive), PAIR, BOB, 1, ALICE, 2);
        assertEq(ledger.count(), 0);
    }

    function test_auth_wrongReactiveRejected() public {
        bytes memory payload = abi.encodeWithSignature(
            "recordEncounter(address,bytes32,address,uint64,address,uint64)",
            address(0),
            PAIR,
            BOB,
            uint64(1),
            ALICE,
            uint64(2)
        );
        (bool ok,) = proxy.deliver(address(ledger), address(0xBEEF), payload);
        assertFalse(ok);
        assertEq(ledger.count(), 0);

        vm.prank(address(proxy));
        vm.expectRevert(
            abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, address(0xBEEF), address(reactive))
        );
        ledger.recordEncounter(address(0xBEEF), PAIR, BOB, 1, ALICE, 2);
    }

    function test_auth_reactOnlySystem() public {
        _arm();
        IReactive.LogRecord memory log_;
        log_.chainId = SEPOLIA;
        log_.contractAddress = address(board);
        log_.topic0 = uint256(TOPIC0);
        log_.topic1 = uint256(uint160(ALICE));
        log_.topic2 = uint256(PAIR);
        log_.data = abi.encode(uint256(1_000_000));
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(system)));
        reactive.react(log_);
    }

    function test_cap_unsubscribesAndSecondMeetingDoesNotRequest() public {
        SignalReactive small = new SignalReactive{ value: 1 ether }(SEPOLIA, address(board), SEPOLIA, WINDOW, 1);
        EncounterLedger smallLedger =
            new EncounterLedger{ value: 0.1 ether }(IPayable(payable(address(proxy))), address(small));
        small.setRecipient(address(smallLedger));

        assertEq(_signalOn(small, ALICE, PAIR, 2_000_000), 0);
        assertEq(_signalOn(small, BOB, PAIR, 2_000_100), 1);
        assertEq(small.remaining(), 0);
        assertEq(small.requested(), 1);
        assertTrue(small.stopped());
        assertFalse(small.subscribed());
        assertEq(system.unsubCount(), 1);
        _assertUnsubMatchesSub();

        uint256 requests = system.requestCount();
        assertEq(_signalOn(small, ALICE, PAIR, 2_100_000), 0);
        assertEq(_signalOn(small, BOB, PAIR, 2_100_100), 0);
        assertEq(system.requestCount(), requests);
        assertEq(small.requested(), 1);
    }

    function test_ledgerCap_returnsWithoutRevert() public {
        _arm();
        assertEq(_signal(ALICE, 3_000_000), 0);
        assertEq(_signal(BOB, 3_000_100), 1);
        bytes memory payload = system.requestAt(0).payload;
        uint256 cap = ledger.MAX_ENCOUNTERS();
        for (uint256 i = 0; i < cap; i++) {
            (bool ok,) = proxy.deliver(address(ledger), address(reactive), payload);
            assertTrue(ok);
        }
        assertEq(ledger.count(), cap);
        (bool again,) = proxy.deliver(address(ledger), address(reactive), payload);
        assertTrue(again);
        assertEq(ledger.count(), cap);
        assertEq(vm.load(address(ledger), bytes32(uint256(1))), bytes32(0));
    }

    function test_freshMeetingNeedsTwoNewSignals() public {
        _arm();
        assertEq(_signal(ALICE, 4_000_000), 0);
        assertEq(_signal(BOB, 4_000_100), 1);
        assertEq(_signal(ALICE, 4_100_000), 0);
        assertEq(system.requestCount(), 1);
        assertEq(_signal(BOB, 4_100_050), 1);
        assertEq(reactive.requested(), 2);
        assertEq(reactive.remaining(), LIMIT - 2);
    }

    function test_replaySameMeeting_doesNotCallbackAgain() public {
        _arm();
        assertEq(_reactAt(ALICE, PAIR, 8_000), 0);
        assertEq(_reactAt(BOB, PAIR, 8_100), 1);
        uint256 requests = system.requestCount();
        assertEq(_reactAt(ALICE, PAIR, 8_000), 0);
        assertEq(_reactAt(BOB, PAIR, 8_100), 0);
        assertEq(system.requestCount(), requests);
        assertEq(reactive.requested(), 1);
    }

    function test_subscribeOnce_ignoresSenderAndPair() public {
        assertEq(system.subCount(), 0);
        assertFalse(reactive.subscribed());
        _arm();
        assertEq(system.subCount(), 1);
        (uint256 chainId, address origin, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3) = system.subs(0);
        assertEq(chainId, SEPOLIA);
        assertEq(origin, address(board));
        assertEq(topic0, uint256(TOPIC0));
        assertEq(topic1, IGNORE);
        assertEq(topic2, IGNORE);
        assertEq(topic3, IGNORE);

        reactive.setRecipient(address(ledger));
        assertEq(system.subCount(), 1);
    }

    function test_record_oneSlotAndUnderStipend() public {
        uint256 probeBefore = gasleft();
        probe.store();
        uint256 sstoreGas = probeBefore - gasleft();

        vm.prank(address(proxy));
        uint256 before = gasleft();
        ledger.recordEncounter(address(reactive), PAIR, BOB, 1_700_000_000, ALICE, 1_700_003_600);
        uint256 used = before - gasleft();
        emit log_named_uint("sstore probe", sstoreGas);
        emit log_named_uint("record gas", used);

        // Proxy 从 400000 里大约转出 155800。这里留一点余量给真实 Proxy 的调用开销。
        assertLt(used, 150_000, "recordEncounter exceeds the Sepolia callback stipend");
        if (sstoreGas > 50_000) {
            assertGt(used, 90_000, "amsterdam run did not pay the expensive SSTORE");
        }
        assertEq(vm.load(address(ledger), bytes32(uint256(1))), bytes32(0));
        assertEq(ledger.count(), 1);

        vm.prank(address(proxy));
        uint256 secondBefore = gasleft();
        ledger.recordEncounter(address(reactive), PAIR, BOB, 1_700_000_100, ALICE, 1_700_000_200);
        uint256 second = secondBefore - gasleft();
        emit log_named_uint("second record gas", second);
        assertLt(second, used);
        assertEq(ledger.count(), 2);
    }

    function test_wrongTopicOrContract_doesNotRequest() public {
        _arm();
        IReactive.LogRecord memory log_;
        log_.chainId = SEPOLIA;
        log_.contractAddress = address(board);
        log_.topic0 = uint256(keccak256("Ping(address,uint256)"));
        log_.topic1 = uint256(uint160(ALICE));
        log_.topic2 = uint256(PAIR);
        log_.data = abi.encode(uint256(1_000_000));
        vm.prank(address(system));
        reactive.react(log_);

        log_.topic0 = uint256(TOPIC0);
        log_.contractAddress = address(0xBEEF);
        vm.prank(address(system));
        reactive.react(log_);
        assertEq(system.requestCount(), 0);
        assertEq(reactive.lastReactBlock(), 0);
    }

    function test_dirtyTopic1_isIgnored() public {
        _arm();
        IReactive.LogRecord memory log_;
        log_.chainId = SEPOLIA;
        log_.contractAddress = address(board);
        log_.topic0 = uint256(TOPIC0);
        log_.topic1 = uint256(uint160(ALICE)) | (uint256(1) << 160);
        log_.topic2 = uint256(PAIR);
        log_.data = abi.encode(uint256(1_000_000));
        vm.prank(address(system));
        reactive.react(log_);
        (address first,,,) = reactive.pairMemory(PAIR);
        assertEq(first, address(0));
        assertEq(system.requestCount(), 0);
    }

    function test_doesNotEmitDeprecatedCallback() public {
        _arm();
        assertEq(_signal(ALICE, 6_000_000), 0);
        vm.recordLogs();
        assertEq(_signal(BOB, 6_000_100), 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGt(logs.length, 0);
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != DEPRECATED_CALLBACK_TOPIC);
        }
    }

    function test_refuseOfficialAndD5Addresses() public {
        vm.expectRevert(abi.encodeWithSelector(SignalGuard.ForbiddenAddress.selector, SignalGuard.CAMP_ORIGIN));
        new SignalReactive(SEPOLIA, SignalGuard.CAMP_ORIGIN, SEPOLIA, WINDOW, LIMIT);

        vm.expectRevert(abi.encodeWithSelector(SignalGuard.ForbiddenAddress.selector, SignalGuard.CAMP_REACTIVE));
        new SignalReactive(SEPOLIA, SignalGuard.CAMP_REACTIVE, SEPOLIA, WINDOW, LIMIT);

        vm.expectRevert(abi.encodeWithSelector(SignalGuard.ForbiddenAddress.selector, SignalGuard.D5_REACTIVE));
        new EncounterLedger(IPayable(payable(address(proxy))), SignalGuard.D5_REACTIVE);

        vm.expectRevert(abi.encodeWithSelector(SignalGuard.ForbiddenAddress.selector, SignalGuard.D5_FAILED_CALLBACK));
        new EncounterLedger(IPayable(payable(address(proxy))), SignalGuard.D5_FAILED_CALLBACK);

        _arm();
        vm.expectRevert(abi.encodeWithSelector(SignalGuard.ForbiddenAddress.selector, SignalGuard.CAMP_CALLBACK));
        reactive.setRecipient(SignalGuard.CAMP_CALLBACK);
        vm.expectRevert(abi.encodeWithSelector(SignalGuard.ForbiddenAddress.selector, SignalGuard.D5_CALLBACK));
        reactive.setRecipient(SignalGuard.D5_CALLBACK);
    }

    function test_constructor_revertsOnWrongChainOrBadConfig() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(SignalReactive.WrongChain.selector, uint256(1), uint256(LASNA)));
        new SignalReactive(SEPOLIA, address(board), SEPOLIA, WINDOW, LIMIT);

        vm.chainId(LASNA);
        vm.expectRevert(SignalReactive.BadWindow.selector);
        new SignalReactive(SEPOLIA, address(board), SEPOLIA, 0, LIMIT);
        vm.expectRevert(SignalReactive.BadLimit.selector);
        new SignalReactive(SEPOLIA, address(board), SEPOLIA, WINDOW, 0);
        vm.expectRevert(SignalReactive.BadLimit.selector);
        new SignalReactive(SEPOLIA, address(board), SEPOLIA, WINDOW, 6);
    }

    function test_board_rejectsEmptyPair() public {
        vm.expectRevert(SignalBoard.EmptyPair.selector);
        board.sendSignal(bytes32(0));
    }

    function test_stop_thenSignalDoesNotRequest() public {
        _arm();
        reactive.stop();
        assertTrue(reactive.stopped());
        assertFalse(reactive.subscribed());
        assertEq(_signal(ALICE, 7_000_000), 0);
        assertEq(_signal(BOB, 7_000_100), 0);
        assertEq(system.requestCount(), 0);
        vm.expectRevert(SignalReactive.Stopped.selector);
        reactive.setRecipient(address(ledger));
    }

    function test_coverDebt_whenClear() public {
        reactive.coverDebt();
        ledger.coverDebt();
    }

    function test_badPayload_returnsWithoutRevert() public {
        vm.prank(address(proxy));
        ledger.recordEncounter(address(reactive), PAIR, ALICE, 2, BOB, 1);
        assertEq(ledger.count(), 0);
        vm.prank(address(proxy));
        ledger.recordEncounter(address(reactive), bytes32(0), BOB, 1, ALICE, 2);
        assertEq(ledger.count(), 0);
    }

    /// @dev 部署交易还要再加上 21000 和 init code 的 calldata。这里只卡住 CREATE 本身别突然变大。
    function test_createGas_staysWithinDeployBudget() public {
        uint256 before = gasleft();
        new SignalBoard();
        uint256 boardGas = before - gasleft();

        before = gasleft();
        new SignalReactive{ value: 0 }(SEPOLIA, address(board), SEPOLIA, WINDOW, LIMIT);
        uint256 reactiveGas = before - gasleft();

        before = gasleft();
        new EncounterLedger{ value: 0 }(IPayable(payable(address(proxy))), address(reactive));
        uint256 ledgerGas = before - gasleft();

        emit log_named_uint("board create", boardGas);
        emit log_named_uint("reactive create", reactiveGas);
        emit log_named_uint("ledger create", ledgerGas);
        assertLt(boardGas, 400_000);
        assertLt(reactiveGas, 2_000_000);
        assertLt(ledgerGas, 900_000);
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

    function _decode(bytes memory payload)
        internal
        pure
        returns (
            bytes4 selector,
            address placeholder,
            bytes32 pairId,
            address low,
            uint64 timeLow,
            address high,
            uint64 timeHigh
        )
    {
        selector = bytes4(payload);
        assembly {
            placeholder := mload(add(payload, 36))
            pairId := mload(add(payload, 68))
            low := mload(add(payload, 100))
            timeLow := mload(add(payload, 132))
            high := mload(add(payload, 164))
            timeHigh := mload(add(payload, 196))
        }
    }
}

contract SignalSstoreProbe {
    uint256 internal slot;

    function store() external {
        slot = 1;
    }
}
