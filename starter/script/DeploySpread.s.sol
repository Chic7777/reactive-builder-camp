// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { SimDualAmm } from "../src/spread/SimDualAmm.sol";
import { SpreadReactive } from "../src/spread/SpreadReactive.sol";
import { OpportunityLedger } from "../src/spread/OpportunityLedger.sol";
import { SpreadGuard } from "../src/spread/SpreadGuard.sol";

// Sepolia Callback Proxy. Phase A source and destination are both Ethereum Sepolia.
address constant SEPOLIA_CALLBACK_PROXY = 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4;

/// 第 1 步：在 Ethereum Sepolia 部署两个教学模拟池。这一步还不产生价差。
///   forge script script/DeploySpread.s.sol:DeployAmm --rpc-url %SEPOLIA% --broadcast --chain 11155111 --evm-version cancun
contract DeployAmm is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        SimDualAmm amm = new SimDualAmm();
        vm.stopBroadcast();

        console.log("SPREAD_AMM_ADDR=", address(amm));
        console.log("teaching sim", amm.TEACHING_SIM());
    }
}

/// 第 2 步：在 Lasna 部署并转入 lREACT。这一步还不订阅，避免 Ledger 没就绪时就开始扣费。
///   forge script script/DeploySpread.s.sol:DeployReactive --rpc-url %LASNA% --broadcast --chain 5318007 --evm-version cancun
contract DeployReactive is Script {
    function run() external {
        uint256 originChain = vm.envOr("ORIGIN_CHAIN_ID", uint256(11155111));
        address origin = vm.envAddress("SPREAD_AMM_ADDR");
        uint256 destChain = vm.envOr("DEST_CHAIN_ID", uint256(11155111));
        uint256 threshold = vm.envOr("SPREAD_THRESHOLD_BPS", uint256(100));
        uint256 maxRecords = vm.envOr("SPREAD_MAX_RECORDS", uint256(5));
        uint256 fund = vm.envOr("SPREAD_REACTIVE_FUND", uint256(0.10 ether));
        SpreadGuard.refuse(origin);
        require(origin != address(0), "SPREAD_AMM_ADDR missing");
        require(fund > 0, "reactive needs lREACT");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        SpreadReactive reactive =
            new SpreadReactive{ value: fund }(originChain, origin, destChain, threshold, maxRecords);
        vm.stopBroadcast();

        console.log("SPREAD_REACTIVE_ADDR=", address(reactive));
        console.log("funded lREACT wei", fund);
        console.log("threshold bps", threshold);
        console.log("max records", maxRecords);
        console.log("subscribed", reactive.subscribed());
        console.log("topic0", reactive.RESERVES_TOPIC0());
    }
}

/// 第 3 步：在 Sepolia 部署账本。构造参数是本链 Proxy 和第 2 步的地址，并转入付回调 gas 的 ETH。
///   forge script script/DeploySpread.s.sol:DeployLedger --rpc-url %SEPOLIA% --broadcast --chain 11155111 --evm-version cancun
contract DeployLedger is Script {
    function run() external {
        address proxy = vm.envAddress("CALLBACK_PROXY");
        address reactive = vm.envAddress("SPREAD_REACTIVE_ADDR");
        uint256 fund = vm.envOr("SPREAD_LEDGER_FUND", uint256(0.002 ether));
        SpreadGuard.refuse(reactive);
        require(proxy == SEPOLIA_CALLBACK_PROXY, "CALLBACK_PROXY must be the Sepolia Omni proxy");
        require(fund > 0, "ledger needs ETH for callback gas");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        OpportunityLedger ledger = new OpportunityLedger{ value: fund }(IPayable(payable(proxy)), reactive);
        vm.stopBroadcast();

        console.log("SPREAD_LEDGER_ADDR=", address(ledger));
        console.log("funded ETH wei", fund);
    }
}

/// 第 4 步：回到 Lasna，把账本地址交给 SpreadReactive。这一步才订阅 ReservesUpdated。
///   forge script script/DeploySpread.s.sol:SetRecipient --rpc-url %LASNA% --broadcast --chain 5318007 --evm-version cancun
contract SetRecipient is Script {
    function run() external {
        address reactiveAddr = vm.envAddress("SPREAD_REACTIVE_ADDR");
        address ledgerAddr = vm.envAddress("SPREAD_LEDGER_ADDR");
        address ammAddr = vm.envAddress("SPREAD_AMM_ADDR");
        SpreadGuard.refuse(reactiveAddr);
        SpreadGuard.refuse(ledgerAddr);
        SpreadGuard.refuse(ammAddr);

        SpreadReactive reactive = SpreadReactive(payable(reactiveAddr));
        // CampReactive 和 D5CronReactive 也有 setRecipient(address)。先对上本合约的常量，再发交易。
        require(reactive.MAX_RECORDS() > 0, "not a spread reactive");
        require(
            reactive.RESERVES_TOPIC0() == uint256(keccak256("ReservesUpdated(uint8,uint112,uint112)")),
            "not a spread reactive"
        );
        require(reactive.ORIGIN_CONTRACT() == ammAddr, "reactive is not watching this amm");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        reactive.setRecipient(ledgerAddr);
        vm.stopBroadcast();

        console.log("recipient", reactive.recipient());
        console.log("subscribed", reactive.subscribed());
        console.log("remaining", reactive.remaining());
    }
}

/// 第 5 步：在 Sepolia 上改两个池的储备。第二笔 nudge 才同时具备「两个报价 + 价差达到阈值」。
///         默认 10000/10000 对 10000/10100，价差正好 100 bps。阈值如果改大了，这里也要改。
///   forge script script/DeploySpread.s.sol:NudgeSpread --rpc-url %SEPOLIA% --broadcast --chain 11155111 --evm-version cancun
contract NudgeSpread is Script {
    function run() external {
        address ammAddr = vm.envAddress("SPREAD_AMM_ADDR");
        SpreadGuard.refuse(ammAddr);
        SimDualAmm amm = SimDualAmm(ammAddr);
        require(amm.TEACHING_SIM(), "not the teaching-sim amm");
        require(amm.OWNER() == vm.addr(vm.envUint("PRIVATE_KEY")), "sender is not the amm owner");

        uint112 r0a = _u112("SPREAD_POOL1_R0", 10_000);
        uint112 r1a = _u112("SPREAD_POOL1_R1", 10_000);
        uint112 r0b = _u112("SPREAD_POOL2_R0", 10_000);
        uint112 r1b = _u112("SPREAD_POOL2_R1", 10_100);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        amm.nudgeReserves(1, r0a, r1a);
        amm.nudgeReserves(2, r0b, r1b);
        vm.stopBroadcast();

        console.log("nudged pool 1", uint256(r0a), uint256(r1a));
        console.log("nudged pool 2", uint256(r0b), uint256(r1b));
        console.log("source tx for the homework path is the second nudge, after both pools have a quote");
    }

    function _u112(string memory name, uint256 fallback_) internal view returns (uint112) {
        uint256 value = vm.envOr(name, fallback_);
        require(value > 0 && value <= type(uint112).max, "reserve out of range");
        return uint112(value);
    }
}

/// 紧急退订。记录次数用完时合约会自己退订。只有 subscribed 仍为 true 时才需要跑这一步。
///   forge script script/DeploySpread.s.sol:StopSpread --rpc-url %LASNA% --broadcast --chain 5318007 --evm-version cancun
contract StopSpread is Script {
    function run() external {
        address reactiveAddr = vm.envAddress("SPREAD_REACTIVE_ADDR");
        SpreadGuard.refuse(reactiveAddr);
        SpreadReactive reactive = SpreadReactive(payable(reactiveAddr));
        require(reactive.MAX_RECORDS() > 0, "not a spread reactive");
        require(
            reactive.RESERVES_TOPIC0() == uint256(keccak256("ReservesUpdated(uint8,uint112,uint112)")),
            "not a spread reactive"
        );

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        reactive.stop();
        vm.stopBroadcast();

        console.log("subscribed", reactive.subscribed());
        console.log("stopped", reactive.stopped());
        console.log("remaining", reactive.remaining());
    }
}
