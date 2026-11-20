// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test, Vm } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { D5CronReactive } from "../src/d5/D5CronReactive.sol";
import { D5CronCallback } from "../src/d5/D5CronCallback.sol";

/// @dev 放在 0x8888…8888 上，记录订阅、退订和回调请求。不广播，也不持有私钥。
contract D5MockSystem {
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
contract D5MockProxy {
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

contract D5CronTest is Test {
    uint256 constant DEST_CHAIN = 11155111;
    uint256 constant LIMIT = 2;
    uint256 constant LASNA = 5318007;
    address constant LEGACY = 0x0000000000000000000000000000000000fffFfF;
    uint256 constant CRON100 = 0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;
    uint256 constant IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    bytes32 constant DEPRECATED_CALLBACK_TOPIC = keccak256("Callback(uint256,address,uint64,bytes)");

    D5MockSystem system;
    D5MockProxy proxy;
    D5CronReactive reactive;
    D5CronCallback callback;

    function setUp() public {
        vm.chainId(LASNA);
        D5MockSystem impl = new D5MockSystem();
        vm.etch(0x8888888888888888888888888888888888888888, address(impl).code);
        system = D5MockSystem(payable(0x8888888888888888888888888888888888888888));
        proxy = new D5MockProxy();
        reactive = new D5CronReactive{ value: 1 ether }(DEST_CHAIN, LIMIT);
        callback = new D5CronCallback{ value: 0.1 ether }(IPayable(payable(address(proxy))), address(reactive));
        assertEq(reactive.LASNA_CHAIN_ID(), LASNA);
        assertEq(reactive.LEGACY_CRON(), LEGACY);
        assertEq(reactive.CRON100_TOPIC0(), CRON100);
    }

    function _arm() internal {
        reactive.setRecipient(address(callback));
    }

    /// @param indexedNumber 非 0 时走线上布局：number 在 topic1，data 为空。
    /// @param dataNumber    indexedNumber 为 0 时走文档布局：number 在 data 里。
    function _cron(uint256 indexedNumber, uint256 dataNumber, uint256 txHash)
        internal
        pure
        returns (IReactive.LogRecord memory log_)
    {
        log_.chainId = LASNA;
        log_.contractAddress = LEGACY;
        log_.topic0 = CRON100;
        log_.topic1 = indexedNumber;
        if (indexedNumber == 0) log_.data = abi.encode(dataNumber);
        log_.opCode = indexedNumber == 0 ? 1 : 2;
        log_.blockNumber = indexedNumber == 0 ? dataNumber : indexedNumber;
        log_.txHash = txHash;
    }

    function _decodePayload(bytes memory payload)
        internal
        pure
        returns (address placeholder, uint256 cronNumber, uint256 tickIndex)
    {
        assembly {
            placeholder := mload(add(payload, 36))
            cronNumber := mload(add(payload, 68))
            tickIndex := mload(add(payload, 100))
        }
    }

    function test_constructor_revertsOnWrongChain() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(D5CronReactive.WrongChain.selector, uint256(1), uint256(5318007)));
        new D5CronReactive(DEST_CHAIN, LIMIT);
    }

    function test_constructor_revertsOnZeroLimit() public {
        vm.expectRevert(D5CronReactive.ZeroLimit.selector);
        new D5CronReactive(DEST_CHAIN, 0);
    }

    function test_doesNotSubscribeUntilRecipientSet() public view {
        assertEq(system.subCount(), 0);
        assertEq(reactive.recipient(), address(0));
        assertFalse(reactive.subscribed());
        assertEq(reactive.remaining(), LIMIT);
    }

    function test_setRecipient_subscribesCron100Once() public {
        _arm();
        assertEq(system.subCount(), 1);
        (uint256 chainId, address cron, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3) = system.subs(0);
        assertEq(chainId, 5318007);
        assertEq(cron, LEGACY);
        assertEq(topic0, CRON100);
        assertEq(topic1, IGNORE);
        assertEq(topic2, IGNORE);
        assertEq(topic3, IGNORE);
        assertTrue(reactive.subscribed());

        reactive.setRecipient(address(callback));
        assertEq(system.subCount(), 1);
    }

    function test_auth_setRecipientOnlyOwner() public {
        vm.expectRevert(D5CronReactive.ZeroAddress.selector);
        reactive.setRecipient(address(0));

        vm.prank(address(0xBEEF));
        vm.expectRevert(D5CronReactive.NotOwner.selector);
        reactive.setRecipient(address(callback));
        assertEq(system.subCount(), 0);
    }

    function test_auth_reactOnlySystem() public {
        _arm();
        vm.expectRevert();
        reactive.react(_cron(8813600, 0, 1));
    }

    function test_wrongTopic_doesNotRequestOrCount() public {
        _arm();
        IReactive.LogRecord memory log_ = _cron(8813600, 0, 1);
        log_.topic0 = uint256(keccak256("Cron10(uint256)"));
        vm.prank(address(system));
        reactive.react(log_);
        assertEq(system.requestCount(), 0);
        assertEq(reactive.remaining(), LIMIT);
        assertEq(reactive.lastCronNumber(), 0);
    }

    function test_reactBeforeArm_doesNotConsumeQuota() public {
        vm.prank(address(system));
        reactive.react(_cron(8813600, 0, 1));
        assertEq(system.requestCount(), 0);
        assertEq(reactive.remaining(), LIMIT);
        assertEq(reactive.lastCronNumber(), 8813600);
    }

    function test_limit_stopsAfterTwoAndThirdTickDoesNotRequest() public {
        _arm();
        vm.startPrank(address(system));
        reactive.react(_cron(8813600, 0, 11));
        reactive.react(_cron(0, 8813700, 12));
        reactive.react(_cron(8813800, 0, 13));
        vm.stopPrank();

        assertEq(system.requestCount(), 2);
        assertEq(system.unsubCount(), 1);
        assertEq(reactive.remaining(), 0);
        assertEq(reactive.executed(), 2);
        assertFalse(reactive.subscribed());
        assertTrue(reactive.stopped());
        // 第三次仍然送到了 react()，只记账，不再请求回调。
        assertEq(reactive.lastCronNumber(), 8813800);

        (address placeholder1, uint256 cron1, uint256 tick1) = _decodePayload(system.requestAt(0).payload);
        (address placeholder2, uint256 cron2, uint256 tick2) = _decodePayload(system.requestAt(1).payload);
        assertEq(placeholder1, address(0));
        assertEq(placeholder2, address(0));
        assertEq(cron1, 8813600);
        assertEq(cron2, 8813700);
        assertEq(tick1, 1);
        assertEq(tick2, 2);
        assertEq(system.requestAt(0).chainId, DEST_CHAIN);
        assertEq(system.requestAt(0).recipient, address(callback));
        assertEq(system.requestAt(0).gasLimit, 400_000);
        assertGe(system.requestAt(0).gasLimit, 100_000);
    }

    function test_unsubscribeCriteriaMatchSubscribe() public {
        _arm();
        vm.prank(address(system));
        reactive.react(_cron(8813600, 0, 1));
        vm.prank(address(system));
        reactive.react(_cron(8813700, 0, 2));

        (
            uint256 chainId,
            address cron,
            uint256 topic0,
            uint256 topic1,
            uint256 topic2,
            uint256 topic3
        ) = system.subs(0);
        (
            uint256 uchainId,
            address ucron,
            uint256 utopic0,
            uint256 utopic1,
            uint256 utopic2,
            uint256 utopic3
        ) = system.unsubs(0);
        assertEq(uchainId, chainId);
        assertEq(ucron, cron);
        assertEq(utopic0, topic0);
        assertEq(utopic1, topic1);
        assertEq(utopic2, topic2);
        assertEq(utopic3, topic3);
    }

    function test_doesNotEmitDeprecatedCallback() public {
        _arm();
        vm.recordLogs();
        vm.prank(address(system));
        reactive.react(_cron(8813600, 0, 1));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != DEPRECATED_CALLBACK_TOPIC);
        }
        assertEq(system.requestCount(), 1);
    }

    function test_callback_receivesTwoTicks() public {
        _arm();
        vm.prank(address(system));
        reactive.react(_cron(8813600, 0, 11));
        (bool ok,) = proxy.deliver(address(callback), address(reactive), system.requestAt(0).payload);
        assertTrue(ok);

        vm.prank(address(system));
        reactive.react(_cron(8813700, 0, 12));
        (ok,) = proxy.deliver(address(callback), address(reactive), system.requestAt(1).payload);
        assertTrue(ok);

        assertEq(callback.count(), 2);
        assertEq(callback.lastCronNumber(), 8813700);
        assertEq(callback.lastTickIndex(), 2);
        assertEq(callback._CALLBACK_SENDER(), address(reactive));

        uint256 requests = system.requestCount();
        vm.prank(address(system));
        reactive.react(_cron(8813800, 0, 13));
        assertEq(system.requestCount(), requests);
        assertEq(callback.count(), 2);
    }

    function test_auth_callbackRejectsDirectCall() public {
        bytes memory payload = abi.encodeWithSignature("onTick(address,uint256,uint256)", address(reactive), 8813600, 1);
        (bool ok,) = address(callback).call(payload);
        assertFalse(ok);
        assertEq(callback.count(), 0);
    }

    function test_auth_callbackRejectsWrongReactive() public {
        bytes memory payload = abi.encodeWithSignature("onTick(address,uint256,uint256)", address(0), 8813600, 1);
        (bool ok,) = proxy.deliver(address(callback), address(0xBEEF), payload);
        assertFalse(ok);
        assertEq(callback.count(), 0);
    }

    function test_ownerStop_thenTickDoesNotRequest() public {
        _arm();
        reactive.stop();
        assertFalse(reactive.subscribed());
        assertTrue(reactive.stopped());
        assertEq(system.unsubCount(), 1);

        vm.prank(address(system));
        reactive.react(_cron(8813600, 0, 1));
        assertEq(system.requestCount(), 0);
        assertEq(reactive.remaining(), LIMIT);

        uint256 unsubs = system.unsubCount();
        reactive.stop();
        assertEq(system.unsubCount(), unsubs);
    }

    function test_auth_stopOnlyOwner() public {
        _arm();
        vm.prank(address(0xBEEF));
        vm.expectRevert(D5CronReactive.NotOwner.selector);
        reactive.stop();
        assertTrue(reactive.subscribed());
    }

    function test_setRecipientAfterStopReverts() public {
        _arm();
        reactive.stop();
        vm.expectRevert(D5CronReactive.Stopped.selector);
        reactive.setRecipient(address(callback));
        assertEq(system.subCount(), 1);
    }

    function test_coverDebt_whenClear() public {
        reactive.coverDebt();
        callback.coverDebt();
    }
}
