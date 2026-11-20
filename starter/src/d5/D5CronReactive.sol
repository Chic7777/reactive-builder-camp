// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title D5CronReactive — 11/20 定时任务的 Lasna 侧合约
/// @notice 订阅 Lasna 上的 Cron100（约每 100 个区块 / 约 2 分钟一次）。
///         每次 tick 向 Ethereum Sepolia 请求一次回调。执行满 MAX_EXECUTIONS 次后，
///         在同一笔 react() 里退订，避免后面的 tick 继续扣 lREACT。
/// @dev    写法对齐官方 Omni micro-demo `Cron.sol`（reactive-smart-contract-demos 的 omni 分支）：
///         SYSTEM = 0x8888…8888，react() 使用 onlySystem，回调走 requestCallbackV_1_0。
///         Cron 事件本身来自旧系统地址 0x…fffFfF，这个地址只出现在订阅条件里。
///         2026-11-20 在 Lasna 上核对过：Cron100 的 number 是 indexed，在 topic1，data 为空。
///         官方文档仍写「number 在 data 里」。两种布局都能解码，以 topic1 为准。
contract D5CronReactive is AbstractReactive {
    error NotOwner();
    error ZeroAddress();
    error ZeroLimit();
    error WrongChain(uint256 got, uint256 want);
    error Stopped();

    /// @notice 部署者。只有部署者能绑定回调地址和紧急退订。
    address public immutable OWNER;
    /// @notice 目标链。本实验固定为 Ethereum Sepolia 11155111。
    uint256 public immutable DEST_CHAIN_ID;
    /// @notice 最多请求多少次 Sepolia 回调。构造时定死，没有加次数的函数。
    uint256 public immutable MAX_EXECUTIONS;

    /// @notice Lasna chainId。Cron 事件发在这条链上。
    uint256 public constant LASNA_CHAIN_ID = 5318007;
    /// @notice 只用于 Cron 订阅的合约地址，不是现在的系统合约。
    address public constant LEGACY_CRON = 0x0000000000000000000000000000000000fffFfF;
    /// @notice keccak256("Cron100(uint256)")。2026-11-20 用 cast keccak 对过。
    uint256 public constant CRON100_TOPIC0 = 0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;
    /// @notice 中继把交易 gas 设成这个数。Proxy 还要留下 _extraGas 150000 和 _maxChargeGas 50000，
    ///         实际转给 onTick 的大约是 156000。三次冷 SSTORE 不够，一次打包写入够。不要再往上加。
    uint64 public constant CALLBACK_GAS_LIMIT = 400_000;

    /// @notice Sepolia 上的 D5CronCallback。setRecipient 之前是 0，这段时间不订阅。
    address public recipient;
    /// @notice 还允许请求几次回调。到 0 就退订。
    uint256 public remaining;
    /// @notice 本地记账：节点里的订阅读不回来，退订参数必须和订阅时逐字相同。
    bool public subscribed;
    /// @notice 满额或主人调用 stop() 之后为 true。之后 setRecipient 也不能再订阅。
    bool public stopped;

    /// @notice 最近一次送到 react() 的 Cron 区块号。晚到的 tick 仍会更新它，但不一定请求回调。
    uint256 public lastCronNumber;
    /// @notice 最近一次 react() 所在的 Lasna 区块。
    uint256 public lastReactBlock;

    event RecipientSet(address indexed recipient);
    event CronSeen(uint256 indexed cronNumber, uint256 lasnaBlock);
    event TickHandled(uint256 indexed tickIndex, uint256 cronNumber, address indexed recipient);
    /// @param byOwner true 表示主人调用了 stop()；false 表示次数用完后自动退订。
    event CronStopped(uint256 executed, bool byOwner);

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert NotOwner();
        _;
    }

    /// @param destChainId_ 目标链 chainId。本实验传 11155111。
    /// @param maxExecutions_ 最多回调几次。本实验传 2。传 0 会在部署时失败，避免无限订阅。
    constructor(uint256 destChainId_, uint256 maxExecutions_) payable {
        if (block.chainid != LASNA_CHAIN_ID) revert WrongChain(block.chainid, LASNA_CHAIN_ID);
        if (maxExecutions_ == 0) revert ZeroLimit();
        OWNER = msg.sender;
        DEST_CHAIN_ID = destChainId_;
        MAX_EXECUTIONS = maxExecutions_;
        remaining = maxExecutions_;
        // 故意不在构造函数里订阅。官方 Cron.sol 一部署就开始每个 tick 扣费；
        // 学生还要再部署 Sepolia 回调合约，这段时间会白烧 lREACT，而且还可能把 2 次额度用掉。
    }

    /// @notice 已经成功请求过的回调次数。
    function executed() public view returns (uint256) {
        return MAX_EXECUTIONS - remaining;
    }

    /// @notice 绑定 Sepolia 回调合约，并在第一次调用时订阅 Cron100。
    ///         重复调用只更新地址，不会再 subscribe 一次（重复订阅会多扣一份）。
    function setRecipient(address recipient_) external onlyOwner {
        if (stopped) revert Stopped();
        if (recipient_ == address(0)) revert ZeroAddress();
        recipient = recipient_;
        emit RecipientSet(recipient_);
        if (!subscribed) _subscribe();
    }

    /// @notice 紧急退订。可以重复调用：第二次什么都不做。
    ///         次数用完时 react() 会自己退订，正常跑完不必再调这个函数。
    function stop() external onlyOwner {
        if (stopped && !subscribed) return;
        if (!stopped) {
            stopped = true;
            emit CronStopped(executed(), true);
        }
        if (subscribed) _unsubscribe();
    }

    /// @notice 用本合约余额补上欠款。debt > 0 时网络会静默停止投递。
    function coverDebt() external {
        _coverDebt();
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        // 不匹配就 return。revert 也会被收费。
        if (log_.topic0 != CRON100_TOPIC0) return;
        if (log_.contractAddress != LEGACY_CRON) return;
        if (log_.chainId != LASNA_CHAIN_ID) return;

        uint256 cronNumber = _cronNumber(log_);
        lastCronNumber = cronNumber;
        lastReactBlock = block.number;
        emit CronSeen(cronNumber, block.number);

        // 已停止、还没绑定回调、或额度用完：记下看到了这次 tick，但不请求回调。
        if (stopped || !subscribed || remaining == 0 || recipient == address(0)) return;

        remaining -= 1;
        uint256 tickIndex = executed();
        bool finished = remaining == 0;
        if (finished) stopped = true;

        // 第一个参数必须是 address，并且填 address(0)。Proxy 会改写成本合约地址。
        // 先改状态、先记事件，再调用系统合约，避免退订/请求回调重入时次数被算第二次。
        bytes memory payload = abi.encodeWithSignature(
            "onTick(address,uint256,uint256)", address(0), cronNumber, tickIndex
        );
        emit TickHandled(tickIndex, cronNumber, recipient);
        if (finished) emit CronStopped(tickIndex, false);
        if (finished) _unsubscribe();
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: DEST_CHAIN_ID,
                recipient: recipient,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }

    /// @dev 订阅和退订的六个参数必须完全一致，否则 unsubscribe 静默失败，tick 会继续扣费。
    function _subscribe() internal {
        subscribed = true;
        SYSTEM.subscribe(
            LASNA_CHAIN_ID, LEGACY_CRON, CRON100_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    function _unsubscribe() internal {
        subscribed = false;
        SYSTEM.unsubscribe(
            LASNA_CHAIN_ID, LEGACY_CRON, CRON100_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    /// @dev 线上 Cron100(uint256 indexed number)：number 在 topic1，data 为 0x。
    ///      若以后改成不 indexed，number 会在 data 里，topic1 为 0。两种都认。
    function _cronNumber(LogRecord calldata log_) internal pure returns (uint256) {
        if (log_.topic1 != 0) return log_.topic1;
        if (log_.data.length >= 32) return abi.decode(log_.data, (uint256));
        return log_.blockNumber;
    }
}
