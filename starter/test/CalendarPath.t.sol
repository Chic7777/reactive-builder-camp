// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test, Vm } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { ClarityCalendar } from "../src/calendar/ClarityCalendar.sol";
import { ClarityReactive } from "../src/calendar/ClarityReactive.sol";
import { CalendarGuard } from "../src/calendar/CalendarGuard.sol";

contract CalendarMockSystem {
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

contract CalendarMockProxy {
    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable {}

    function deliver(address recipient, address reactiveAddr, bytes memory payload)
        external
        returns (bool ok, bytes memory ret)
    {
        assembly {
            mstore(add(payload, 36), reactiveAddr)
        }
        (ok, ret) = recipient.call(payload);
    }
}

contract CalendarSstoreProbe {
    uint256 internal slot;

    function store() external {
        slot = 1;
    }
}

/// @notice 本地走完：开团 / 链接合并 / 承诺 / touch 重置窗口 / 到期释放 / cron 上限 / 回调 gas。
contract CalendarPathTest is Test {
    uint256 constant SEPOLIA = 11155111;
    uint256 constant LASNA = 5318007;
    uint256 constant WINDOW = 1800;
    uint256 constant CAP = 2;
    bytes32 constant TOUCH_TOPIC = keccak256("ThreadTouched(address,uint256,uint256)");
    bytes32 constant PLEDGE_TOPIC = keccak256("LetGoPledged(address,uint256,uint256)");
    bytes32 constant MERGE_TOPIC = keccak256("ThreadsMerged(address,uint256,uint256)");
    uint256 constant CRON100 = 0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;
    address constant LEGACY = 0x0000000000000000000000000000000000fffFfF;
    address constant USER = address(0xA11CE);

    CalendarMockSystem system;
    CalendarMockProxy proxy;
    ClarityCalendar calendar;
    ClarityReactive reactive;
    CalendarSstoreProbe probe;

    function setUp() public {
        vm.chainId(LASNA);
        CalendarMockSystem impl = new CalendarMockSystem();
        vm.etch(0x8888888888888888888888888888888888888888, address(impl).code);
        system = CalendarMockSystem(payable(0x8888888888888888888888888888888888888888));
        proxy = new CalendarMockProxy();
        calendar = new ClarityCalendar{ value: 0.1 ether }(IPayable(payable(address(proxy))));
        probe = new CalendarSstoreProbe();
        reactive = new ClarityReactive{ value: 1 ether }(SEPOLIA, address(calendar), SEPOLIA, WINDOW, CAP);
        calendar.bindReactive(address(reactive));
        reactive.setRecipient(address(calendar));
    }

    function test_openTouchPledge_andReleaseAfterWindow() public {
        uint256 id = _open();
        assertEq(system.requestCount(), 0);
        assertFalse(reactive.subscribedCron());

        _pledge(id);
        assertTrue(reactive.subscribedCron());
        assertEq(reactive.pendingCount(), 1);
        assertTrue(calendar.isPledged(USER, id));
        assertFalse(calendar.isReleased(USER, id));

        vm.warp(block.timestamp + WINDOW - 1);
        assertEq(_cron(9_000_001), 0);
        assertFalse(calendar.isReleased(USER, id));

        vm.warp(block.timestamp + 2);
        assertEq(_cron(9_000_002), 1);
        _deliverLatest();
        assertTrue(calendar.isReleased(USER, id));
        assertEq(reactive.pendingCount(), 0);
        assertFalse(reactive.subscribedCron());
    }

    /// @notice New related write (touch) returns thread to not-let-go: clears pledged; old window cannot release.
    function test_touchClearsPledge_requiresRePledge() public {
        uint256 id = _open();
        _pledge(id);
        assertTrue(calendar.isPledged(USER, id));
        assertTrue(reactive.subscribedCron());
        assertEq(reactive.pendingCount(), 1);

        uint64 pledgedAt = calendar.lastTouchAt(USER, id);
        vm.warp(uint256(pledgedAt) + WINDOW - 10);
        _touch(id);

        assertFalse(calendar.isPledged(USER, id), "touch returns thread to not-let-go");
        assertFalse(calendar.isReleased(USER, id));
        assertEq(reactive.pendingCount(), 0, "unpledged thread leaves cron queue");
        assertFalse(reactive.subscribedCron());

        // Old window must not release after unpledge
        vm.warp(uint256(pledgedAt) + WINDOW + 1);
        assertEq(_cron(1), 0, "unpledged thread must not release");
        assertFalse(calendar.isReleased(USER, id));

        // Re-pledge -> letting-go -> released after window
        _pledge(id);
        assertTrue(calendar.isPledged(USER, id));
        vm.warp(uint256(calendar.lastTouchAt(USER, id)) + WINDOW + 1);
        assertEq(_cron(2), 1);
        _deliverLatest();
        assertTrue(calendar.isReleased(USER, id));
    }

    function test_linkNetworkMerge_isOneThread() public {
        uint256 a = _open();
        uint256 b = _open();
        uint256 c = _open();

        uint256[] memory ab = new uint256[](2);
        ab[0] = a;
        ab[1] = b;
        uint256 root = _link(ab);
        assertEq(root, a < b ? a : b);
        assertEq(calendar.find(USER, a), root);
        assertEq(calendar.find(USER, b), root);

        uint256[] memory bc = new uint256[](2);
        bc[0] = b;
        bc[1] = c;
        root = _link(bc);
        assertEq(calendar.find(USER, a), root);
        assertEq(calendar.find(USER, b), root);
        assertEq(calendar.find(USER, c), root);

        _pledge(c);
        assertTrue(calendar.isPledged(USER, a));
        assertEq(reactive.pendingCount(), 1);
    }

    function test_mergeEmitsAndReactiveFollowsInto() public {
        uint256 a = _open();
        uint256 b = _open();
        _pledge(b);
        assertEq(reactive.pendingCount(), 1);

        vm.recordLogs();
        vm.prank(USER);
        calendar.merge(a, b);
        _feedRecorded();

        uint256 root = calendar.find(USER, a);
        assertTrue(calendar.isPledged(USER, root));
        (address qu, uint64 qt) = reactive.queue(0);
        assertEq(qu, USER);
        assertEq(uint256(qt), root);
    }

    /// @notice After released, a new related write returns to not-let-go (clears released + pledged).
    function test_touchReleasedReturnsToNotLetGo() public {
        uint256 id = _open();
        _pledge(id);
        vm.warp(uint256(calendar.lastTouchAt(USER, id)) + WINDOW + 1);
        assertEq(_cron(3), 1);
        _deliverLatest();
        assertTrue(calendar.isReleased(USER, id));

        _touch(id);
        assertFalse(calendar.isReleased(USER, id));
        assertFalse(calendar.isPledged(USER, id), "reopen is not-let-go, not still letting-go");
        assertEq(reactive.pendingCount(), 0);
        assertFalse(reactive.subscribedCron());
    }

    /// @notice linkAndTouch after a pledge clears pledged on the merged root.
    function test_linkAndTouchClearsPledgedOnMergedThread() public {
        uint256 a = _open();
        uint256 b = _open();
        _pledge(a);
        assertTrue(calendar.isPledged(USER, a));

        uint256[] memory ab = new uint256[](2);
        ab[0] = a;
        ab[1] = b;
        uint256 root = _link(ab);
        assertFalse(calendar.isPledged(USER, root), "linkAndTouch ends in not-let-go");
        assertFalse(calendar.isReleased(USER, root));
        assertEq(reactive.pendingCount(), 0);
    }

    function test_noReleaseBeforeWindow() public {
        uint256 id = _open();
        _pledge(id);
        vm.warp(uint256(calendar.lastTouchAt(USER, id)) + WINDOW - 1);
        assertEq(_cron(4), 0);
        assertEq(system.requestCount(), 0);
    }

    function test_onlyProxyAndBoundReactiveCanRelease() public {
        uint256 id = _open();
        _pledge(id);

        vm.expectRevert();
        calendar.markReleased(address(reactive), USER, id);

        vm.prank(address(proxy));
        vm.expectRevert(
            abi.encodeWithSelector(ClarityCalendar.CallbackNotAuthorized.selector, address(0xBEEF), address(reactive))
        );
        calendar.markReleased(address(0xBEEF), USER, id);

        assertFalse(calendar.isReleased(USER, id));
    }

    function test_cronCap_boundsWorkPerTick() public {
        for (uint256 i = 0; i < 5; i++) {
            uint256 id = _open();
            _pledge(id);
        }
        assertEq(reactive.pendingCount(), 5);
        vm.warp(block.timestamp + WINDOW + 10);
        uint256 before = system.requestCount();
        _cron(50);
        assertEq(system.requestCount() - before, 2);
        assertEq(reactive.pendingCount(), 3);
    }

    function test_markReleased_oneSlotAndUnderStipend() public {
        uint256 id = _open();
        _pledge(id);

        uint256 probeBefore = gasleft();
        probe.store();
        uint256 sstoreGas = probeBefore - gasleft();

        vm.prank(address(proxy));
        uint256 before = gasleft();
        calendar.markReleased(address(reactive), USER, id);
        uint256 used = before - gasleft();
        emit log_named_uint("sstore probe", sstoreGas);
        emit log_named_uint("markReleased gas", used);
        // markReleased 改的是 open/pledge 已经写过的槽，是暖 SSTORE，比冷写入便宜。
        // Proxy 大约只转出 155800；这里留余量。冷 SSTORE 探针只用来对照环境。
        assertLt(used, 150_000, "markReleased exceeds Sepolia callback stipend");
        assertLt(used, 80_000, "warm markReleased unexpectedly expensive");
        if (sstoreGas > 50_000) {
            emit log_string("amsterdam cold SSTORE probe active; callback stays warm-update");
        }
        assertTrue(calendar.isReleased(USER, id));
    }

    function test_refuseOfficialAndD5Addresses() public {
        vm.expectRevert(abi.encodeWithSelector(CalendarGuard.ForbiddenAddress.selector, CalendarGuard.CAMP_ORIGIN));
        new ClarityReactive(SEPOLIA, CalendarGuard.CAMP_ORIGIN, SEPOLIA, WINDOW, CAP);

        ClarityCalendar fresh = new ClarityCalendar(IPayable(payable(address(proxy))));
        vm.expectRevert(abi.encodeWithSelector(CalendarGuard.ForbiddenAddress.selector, CalendarGuard.D5_REACTIVE));
        fresh.bindReactive(CalendarGuard.D5_REACTIVE);

        vm.expectRevert(abi.encodeWithSelector(CalendarGuard.ForbiddenAddress.selector, CalendarGuard.CAMP_CALLBACK));
        reactive.setRecipient(CalendarGuard.CAMP_CALLBACK);
    }

    function test_reactOnlySystem_andWrongTopicIgnored() public {
        _open();
        IReactive.LogRecord memory log_;
        log_.chainId = SEPOLIA;
        log_.contractAddress = address(calendar);
        log_.topic0 = uint256(TOUCH_TOPIC);
        log_.topic1 = uint256(uint160(USER));
        log_.topic2 = 1;
        log_.data = abi.encode(uint256(1_000_000));
        vm.expectRevert();
        reactive.react(log_);

        log_.topic0 = uint256(keccak256("Ping(address,uint256)"));
        vm.prank(address(system));
        reactive.react(log_);
        assertEq(reactive.pendingCount(), 0);
    }

    function test_windowUsesEventTimestampNotBlockCount() public {
        uint256 id = _open();
        _pledge(id);
        vm.warp(10_000_000);
        // 覆盖上次 touch 时间为很早的事件时间戳
        _reactManual(USER, id, 1000, true);
        assertEq(_cron(8), 1);
    }

    function test_emptyLinkOpensThread() public {
        vm.recordLogs();
        vm.prank(USER);
        uint256[] memory none = new uint256[](0);
        uint256 id = calendar.linkAndTouch(none);
        _feedRecorded();
        assertEq(id, 1);
        assertEq(calendar.nextThreadId(USER), 1);
    }

    function test_createGas_staysWithinDeployBudget() public {
        uint256 before = gasleft();
        new ClarityCalendar(IPayable(payable(address(proxy))));
        uint256 calGas = before - gasleft();
        before = gasleft();
        new ClarityReactive{ value: 0 }(SEPOLIA, address(calendar), SEPOLIA, WINDOW, CAP);
        uint256 reacGas = before - gasleft();
        emit log_named_uint("calendar create", calGas);
        emit log_named_uint("reactive create", reacGas);
        assertLt(calGas, 2_500_000);
        assertLt(reacGas, 3_000_000);
    }

    function _open() internal returns (uint256 id) {
        vm.recordLogs();
        vm.prank(USER);
        id = calendar.openThread();
        _feedRecorded();
    }

    function _touch(uint256 id) internal {
        vm.recordLogs();
        vm.prank(USER);
        calendar.touch(id);
        _feedRecorded();
    }

    function _pledge(uint256 id) internal {
        vm.recordLogs();
        vm.prank(USER);
        calendar.pledgeLetGo(id);
        _feedRecorded();
    }

    function _link(uint256[] memory ids) internal returns (uint256 root) {
        vm.recordLogs();
        vm.prank(USER);
        root = calendar.linkAndTouch(ids);
        _feedRecorded();
    }

    function _feedRecorded() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            bytes32 t0 = logs[i].topics[0];
            if (t0 == TOUCH_TOPIC || t0 == PLEDGE_TOPIC || t0 == MERGE_TOPIC) {
                _reactFromLog(logs[i]);
            }
        }
    }

    function _reactFromLog(Vm.Log memory entry) internal {
        IReactive.LogRecord memory log_;
        log_.chainId = SEPOLIA;
        log_.contractAddress = address(calendar);
        log_.topic0 = uint256(entry.topics[0]);
        log_.topic1 = uint256(entry.topics[1]);
        log_.topic2 = entry.topics.length > 2 ? uint256(entry.topics[2]) : 0;
        log_.topic3 = entry.topics.length > 3 ? uint256(entry.topics[3]) : 0;
        log_.data = entry.data;
        log_.blockNumber = block.number;
        vm.prank(address(system));
        reactive.react(log_);
    }

    function _reactManual(address user, uint256 id, uint256 ts, bool pledge) internal {
        IReactive.LogRecord memory log_;
        log_.chainId = SEPOLIA;
        log_.contractAddress = address(calendar);
        log_.topic0 = uint256(pledge ? PLEDGE_TOPIC : TOUCH_TOPIC);
        log_.topic1 = uint256(uint160(user));
        log_.topic2 = id;
        log_.data = abi.encode(ts);
        vm.prank(address(system));
        reactive.react(log_);
    }

    function _cron(uint256 number) internal returns (uint256 newRequests) {
        uint256 before = system.requestCount();
        IReactive.LogRecord memory log_;
        log_.chainId = LASNA;
        log_.contractAddress = LEGACY;
        log_.topic0 = CRON100;
        log_.topic1 = number;
        log_.blockNumber = number;
        vm.prank(address(system));
        reactive.react(log_);
        return system.requestCount() - before;
    }

    function _deliverLatest() internal {
        uint256 n = system.requestCount();
        require(n > 0, "no callback");
        ISystemContract.CallbackConfiguration_V_1_0 memory cfg = system.requestAt(n - 1);
        (bool ok,) = proxy.deliver(cfg.recipient, address(reactive), cfg.payload);
        assertTrue(ok);
    }
}
