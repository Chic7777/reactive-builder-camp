// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";
import { SpreadGuard } from "./SpreadGuard.sol";

/// @title SpreadReactive — Lasna 上比较两个教学池的价差
/// @notice 订阅 Sepolia 上 SimDualAmm 的 ReservesUpdated。react() 记下这一池的储备；
///         两个池都有报价之后计算价差。低于阈值就 return，不 revert（revert 一样扣费）。
///         达到或超过阈值才请求 Sepolia 回调，把这次机会记下来。
/// @dev    这是 Phase A：检测并记录。不做同链原子套利，也不做跨链套利。
///         运行时没有 AI。SYSTEM 与 D5 相同，是 0x8888…8888。
///         构造时不订阅。订阅发生在 setRecipient，避免 Ledger 还没部署时就对着空地址烧 lREACT。
contract SpreadReactive is AbstractReactive {
    error NotOwner();
    error ZeroAddress();
    error ZeroLimit();
    error WrongChain(uint256 got, uint256 want);
    error Stopped();

    event RecipientSet(address indexed recipient);
    event QuoteStored(uint8 indexed poolId, uint112 reserve0, uint112 reserve1);
    /// @notice 两个池都有报价，但价差低于阈值。没有请求回调。
    event SpreadSkipped(uint256 spreadBps, uint256 thresholdBps);
    event OpportunityRequested(uint256 indexed spreadBps, uint8 indexed cheapPoolId, address recipient);
    /// @param byOwner true 表示主人调用了 stop()；false 表示记录次数用完后自动退订。
    event RecordsStopped(uint256 requested, bool byOwner);

    struct Quote {
        uint112 reserve0;
        uint112 reserve1;
        bool seen;
    }

    address public immutable OWNER;
    uint256 public immutable ORIGIN_CHAIN_ID;
    address public immutable ORIGIN_CONTRACT;
    uint256 public immutable DEST_CHAIN_ID;
    /// @notice 价差阈值，单位是 bps。100 = 1%。差价小于这个数就跳过。
    uint256 public immutable THRESHOLD_BPS;
    /// @notice 最多请求几次回调。用完就退订，避免后面的事件继续扣 lREACT。
    uint256 public immutable MAX_RECORDS;

    uint256 public constant LASNA_CHAIN_ID = 5318007;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    /// @notice keccak256("ReservesUpdated(uint8,uint112,uint112)")。poolId 是 indexed，在 topic1。
    uint256 public constant RESERVES_TOPIC0 = uint256(keccak256("ReservesUpdated(uint8,uint112,uint112)"));
    /// @notice 中继按这个 gas 发 Sepolia 交易。Proxy 留下 _extraGas 150000 和 _maxChargeGas 50000，
    ///         实际转给 recordOpportunity 的大约是 155800。Ledger 必须在这个额度里写完。
    uint64 public constant CALLBACK_GAS_LIMIT = 400_000;

    address public recipient;
    uint256 public remaining;
    bool public subscribed;
    bool public stopped;

    Quote public quote1;
    Quote public quote2;
    /// @notice 最近一次两个池都能比的价差。只有一个池有报价时不改它。
    uint256 public lastSpreadBps;
    uint256 public lastReactBlock;

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert NotOwner();
        _;
    }

    /// @param originChainId_ 源链。Phase A 固定 Ethereum Sepolia 11155111。
    /// @param originContract_ SimDualAmm 的地址。不能是官方示例或 D5 合约。
    /// @param destChainId_    目标链。Phase A 同样是 Sepolia，不在这里做跨链。
    /// @param thresholdBps_   阈值 bps。脚本默认 100。
    /// @param maxRecords_     最多记几次。传 0 会在部署时失败。脚本默认 5。
    constructor(
        uint256 originChainId_,
        address originContract_,
        uint256 destChainId_,
        uint256 thresholdBps_,
        uint256 maxRecords_
    ) payable {
        if (block.chainid != LASNA_CHAIN_ID) revert WrongChain(block.chainid, LASNA_CHAIN_ID);
        if (originChainId_ != SEPOLIA_CHAIN_ID) revert WrongChain(originChainId_, SEPOLIA_CHAIN_ID);
        if (destChainId_ != SEPOLIA_CHAIN_ID) revert WrongChain(destChainId_, SEPOLIA_CHAIN_ID);
        if (originContract_ == address(0)) revert ZeroAddress();
        if (maxRecords_ == 0) revert ZeroLimit();
        SpreadGuard.refuse(originContract_);

        OWNER = msg.sender;
        ORIGIN_CHAIN_ID = originChainId_;
        ORIGIN_CONTRACT = originContract_;
        DEST_CHAIN_ID = destChainId_;
        THRESHOLD_BPS = thresholdBps_;
        MAX_RECORDS = maxRecords_;
        remaining = maxRecords_;
    }

    /// @notice 已经成功请求过的回调次数。
    function requested() public view returns (uint256) {
        return MAX_RECORDS - remaining;
    }

    /// @notice 用当前两池报价预算价差。还缺一池时 ready 为 false。
    function previewSpreadBps() external view returns (uint256 spreadBps, bool ready) {
        if (!quote1.seen || !quote2.seen) return (0, false);
        return (spreadBpsOf(quote1.reserve0, quote1.reserve1, quote2.reserve0, quote2.reserve1), true);
    }

    /// @notice 绑定 Sepolia 上的 OpportunityLedger，并在第一次调用时订阅 ReservesUpdated。
    ///         topic1 用 REACTIVE_IGNORE，这样 pool 1 和 pool 2 的事件都进同一个订阅。
    ///         重复调用只更新地址，不会再 subscribe 一次。
    function setRecipient(address recipient_) external onlyOwner {
        if (stopped) revert Stopped();
        if (recipient_ == address(0)) revert ZeroAddress();
        SpreadGuard.refuse(recipient_);
        recipient = recipient_;
        emit RecipientSet(recipient_);
        if (!subscribed) _setSubscription(true);
    }

    /// @notice 紧急退订。可以重复调用：第二次如果已经退订，就什么都不做。
    function stop() external onlyOwner {
        if (stopped && !subscribed) return;
        if (!stopped) {
            stopped = true;
            emit RecordsStopped(requested(), true);
        }
        if (subscribed) _setSubscription(false);
    }

    /// @notice 用本合约余额补上欠款。debt > 0 时网络会静默停止投递。
    function coverDebt() external {
        _coverDebt();
    }

    /// @dev 价格定义为 reserve1 / reserve0（每个 token0 值多少 token1）。
    ///      spreadBps = abs(p1 - p2) * 10000 / min(p1, p2)。
    ///      交叉相乘：a = r1Of1 * r0Of2，b = r1Of2 * r0Of1，和直接除再比是同一个方向，
    ///      但不会因为两次除法的余数把阈值边界算偏。
    function spreadBpsOf(uint112 r0Of1, uint112 r1Of1, uint112 r0Of2, uint112 r1Of2) public pure returns (uint256) {
        if (r0Of1 == 0 || r1Of1 == 0 || r0Of2 == 0 || r1Of2 == 0) return 0;
        uint256 a = uint256(r1Of1) * uint256(r0Of2);
        uint256 b = uint256(r1Of2) * uint256(r0Of1);
        uint256 lo = a < b ? a : b;
        if (lo == 0) return 0;
        uint256 diff = a > b ? a - b : b - a;
        return diff * 10_000 / lo;
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        if (log_.topic0 != RESERVES_TOPIC0) return;
        if (log_.contractAddress != ORIGIN_CONTRACT) return;
        if (log_.chainId != ORIGIN_CHAIN_ID) return;
        if (log_.data.length < 64) return;

        // indexed uint8 在 topic1 里是左填充的 32 字节。只认 1 和 2，避免把 257 截成池 1。
        if (log_.topic1 != 1 && log_.topic1 != 2) return;
        uint8 poolId = uint8(log_.topic1);
        (uint112 reserve0, uint112 reserve1) = abi.decode(log_.data, (uint112, uint112));
        if (reserve0 == 0 || reserve1 == 0) return;

        // 储备没变就直接回去。同一笔教学参数重放不会把 5 次额度用掉。
        // 更完整的去重（价差相同但储备来回变）留到 D10。
        Quote memory prev = poolId == 1 ? quote1 : quote2;
        if (prev.seen && prev.reserve0 == reserve0 && prev.reserve1 == reserve1) return;

        if (poolId == 1) quote1 = Quote(reserve0, reserve1, true);
        else quote2 = Quote(reserve0, reserve1, true);

        lastReactBlock = block.number;
        emit QuoteStored(poolId, reserve0, reserve1);

        // 只更新了一个池：条件还不成立，不回调，也不扣次数。
        if (!quote1.seen || !quote2.seen) return;

        uint256 spread = spreadBpsOf(quote1.reserve0, quote1.reserve1, quote2.reserve0, quote2.reserve1);
        lastSpreadBps = spread;
        if (spread < THRESHOLD_BPS) {
            emit SpreadSkipped(spread, THRESHOLD_BPS);
            return;
        }
        if (stopped || !subscribed || remaining == 0 || recipient == address(0)) return;

        remaining -= 1;
        bool finished = remaining == 0;
        if (finished) stopped = true;

        uint8 cheapPoolId = _cheapPoolId();
        // 第一个参数必须是 address，并且填 address(0)。Proxy 会改写成本合约地址。
        // 编码放在单独的函数里，避免 react() 的局部变量把编译栈撑爆。
        bytes memory payload = _opportunityPayload(spread, log_.blockNumber, cheapPoolId);
        emit OpportunityRequested(spread, cheapPoolId, recipient);
        if (finished) emit RecordsStopped(requested(), false);
        // 先改状态再调用系统合约。退订参数必须和订阅时逐字相同。
        if (finished) _setSubscription(false);
        _request(payload);
    }

    function _cheapPoolId() internal view returns (uint8) {
        uint256 a = uint256(quote1.reserve1) * uint256(quote2.reserve0);
        uint256 b = uint256(quote2.reserve1) * uint256(quote1.reserve0);
        return a <= b ? 1 : 2;
    }

    function _price(uint112 reserve0, uint112 reserve1) internal pure returns (uint256) {
        return uint256(reserve1) * 1e18 / uint256(reserve0);
    }

    function _opportunityPayload(uint256 spread, uint256 srcBlock, uint8 cheapPoolId) internal view returns (bytes memory) {
        return abi.encodeWithSignature(
            "recordOpportunity(address,uint256,uint256,uint256,uint256,uint8)",
            address(0),
            spread,
            _price(quote1.reserve0, quote1.reserve1),
            _price(quote2.reserve0, quote2.reserve1),
            srcBlock,
            cheapPoolId
        );
    }

    function _request(bytes memory payload) internal {
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
                ORIGIN_CHAIN_ID, ORIGIN_CONTRACT, RESERVES_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
        } else {
            SYSTEM.unsubscribe(
                ORIGIN_CHAIN_ID, ORIGIN_CONTRACT, RESERVES_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
        }
    }
}
