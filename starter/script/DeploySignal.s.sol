// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { SignalBoard } from "../src/signal/SignalBoard.sol";
import { SignalReactive } from "../src/signal/SignalReactive.sol";
import { EncounterLedger } from "../src/signal/EncounterLedger.sol";
import { SignalGuard } from "../src/signal/SignalGuard.sol";

// Sepolia Callback Proxy. 源链和目标链都是 Ethereum Sepolia。
address constant SEPOLIA_CALLBACK_PROXY = 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4;

uint256 constant SIGNAL_TOPIC0 = uint256(keccak256("SignalSent(address,bytes32,uint256)"));

/// 部署脚本共用的拒绝名单。官方示例、D5，以及 .env 里已经记下的其他实验地址，都不能拿来当这条链路的合约。
abstract contract SignalScript is Script {
    function _refuseKnown(address a) internal view {
        SignalGuard.refuse(a);
        _differ(a, "SPREAD_AMM_ADDR");
        _differ(a, "SPREAD_REACTIVE_ADDR");
        _differ(a, "SPREAD_LEDGER_ADDR");
        _differ(a, "ORIGIN_ADDR");
        _differ(a, "REACTIVE_ADDR");
        _differ(a, "CALLBACK_ADDR");
        _differ(a, "D5_REACTIVE_ADDR");
        _differ(a, "D5_CALLBACK_ADDR");
        _differ(a, "D5_FAILED_REACTIVE_ADDR");
        _differ(a, "D5_FAILED_CALLBACK_ADDR");
    }

    function _differ(address a, string memory key) internal view {
        address other = vm.envOr(key, address(0));
        require(other == address(0) || other != a, "address belongs to another lab");
    }
}

/// 不广播。只从环境变量推出地址，方便脚本确认两个钱包不是同一个人。私钥不会被打印。
contract ShowSenders is Script {
    function run() external view {
        address first = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("sender1", first);
        if (vm.envOr("SIGNAL_HAS_KEY2", uint256(0)) == 1) {
            address second = vm.addr(vm.envUint("PRIVATE_KEY_2"));
            console.log("sender2", second);
        } else {
            console.log("sender2", address(0));
        }
    }
}

/// 第 1 步：在 Ethereum Sepolia 部署信号板。这一步还不产生相遇。
///   forge script script/DeploySignal.s.sol:DeployBoard --rpc-url %SEPOLIA% --broadcast --chain 11155111 --evm-version cancun
contract DeployBoard is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        SignalBoard board = new SignalBoard();
        vm.stopBroadcast();

        console.log("SIGNAL_BOARD_ADDR=", address(board));
        console.log("romantic demo", board.ROMANTIC_DEMO());
    }
}

/// 第 2 步：在 Lasna 部署并转入 lREACT。这一步还不订阅，避免 Ledger 没就绪时就开始扣费。
///   forge script script/DeploySignal.s.sol:DeployReactive --rpc-url %LASNA% --broadcast --chain 5318007 --evm-version cancun
contract DeployReactive is SignalScript {
    function run() external {
        uint256 originChain = vm.envOr("ORIGIN_CHAIN_ID", uint256(11155111));
        address origin = vm.envAddress("SIGNAL_BOARD_ADDR");
        uint256 destChain = vm.envOr("DEST_CHAIN_ID", uint256(11155111));
        uint256 window = vm.envOr("SIGNAL_WINDOW", uint256(3600));
        uint256 maxEncounters = vm.envOr("SIGNAL_MAX_ENCOUNTERS", uint256(3));
        uint256 fund = vm.envOr("SIGNAL_REACTIVE_FUND", uint256(0.10 ether));
        _refuseKnown(origin);
        require(origin != address(0), "SIGNAL_BOARD_ADDR missing");
        require(originChain == 11155111 && destChain == 11155111, "signal path is Sepolia only");
        require(fund > 0, "reactive needs lREACT");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        SignalReactive reactive = new SignalReactive{ value: fund }(originChain, origin, destChain, window, maxEncounters);
        vm.stopBroadcast();

        console.log("SIGNAL_REACTIVE_ADDR=", address(reactive));
        console.log("funded lREACT wei", fund);
        console.log("window seconds", window);
        console.log("max encounters", maxEncounters);
        console.log("subscribed", reactive.subscribed());
        console.log("topic0", reactive.SIGNAL_TOPIC0());
    }
}

/// 第 3 步：在 Sepolia 部署账本。构造参数是本链 Proxy 和第 2 步的地址，并转入付回调 gas 的 ETH。
///   forge script script/DeploySignal.s.sol:DeployLedger --rpc-url %SEPOLIA% --broadcast --chain 11155111 --evm-version cancun
contract DeployLedger is SignalScript {
    function run() external {
        address proxy = vm.envAddress("CALLBACK_PROXY");
        address reactive = vm.envAddress("SIGNAL_REACTIVE_ADDR");
        uint256 fund = vm.envOr("SIGNAL_LEDGER_FUND", uint256(0.002 ether));
        _refuseKnown(reactive);
        require(proxy == SEPOLIA_CALLBACK_PROXY, "CALLBACK_PROXY must be the Sepolia Omni proxy");
        require(fund > 0, "ledger needs ETH for callback gas");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        EncounterLedger ledger = new EncounterLedger{ value: fund }(IPayable(payable(proxy)), reactive);
        vm.stopBroadcast();

        console.log("SIGNAL_LEDGER_ADDR=", address(ledger));
        console.log("funded ETH wei", fund);
    }
}

/// 第 4 步：回到 Lasna，把账本地址交给 SignalReactive。这一步才订阅 SignalSent。
///   forge script script/DeploySignal.s.sol:SetRecipient --rpc-url %LASNA% --broadcast --chain 5318007 --evm-version cancun
contract SetRecipient is SignalScript {
    function run() external {
        address reactiveAddr = vm.envAddress("SIGNAL_REACTIVE_ADDR");
        address ledgerAddr = vm.envAddress("SIGNAL_LEDGER_ADDR");
        address boardAddr = vm.envAddress("SIGNAL_BOARD_ADDR");
        _refuseKnown(reactiveAddr);
        _refuseKnown(ledgerAddr);
        _refuseKnown(boardAddr);

        SignalReactive reactive = SignalReactive(payable(reactiveAddr));
        require(reactive.SIGNAL_TOPIC0() == SIGNAL_TOPIC0, "not a signal reactive");
        require(reactive.ORIGIN_CONTRACT() == boardAddr, "reactive is not watching this board");
        require(reactive.MAX_ENCOUNTERS() > 0 && reactive.MAX_ENCOUNTERS() <= 5, "not a signal reactive");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        reactive.setRecipient(ledgerAddr);
        vm.stopBroadcast();

        console.log("recipient", reactive.recipient());
        console.log("subscribed", reactive.subscribed());
        console.log("remaining", reactive.remaining());
    }
}

/// 第 5 步：主钱包发出第一下信号。这一下单独不会相遇。
///   forge script script/DeploySignal.s.sol:WaveA --rpc-url %SEPOLIA% --broadcast --chain 11155111 --evm-version cancun
contract WaveA is SignalScript {
    function run() external {
        _wave(vm.envUint("PRIVATE_KEY"));
    }

    function _wave(uint256 key) internal {
        address boardAddr = vm.envAddress("SIGNAL_BOARD_ADDR");
        bytes32 pairId = vm.envBytes32("SIGNAL_PAIR_ID");
        _refuseKnown(boardAddr);
        require(pairId != bytes32(0), "SIGNAL_PAIR_ID is empty");
        SignalBoard board = SignalBoard(boardAddr);
        require(board.ROMANTIC_DEMO(), "not the signal board");

        vm.startBroadcast(key);
        board.sendSignal(pairId);
        vm.stopBroadcast();

        console.log("sender", vm.addr(key));
        console.log("pair");
        console.logBytes32(pairId);
    }
}

/// 第 6 步：另一个地址发出第二下信号。这一笔才是作业链路的源链交易。
///         私钥来自环境变量 PRIVATE_KEY_2，不会打印。同一个人挥两次不算相遇。
///   forge script script/DeploySignal.s.sol:WaveB --rpc-url %SEPOLIA% --broadcast --chain 11155111 --evm-version cancun
contract WaveB is SignalScript {
    function run() external {
        uint256 key1 = vm.envUint("PRIVATE_KEY");
        uint256 key2 = vm.envUint("PRIVATE_KEY_2");
        address first = vm.addr(key1);
        address second = vm.addr(key2);
        require(second != address(0) && second != first, "wave B needs a different address");

        address boardAddr = vm.envAddress("SIGNAL_BOARD_ADDR");
        bytes32 pairId = vm.envBytes32("SIGNAL_PAIR_ID");
        _refuseKnown(boardAddr);
        require(pairId != bytes32(0), "SIGNAL_PAIR_ID is empty");
        SignalBoard board = SignalBoard(boardAddr);
        require(board.ROMANTIC_DEMO(), "not the signal board");

        vm.startBroadcast(key2);
        board.sendSignal(pairId);
        vm.stopBroadcast();

        console.log("sender", second);
        console.log("pair");
        console.logBytes32(pairId);
        console.log("source tx for the homework path is this second signal");
    }
}

/// 紧急退订。相遇次数用完时合约会自己退订。只有 subscribed 仍为 true 时才需要跑这一步。
///   forge script script/DeploySignal.s.sol:StopSignal --rpc-url %LASNA% --broadcast --chain 5318007 --evm-version cancun
contract StopSignal is SignalScript {
    function run() external {
        address reactiveAddr = vm.envAddress("SIGNAL_REACTIVE_ADDR");
        _refuseKnown(reactiveAddr);
        SignalReactive reactive = SignalReactive(payable(reactiveAddr));
        require(reactive.SIGNAL_TOPIC0() == SIGNAL_TOPIC0, "not a signal reactive");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        reactive.stop();
        vm.stopBroadcast();

        console.log("subscribed", reactive.subscribed());
        console.log("stopped", reactive.stopped());
        console.log("remaining", reactive.remaining());
    }
}
