// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";
import { SignalGuard } from "./SignalGuard.sol";

/// @title SignalReactive — Lasna 上判断两个人有没有在时间窗里相遇
/// @notice 订阅 Sepolia 上 SignalBoard 的 SignalSent。react() 记下这个人在这个 pairId 里的最近一次信号时间。
///         两个不同地址的信号时间相差不超过 WINDOW，才请求 Sepolia 回调。没凑成对就 return，不 revert。
/// @dev    教学/演示。运行时没有 AI。SYSTEM 与仓库里其他合约相同，是 0x8888…8888。
///         时间窗比较的是事件里的 timestamp（Sepolia 的 block.timestamp），不是 Lasna 的区块时间。
///         两条链的钟不一样，所以不能用「react() 被调用的那一刻」来判断他们是不是同一小时挥的手。
///         构造时不订阅。订阅发生在 setRecipient，避免 Ledger 还没部署时就对着空地址烧 lREACT。
///         每个 SignalSent 都会让网络调用 react() 并扣 lREACT，直到退订或欠款。MAX_ENCOUNTERS 用来停掉后续回调。
contract SignalReactive is AbstractReactive {
    error NotOwner();
    error ZeroAddress();
    error BadLimit();
    error BadWindow();
    error WrongChain(uint256 got, uint256 want);
    error Stopped();

    event RecipientSet(address indexed recipient);
    event SignalNoted(address indexed sender, bytes32 indexed pairId, uint64 timestamp);
    /// @notice 两个人都挥过手，但时间差大于 WINDOW。没有请求回调。
    event WindowMissed(bytes32 indexed pairId, uint64 earlier, uint64 later, uint256 window);
    event EncounterRequested(bytes32 indexed pairId, address recipient);
    /// @param byOwner true 表示主人调用了 stop()；false 表示相遇次数用完后自动退订。
    event EncountersStopped(uint256 requested, bool byOwner);

    /// @dev 一个房间只记最近的两个不同地址。第三人到来时，替换更早的那一个。
    ///      这样「两个人」始终是最近的一对，而不是第一对永远占着位置。
    struct PairMemory {
        address first;
        uint64 firstAt;
        address second;
        uint64 secondAt;
    }

    struct Meeting {
        bool met;
        bool bothPresent;
        address low;
        uint64 timeLow;
        address high;
        uint64 timeHigh;
        uint64 earlier;
        uint64 later;
    }

    address public immutable OWNER;
    uint256 public immutable ORIGIN_CHAIN_ID;
    address public immutable ORIGIN_CONTRACT;
    uint256 public immutable DEST_CHAIN_ID;
    /// @notice 两条 Sepolia 信号的时间差上限，单位是秒。默认脚本传 3600（1 小时）。相差正好等于 WINDOW 也算遇见。
    uint256 public immutable WINDOW;
    /// @notice 最多请求几次回调。用完就退订。不能超过账本的第二道上限 5。
    uint256 public immutable MAX_ENCOUNTERS;

    uint256 public constant LASNA_CHAIN_ID = 5318007;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    /// @notice keccak256("SignalSent(address,bytes32,uint256)")。sender 在 topic1，pairId 在 topic2。
    uint256 public constant SIGNAL_TOPIC0 = uint256(keccak256("SignalSent(address,bytes32,uint256)"));
    /// @notice 中继按这个 gas 发 Sepolia 交易。Proxy 留下 _extraGas 150000 和 _maxChargeGas 50000，
    ///         实际转给 recordEncounter 的大约是 155800。账本必须在这个额度里写完一个槽。
    uint64 public constant CALLBACK_GAS_LIMIT = 400_000;

    address public recipient;
    uint256 public remaining;
    bool public subscribed;
    bool public stopped;
    /// @notice 最近一次已经请求过回调的相遇。同一对地址、同一个 pairId、同样的两个时间再送来，不再请求。
    bytes32 public lastEncounterKey;
    uint256 public lastReactBlock;

    mapping(bytes32 => PairMemory) public pairMemory;

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert NotOwner();
        _;
    }

    /// @param originChainId_  源链。固定 Ethereum Sepolia 11155111。
    /// @param originContract_ SignalBoard 的地址。不能是官方示例或 D5 合约。
    /// @param destChainId_    目标链。同样是 Sepolia。同一条链当源和目标是一条完整链路。
    /// @param window_         时间窗秒数。传 0，或大到装不进 uint64，会在部署时失败。
    /// @param maxEncounters_  最多记几次相遇。传 0 或大于 5 会失败。脚本默认 3。
    constructor(
        uint256 originChainId_,
        address originContract_,
        uint256 destChainId_,
        uint256 window_,
        uint256 maxEncounters_
    ) payable {
        if (block.chainid != LASNA_CHAIN_ID) revert WrongChain(block.chainid, LASNA_CHAIN_ID);
        if (originChainId_ != SEPOLIA_CHAIN_ID) revert WrongChain(originChainId_, SEPOLIA_CHAIN_ID);
        if (destChainId_ != SEPOLIA_CHAIN_ID) revert WrongChain(destChainId_, SEPOLIA_CHAIN_ID);
        if (originContract_ == address(0)) revert ZeroAddress();
        if (window_ == 0 || window_ > type(uint64).max) revert BadWindow();
        // EncounterLedger 自己最多收 5 次。这里先拦住，避免多出来的回调白花钱。
        if (maxEncounters_ == 0 || maxEncounters_ > 5) revert BadLimit();
        SignalGuard.refuse(originContract_);

        OWNER = msg.sender;
        ORIGIN_CHAIN_ID = originChainId_;
        ORIGIN_CONTRACT = originContract_;
        DEST_CHAIN_ID = destChainId_;
        WINDOW = window_;
        MAX_ENCOUNTERS = maxEncounters_;
        remaining = maxEncounters_;
    }

    /// @notice 已经成功请求过的回调次数。
    function requested() public view returns (uint256) {
        return MAX_ENCOUNTERS - remaining;
    }

    /// @notice 绑定 Sepolia 上的 EncounterLedger，并在第一次调用时订阅 SignalSent。
    ///         topic1 和 topic2 都用 REACTIVE_IGNORE，任何人和任何房间都会进来。
    ///         重复调用只更新地址，不会再 subscribe 一次。
    function setRecipient(address recipient_) external onlyOwner {
        if (stopped) revert Stopped();
        if (recipient_ == address(0)) revert ZeroAddress();
        SignalGuard.refuse(recipient_);
        recipient = recipient_;
        emit RecipientSet(recipient_);
        if (!subscribed) _setSubscription(true);
    }

    /// @notice 紧急退订。可以重复调用：第二次如果已经退订，就什么都不做。
    function stop() external onlyOwner {
        if (stopped && !subscribed) return;
        if (!stopped) {
            stopped = true;
            emit EncountersStopped(requested(), true);
        }
        if (subscribed) _setSubscription(false);
    }

    /// @notice 用本合约余额补上欠款。debt > 0 时网络会静默停止投递。
    function coverDebt() external {
        _coverDebt();
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        if (!_accepted(log_)) return;
        uint64 ts = _timestamp(log_.data);
        if (ts == 0) return;

        // indexed address 必须是左填充的 20 字节。高位脏数据直接丢掉，避免截成另一个地址。
        if (log_.topic1 != uint256(uint160(log_.topic1))) return;
        address sender = address(uint160(log_.topic1));
        bytes32 pairId = bytes32(log_.topic2);
        if (sender == address(0) || pairId == bytes32(0)) return;

        lastReactBlock = block.number;
        Meeting memory meeting = _observe(pairId, sender, ts);
        emit SignalNoted(sender, pairId, ts);
        if (!meeting.met) {
            if (meeting.bothPresent) emit WindowMissed(pairId, meeting.earlier, meeting.later, WINDOW);
            return;
        }
        // 编码和系统调用放到单独的函数里，避免 react() 的局部变量把编译栈撑爆。
        _commit(pairId, meeting);
    }

    function _accepted(LogRecord calldata log_) internal view returns (bool) {
        if (log_.topic0 != SIGNAL_TOPIC0) return false;
        if (log_.contractAddress != ORIGIN_CONTRACT) return false;
        if (log_.chainId != ORIGIN_CHAIN_ID) return false;
        if (log_.data.length < 32) return false;
        if (stopped || !subscribed || remaining == 0 || recipient == address(0)) return false;
        return true;
    }

    function _timestamp(bytes calldata data) internal pure returns (uint64) {
        uint256 ts = abi.decode(data, (uint256));
        if (ts == 0 || ts > type(uint64).max) return 0;
        return uint64(ts);
    }

    /// @dev 先记下这个人的时间。两格都有人，并且较晚的时间减去较早的时间 <= WINDOW，才算遇见。
    ///      同一个人再挥一次，只更新自己的时间。记忆留在这里，等 _commit 真的请求回调时再清掉。
    function _observe(bytes32 pairId, address sender, uint64 ts) internal returns (Meeting memory meeting) {
        PairMemory storage room = pairMemory[pairId];
        if (room.first == sender) {
            room.firstAt = ts;
        } else if (room.second == sender) {
            room.secondAt = ts;
        } else if (room.first == address(0)) {
            room.first = sender;
            room.firstAt = ts;
        } else if (room.second == address(0)) {
            room.second = sender;
            room.secondAt = ts;
        } else if (room.firstAt <= room.secondAt) {
            room.first = sender;
            room.firstAt = ts;
        } else {
            room.second = sender;
            room.secondAt = ts;
        }

        if (room.first == address(0) || room.second == address(0) || room.first == room.second) return meeting;
        meeting.bothPresent = true;
        meeting.earlier = room.firstAt < room.secondAt ? room.firstAt : room.secondAt;
        meeting.later = room.firstAt > room.secondAt ? room.firstAt : room.secondAt;
        if (uint256(meeting.later) - uint256(meeting.earlier) > WINDOW) return meeting;

        meeting.met = true;
        if (room.first < room.second) {
            meeting.low = room.first;
            meeting.timeLow = room.firstAt;
            meeting.high = room.second;
            meeting.timeHigh = room.secondAt;
        } else {
            meeting.low = room.second;
            meeting.timeLow = room.secondAt;
            meeting.high = room.first;
            meeting.timeHigh = room.firstAt;
        }
    }

    function _commit(bytes32 pairId, Meeting memory meeting) internal {
        bytes32 key = keccak256(abi.encode(pairId, meeting.low, meeting.timeLow, meeting.high, meeting.timeHigh));
        // 同一对信号被重放时，不要把仅剩的次数再扣掉。
        if (lastEncounterKey != bytes32(0) && key == lastEncounterKey) return;
        if (remaining == 0) return;

        lastEncounterKey = key;
        remaining -= 1;
        bool finished = remaining == 0;
        if (finished) stopped = true;
        _clear(pairId);

        emit EncounterRequested(pairId, recipient);
        if (finished) emit EncountersStopped(requested(), false);
        // 先改状态再调用系统合约。退订参数必须和订阅时逐字相同。
        if (finished) _setSubscription(false);
        _request(pairId, meeting);
    }

    function _clear(bytes32 pairId) internal {
        PairMemory storage room = pairMemory[pairId];
        room.first = address(0);
        room.firstAt = 0;
        room.second = address(0);
        room.secondAt = 0;
    }

    function _request(bytes32 pairId, Meeting memory meeting) internal {
        // 第一个参数必须是 address，并且填 address(0)。Proxy 会改写成本合约地址。
        bytes memory payload = abi.encodeWithSignature(
            "recordEncounter(address,bytes32,address,uint64,address,uint64)",
            address(0),
            pairId,
            meeting.low,
            meeting.timeLow,
            meeting.high,
            meeting.timeHigh
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: DEST_CHAIN_ID,
                recipient: recipient,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }

    function _setSubscription(bool on) internal {
        subscribed = on;
        if (on) {
            SYSTEM.subscribe(
                ORIGIN_CHAIN_ID, ORIGIN_CONTRACT, SIGNAL_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
        } else {
            SYSTEM.unsubscribe(
                ORIGIN_CHAIN_ID, ORIGIN_CONTRACT, SIGNAL_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
        }
    }
}
