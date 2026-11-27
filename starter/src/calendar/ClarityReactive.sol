// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";
import { CalendarGuard } from "./CalendarGuard.sol";

/// @title ClarityReactive — Lasna 上监视已承诺的「一团」是否安静够久
/// @notice 订阅 Sepolia ClarityCalendar 的 touch / pledge / merge，并用 Cron100 检查截止。
///         窗口用事件里的 Sepolia timestamp 起算；cron 用 Lasna block.timestamp 判断是否到期
///         （两条链钟差通常远小于演示窗口）。不用区块个数当窗口。
/// @dev    构造时不订阅。setRecipient 时订阅日历事件 + Cron。无待办时退订 Cron，保留事件订阅。
contract ClarityReactive is AbstractReactive {
    error NotOwner();
    error ZeroAddress();
    error BadWindow();
    error BadCap();
    error WrongChain(uint256 got, uint256 want);
    error Stopped();

    event RecipientSet(address indexed recipient);
    event ThreadNoted(address indexed user, uint256 indexed threadId, uint64 timestamp, bytes32 kind);
    event ReleaseRequested(address indexed user, uint256 indexed threadId, uint64 lastTouch, uint64 nowTs);
    event CronChecked(uint256 checked, uint256 pending, uint256 cronNumber);
    event CronSubscription(bool on);
    event StoppedByOwner(uint256 pendingLeft);

    struct Watch {
        uint64 lastTouchAt;
        bool pledged;
        bool released;
        bool inQueue;
    }

    struct QueueItem {
        address user;
        uint64 threadId;
    }

    address public immutable OWNER;
    uint256 public immutable ORIGIN_CHAIN_ID;
    address public immutable ORIGIN_CONTRACT;
    uint256 public immutable DEST_CHAIN_ID;
    /// @notice 无 touch 多久后彻底放下，单位秒。演示默认 1800（30 分钟）。
    uint256 public immutable WINDOW;
    /// @notice 每次 Cron tick 最多检查几团，防止单次 react 过重。
    uint256 public immutable CRON_CAP;

    uint256 public constant LASNA_CHAIN_ID = 5318007;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    address public constant LEGACY_CRON = 0x0000000000000000000000000000000000fffFfF;
    uint256 public constant CRON100_TOPIC0 = 0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;
    uint256 public constant TOUCH_TOPIC0 = uint256(keccak256("ThreadTouched(address,uint256,uint256)"));
    uint256 public constant PLEDGE_TOPIC0 = uint256(keccak256("LetGoPledged(address,uint256,uint256)"));
    uint256 public constant MERGE_TOPIC0 = uint256(keccak256("ThreadsMerged(address,uint256,uint256)"));
    uint64 public constant CALLBACK_GAS_LIMIT = 400_000;

    address public recipient;
    bool public subscribedEvents;
    bool public subscribedCron;
    bool public stopped;
    uint256 public lastReactBlock;
    uint256 public lastCronNumber;
    uint256 public cronCursor;

    mapping(address => mapping(uint256 => Watch)) public watches;
    QueueItem[] public queue;

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert NotOwner();
        _;
    }

    constructor(
        uint256 originChainId_,
        address originContract_,
        uint256 destChainId_,
        uint256 window_,
        uint256 cronCap_
    ) payable {
        if (block.chainid != LASNA_CHAIN_ID) revert WrongChain(block.chainid, LASNA_CHAIN_ID);
        if (originChainId_ != SEPOLIA_CHAIN_ID) revert WrongChain(originChainId_, SEPOLIA_CHAIN_ID);
        if (destChainId_ != SEPOLIA_CHAIN_ID) revert WrongChain(destChainId_, SEPOLIA_CHAIN_ID);
        if (originContract_ == address(0)) revert ZeroAddress();
        if (window_ == 0 || window_ > type(uint64).max) revert BadWindow();
        if (cronCap_ == 0 || cronCap_ > 32) revert BadCap();
        CalendarGuard.refuse(originContract_);

        OWNER = msg.sender;
        ORIGIN_CHAIN_ID = originChainId_;
        ORIGIN_CONTRACT = originContract_;
        DEST_CHAIN_ID = destChainId_;
        WINDOW = window_;
        CRON_CAP = cronCap_;
    }

    function pendingCount() external view returns (uint256) {
        return queue.length;
    }

    function setRecipient(address recipient_) external onlyOwner {
        if (stopped) revert Stopped();
        if (recipient_ == address(0)) revert ZeroAddress();
        CalendarGuard.refuse(recipient_);
        recipient = recipient_;
        emit RecipientSet(recipient_);
        if (!subscribedEvents) _setEventSubscription(true);
        // Cron 等有待办再订，避免空转扣费。
    }

    function stop() external onlyOwner {
        if (stopped && !subscribedEvents && !subscribedCron) return;
        if (!stopped) {
            stopped = true;
            emit StoppedByOwner(queue.length);
        }
        if (subscribedCron) _setCronSubscription(false);
        if (subscribedEvents) _setEventSubscription(false);
    }

    function coverDebt() external {
        _coverDebt();
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        lastReactBlock = block.number;
        if (log_.topic0 == CRON100_TOPIC0) {
            _onCron(log_);
            return;
        }
        if (!_acceptedOrigin(log_)) return;
        if (log_.topic0 == TOUCH_TOPIC0) {
            _onTouchOrPledge(log_, false);
        } else if (log_.topic0 == PLEDGE_TOPIC0) {
            _onTouchOrPledge(log_, true);
        } else if (log_.topic0 == MERGE_TOPIC0) {
            _onMerge(log_);
        }
    }

    function _acceptedOrigin(LogRecord calldata log_) internal view returns (bool) {
        if (log_.contractAddress != ORIGIN_CONTRACT) return false;
        if (log_.chainId != ORIGIN_CHAIN_ID) return false;
        if (stopped || !subscribedEvents || recipient == address(0)) return false;
        // ThreadsMerged 三个参数全 indexed，data 为空；touch/pledge 需要 data 里的 timestamp。
        if (log_.topic0 != MERGE_TOPIC0 && log_.data.length < 32) return false;
        return true;
    }

    function _onTouchOrPledge(LogRecord calldata log_, bool isPledge) internal {
        if (log_.topic1 != uint256(uint160(log_.topic1))) return;
        address user = address(uint160(log_.topic1));
        uint256 threadId = log_.topic2;
        if (user == address(0) || threadId == 0 || threadId > type(uint64).max) return;
        uint64 ts = _timestamp(log_.data);
        if (ts == 0) return;

        Watch storage w = watches[user][threadId];
        if (ts >= w.lastTouchAt) w.lastTouchAt = ts;
        if (w.released) w.released = false;
        if (isPledge) w.pledged = true;
        emit ThreadNoted(user, threadId, ts, isPledge ? bytes32("pledge") : bytes32("touch"));

        if (w.pledged && !w.released) {
            _enqueue(user, uint64(threadId));
            if (!subscribedCron && !stopped) _setCronSubscription(true);
        }
    }

    function _onMerge(LogRecord calldata log_) internal {
        if (log_.topic1 != uint256(uint160(log_.topic1))) return;
        address user = address(uint160(log_.topic1));
        uint256 fromId = log_.topic2;
        uint256 intoId = log_.topic3;
        if (user == address(0) || fromId == 0 || intoId == 0) return;
        if (fromId > type(uint64).max || intoId > type(uint64).max) return;

        Watch storage from = watches[user][fromId];
        Watch storage into = watches[user][intoId];
        if (from.lastTouchAt > into.lastTouchAt) into.lastTouchAt = from.lastTouchAt;
        into.pledged = into.pledged || from.pledged;
        into.released = into.released && from.released;
        _dequeue(user, uint64(fromId));
        emit ThreadNoted(user, intoId, into.lastTouchAt, bytes32("merge"));
        if (into.pledged && !into.released) {
            _enqueue(user, uint64(intoId));
            if (!subscribedCron && !stopped) _setCronSubscription(true);
        }
    }

    function _onCron(LogRecord calldata log_) internal {
        if (log_.contractAddress != LEGACY_CRON) return;
        if (log_.chainId != LASNA_CHAIN_ID) return;
        uint256 cronNumber = _cronNumber(log_);
        lastCronNumber = cronNumber;
        if (stopped || !subscribedCron || recipient == address(0)) {
            emit CronChecked(0, queue.length, cronNumber);
            return;
        }

        uint256 checked = 0;
        uint256 cap = CRON_CAP;
        uint256 len = queue.length;
        uint64 nowTs = uint64(block.timestamp);

        while (checked < cap && len > 0) {
            if (cronCursor >= len) cronCursor = 0;
            QueueItem memory item = queue[cronCursor];
            Watch storage w = watches[item.user][item.threadId];
            checked += 1;

            if (!w.pledged || w.released || !w.inQueue || w.lastTouchAt == 0) {
                _removeAt(cronCursor);
                len = queue.length;
                continue;
            }

            if (uint256(nowTs) >= uint256(w.lastTouchAt) + WINDOW) {
                w.released = true;
                w.inQueue = false;
                emit ReleaseRequested(item.user, item.threadId, w.lastTouchAt, nowTs);
                _requestRelease(item.user, item.threadId);
                _removeAt(cronCursor);
                len = queue.length;
                continue;
            }

            cronCursor += 1;
        }

        emit CronChecked(checked, queue.length, cronNumber);
        if (queue.length == 0 && subscribedCron) _setCronSubscription(false);
    }

    function _requestRelease(address user, uint256 threadId) internal {
        bytes memory payload =
            abi.encodeWithSignature("markReleased(address,address,uint256)", address(0), user, threadId);
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: DEST_CHAIN_ID,
                recipient: recipient,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }

    function _enqueue(address user, uint64 threadId) internal {
        Watch storage w = watches[user][threadId];
        if (w.inQueue) return;
        w.inQueue = true;
        queue.push(QueueItem({user: user, threadId: threadId}));
    }

    function _dequeue(address user, uint64 threadId) internal {
        Watch storage w = watches[user][threadId];
        if (!w.inQueue) return;
        w.inQueue = false;
        uint256 len = queue.length;
        for (uint256 i = 0; i < len; i++) {
            if (queue[i].user == user && queue[i].threadId == threadId) {
                _removeAt(i);
                return;
            }
        }
    }

    function _removeAt(uint256 index) internal {
        uint256 last = queue.length - 1;
        if (index != last) {
            queue[index] = queue[last];
        }
        queue.pop();
        if (cronCursor > last) cronCursor = 0;
        else if (cronCursor > index && cronCursor > 0) cronCursor -= 1;
    }

    function _timestamp(bytes calldata data) internal pure returns (uint64) {
        uint256 ts = abi.decode(data, (uint256));
        if (ts == 0 || ts > type(uint64).max) return 0;
        return uint64(ts);
    }

    function _cronNumber(LogRecord calldata log_) internal pure returns (uint256) {
        if (log_.topic1 != 0) return log_.topic1;
        if (log_.data.length >= 32) return abi.decode(log_.data, (uint256));
        return log_.blockNumber;
    }

    function _setEventSubscription(bool on) internal {
        subscribedEvents = on;
        // 用合约地址作具体条件；topic0 通配，在 react 里过滤三种事件。
        if (on) {
            SYSTEM.subscribe(
                ORIGIN_CHAIN_ID, ORIGIN_CONTRACT, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
        } else {
            SYSTEM.unsubscribe(
                ORIGIN_CHAIN_ID, ORIGIN_CONTRACT, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
        }
    }

    function _setCronSubscription(bool on) internal {
        subscribedCron = on;
        emit CronSubscription(on);
        if (on) {
            SYSTEM.subscribe(
                LASNA_CHAIN_ID, LEGACY_CRON, CRON100_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
        } else {
            SYSTEM.unsubscribe(
                LASNA_CHAIN_ID, LEGACY_CRON, CRON100_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
        }
    }
}
