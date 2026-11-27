// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { CalendarGuard } from "./CalendarGuard.sol";

/// @title ClarityCalendar — Sepolia 上的恋爱脑清醒日历（源链事件 + 目标链回调同一合约）
/// @notice 链上只记「一团念头」的触碰、放下承诺与彻底放下。日记正文不在这里。
/// @dev    部署顺序：先本合约（Proxy + ETH），再 Lasna ClarityReactive，再 bindReactive。
///         触碰已彻底放下的 thread 会重新打开（released=false）；若仍已承诺则窗口重计。
///         markReleased 必须极省 gas：Proxy 大约只转出 155800。根状态打进一个槽。
contract ClarityCalendar is AbstractPayer {
    /// @notice 给脚本和网页一个固定标记。
    bool public constant CLARITY_DEMO = true;

    /// @dev topic0 订阅用。user 在 topic1，threadId 在 topic2，timestamp 在 data。
    event ThreadTouched(address indexed user, uint256 indexed threadId, uint256 timestamp);
    /// @notice 承诺含义固定为「我愿意好好生活 / I will live well」。不携带日记。
    event LetGoPledged(address indexed user, uint256 indexed threadId, uint256 timestamp);
    event ThreadsMerged(address indexed user, uint256 indexed fromId, uint256 indexed intoId);
    event ThreadReleased(address indexed reactive, address indexed user, uint256 indexed threadId, uint256 timestamp);
    event ReactiveBound(address indexed reactive);

    error NotOwner();
    error ZeroAddress();
    error UnknownThread();
    error SameThread();
    error AlreadyBound();
    error NotBound();
    error CallbackNotAuthorized(address got, address want);

    /// @dev parent==0 表示根。
    struct ThreadMeta {
        uint64 parent;
        bool pledged;
        bool released;
        bool exists;
    }

    /// @dev 根节点紧凑状态，一个槽：
    ///      bit0 exists, bit8 pledged, bit16 released,
    ///      [24,88) lastTouchAt, [88,152) pledgedAt, [152,216) releasedAt
    mapping(address => mapping(uint256 => uint256)) private _rootPack;
    mapping(address => mapping(uint256 => ThreadMeta)) private _meta;
    mapping(address => uint256) public nextThreadId;

    address public owner;
    /// @notice Lasna ClarityReactive。bindReactive 只能成功一次。
    address public reactive;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param proxy_ Sepolia Callback Proxy：0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4
    constructor(IPayable proxy_) payable AbstractPayer(proxy_) {
        if (address(proxy_) == address(0)) revert ZeroAddress();
        CalendarGuard.refuse(address(proxy_));
        owner = msg.sender;
    }

    /// @notice 第 3 步：绑定 Lasna Reactive。填错只能重新部署本合约。
    function bindReactive(address reactive_) external onlyOwner {
        if (reactive != address(0)) revert AlreadyBound();
        if (reactive_ == address(0)) revert ZeroAddress();
        CalendarGuard.refuse(reactive_);
        reactive = reactive_;
        emit ReactiveBound(reactive_);
    }

    function find(address user, uint256 threadId) public view returns (uint256) {
        if (threadId == 0 || !_meta[user][threadId].exists) revert UnknownThread();
        return _find(user, threadId);
    }

    function isPledged(address user, uint256 threadId) external view returns (bool) {
        return _meta[user][find(user, threadId)].pledged;
    }

    function isReleased(address user, uint256 threadId) external view returns (bool) {
        return _meta[user][find(user, threadId)].released;
    }

    function lastTouchAt(address user, uint256 threadId) external view returns (uint64) {
        return uint64(_rootPack[user][find(user, threadId)] >> 24);
    }

    /// @notice 开一团新念头并 touch。对应网页「全新的一件事」。
    function openThread() external returns (uint256 threadId) {
        return _openThread(msg.sender);
    }

    /// @notice 触碰已有一团。若已彻底放下，则重新打开。
    function touch(uint256 threadId) external {
        _touchRoot(msg.sender, find(msg.sender, threadId), true);
    }

    /// @notice 把若干团合成一团并 touch。空数组 = 开新团；一个 id = 只 touch；多个 = 并入最小 id。
    function linkAndTouch(uint256[] calldata threadIds) external returns (uint256 root) {
        uint256 n = threadIds.length;
        if (n == 0) {
            return _openThread(msg.sender);
        }
        root = find(msg.sender, threadIds[0]);
        for (uint256 i = 1; i < n; i++) {
            root = _mergeRoots(msg.sender, root, find(msg.sender, threadIds[i]));
        }
        _touchRoot(msg.sender, root, true);
    }

    /// @notice 合并两团。日子连通分量由网页算好后调用。
    function merge(uint256 a, uint256 b) external returns (uint256 root) {
        if (a == b) revert SameThread();
        root = _mergeRoots(msg.sender, find(msg.sender, a), find(msg.sender, b));
    }

    /// @notice 我愿意彻底放下，继续好好生活。链上事件不带日记正文。
    function pledgeLetGo(uint256 threadId) external {
        uint256 root = find(msg.sender, threadId);
        ThreadMeta storage m = _meta[msg.sender][root];
        uint256 pack = _rootPack[msg.sender][root];
        if (!m.pledged) {
            m.pledged = true;
            pack = _setFlag(pack, 8, true);
            pack = (pack & ~(((uint256(1) << 64) - 1) << 88)) | (uint256(uint64(block.timestamp)) << 88);
        }
        if (m.released) {
            m.released = false;
            pack = _setFlag(pack, 16, false);
            pack = (pack & ~(((uint256(1) << 64) - 1) << 152));
        }
        pack = (pack & ~(((uint256(1) << 64) - 1) << 24)) | (uint256(uint64(block.timestamp)) << 24);
        pack = _setFlag(pack, 0, true);
        _rootPack[msg.sender][root] = pack;
        emit ThreadTouched(msg.sender, root, block.timestamp);
        emit LetGoPledged(msg.sender, root, block.timestamp);
    }

    /// @notice Proxy 回调入口。第一个 address 由网络注入，必须等于已绑定的 Reactive。
    function markReleased(address reactive_, address user_, uint256 threadId_) external onlyServiceProvider {
        address bound = reactive;
        if (bound == address(0)) revert NotBound();
        if (reactive_ != bound) revert CallbackNotAuthorized(reactive_, bound);
        if (user_ == address(0) || threadId_ == 0) return;
        ThreadMeta storage tip = _meta[user_][threadId_];
        if (!tip.exists) return;
        uint256 root = _find(user_, threadId_);
        ThreadMeta storage rm = _meta[user_][root];
        if (!rm.pledged || rm.released) return;
        rm.released = true;
        uint256 pack = _rootPack[user_][root];
        pack = _setFlag(pack, 16, true);
        pack = (pack & ~(((uint256(1) << 64) - 1) << 152)) | (uint256(uint64(block.timestamp)) << 152);
        _rootPack[user_][root] = pack;
        emit ThreadReleased(reactive_, user_, root, block.timestamp);
    }

    function coverDebt() external {
        _coverDebt();
    }

    function _openThread(address user) internal returns (uint256 threadId) {
        threadId = ++nextThreadId[user];
        _meta[user][threadId] = ThreadMeta({parent: 0, pledged: false, released: false, exists: true});
        _touchRoot(user, threadId, false);
    }

    function _find(address user, uint256 threadId) internal view returns (uint256) {
        uint256 id = threadId;
        for (uint256 i = 0; i < 64; i++) {
            ThreadMeta storage m = _meta[user][id];
            if (!m.exists) revert UnknownThread();
            if (m.parent == 0) return id;
            id = uint256(m.parent);
        }
        revert UnknownThread();
    }

    function _findWrite(address user, uint256 threadId) internal returns (uint256) {
        ThreadMeta storage m = _meta[user][threadId];
        if (!m.exists) revert UnknownThread();
        if (m.parent == 0) return threadId;
        uint256 root = _findWrite(user, uint256(m.parent));
        m.parent = uint64(root);
        return root;
    }

    function _mergeRoots(address user, uint256 a, uint256 b) internal returns (uint256 root) {
        uint256 ra = _findWrite(user, a);
        uint256 rb = _findWrite(user, b);
        if (ra == rb) return ra;
        if (rb < ra) (ra, rb) = (rb, ra);
        ThreadMeta storage into = _meta[user][ra];
        ThreadMeta storage from = _meta[user][rb];
        from.parent = uint64(ra);
        into.pledged = into.pledged || from.pledged;
        into.released = into.released && from.released;
        uint256 packA = _rootPack[user][ra];
        uint256 packB = _rootPack[user][rb];
        uint64 touchA = uint64(packA >> 24);
        uint64 touchB = uint64(packB >> 24);
        uint64 last = touchA > touchB ? touchA : touchB;
        packA = _setFlag(packA, 0, true);
        packA = _setFlag(packA, 8, into.pledged);
        packA = _setFlag(packA, 16, into.released);
        packA = (packA & ~(((uint256(1) << 64) - 1) << 24)) | (uint256(last) << 24);
        _rootPack[user][ra] = packA;
        emit ThreadsMerged(user, rb, ra);
        return ra;
    }

    function _touchRoot(address user, uint256 root, bool mayReopen) internal {
        ThreadMeta storage m = _meta[user][root];
        uint256 pack = _rootPack[user][root];
        if (mayReopen && m.released) {
            m.released = false;
            pack = _setFlag(pack, 16, false);
            pack = (pack & ~(((uint256(1) << 64) - 1) << 152));
        }
        pack = _setFlag(pack, 0, true);
        pack = _setFlag(pack, 8, m.pledged);
        pack = (pack & ~(((uint256(1) << 64) - 1) << 24)) | (uint256(uint64(block.timestamp)) << 24);
        _rootPack[user][root] = pack;
        emit ThreadTouched(user, root, block.timestamp);
    }

    function _setFlag(uint256 pack, uint256 bit, bool on) internal pure returns (uint256) {
        if (on) return pack | (uint256(1) << bit);
        return pack & ~(uint256(1) << bit);
    }
}
