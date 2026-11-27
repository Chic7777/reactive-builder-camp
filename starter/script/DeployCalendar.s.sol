// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ClarityCalendar } from "../src/calendar/ClarityCalendar.sol";
import { ClarityReactive } from "../src/calendar/ClarityReactive.sol";
import { CalendarGuard } from "../src/calendar/CalendarGuard.sol";

address constant SEPOLIA_CALLBACK_PROXY = 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4;

/// 拒绝官方示例、D5，以及 .env 里其他实验地址。
abstract contract CalendarScript is Script {
    function _refuseKnown(address a) internal view {
        CalendarGuard.refuse(a);
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
        _differ(a, "SIGNAL_BOARD_ADDR");
        _differ(a, "SIGNAL_REACTIVE_ADDR");
        _differ(a, "SIGNAL_LEDGER_ADDR");
    }

    function _differ(address a, string memory key) internal view {
        address other = vm.envOr(key, address(0));
        require(other == address(0) || other != a, "address belongs to another lab");
    }
}

/// 不广播。只推出部署者地址。私钥不会被打印。
contract ShowSender is Script {
    function run() external view {
        address sender = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("sender", sender);
    }
}

/// 第 1 步：Sepolia 部署日历，并转入付回调 gas 的 ETH。此时还未绑定 Reactive。
///   forge script script/DeployCalendar.s.sol:DeployCalendar --rpc-url %SEPOLIA% --broadcast --chain 11155111 --evm-version cancun
contract DeployCalendar is CalendarScript {
    function run() external {
        address proxy = vm.envAddress("CALLBACK_PROXY");
        uint256 fund = vm.envOr("CALENDAR_FUND", uint256(0.001 ether));
        require(proxy == SEPOLIA_CALLBACK_PROXY, "CALLBACK_PROXY must be the Sepolia Omni proxy");
        require(fund > 0, "calendar needs ETH for callback gas");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        ClarityCalendar calendar = new ClarityCalendar{ value: fund }(IPayable(payable(proxy)));
        vm.stopBroadcast();

        console.log("CALENDAR_ADDR=", address(calendar));
        console.log("funded ETH wei", fund);
        console.log("clarity demo", calendar.CLARITY_DEMO());
    }
}

/// 第 2 步：Lasna 部署 ClarityReactive 并转入 lREACT。还不订阅。
///   forge script script/DeployCalendar.s.sol:DeployCalendarReactive --rpc-url %LASNA% --broadcast --chain 5318007 --evm-version cancun
contract DeployCalendarReactive is CalendarScript {
    function run() external {
        uint256 originChain = vm.envOr("ORIGIN_CHAIN_ID", uint256(11155111));
        address origin = vm.envAddress("CALENDAR_ADDR");
        uint256 destChain = vm.envOr("DEST_CHAIN_ID", uint256(11155111));
        uint256 window = vm.envOr("CALENDAR_WINDOW", uint256(1800));
        uint256 cronCap = vm.envOr("CALENDAR_CRON_CAP", uint256(8));
        uint256 fund = vm.envOr("CALENDAR_REACTIVE_FUND", uint256(0.05 ether));
        _refuseKnown(origin);
        require(origin != address(0), "CALENDAR_ADDR missing");
        require(originChain == 11155111 && destChain == 11155111, "calendar path is Sepolia only");
        require(fund > 0, "reactive needs lREACT");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        ClarityReactive reactive =
            new ClarityReactive{ value: fund }(originChain, origin, destChain, window, cronCap);
        vm.stopBroadcast();

        console.log("CALENDAR_REACTIVE_ADDR=", address(reactive));
        console.log("funded lREACT wei", fund);
        console.log("window seconds", window);
        console.log("cron cap", cronCap);
        console.log("subscribedEvents", reactive.subscribedEvents());
        console.log("subscribedCron", reactive.subscribedCron());
    }
}

/// 第 3 步：Sepolia 上 calendar.bindReactive + Lasna 上 setRecipient。分两个脚本，避免跨链。
///   forge script script/DeployCalendar.s.sol:BindCalendarOnSepolia --rpc-url %SEPOLIA% --broadcast --chain 11155111 --evm-version cancun
contract BindCalendarOnSepolia is CalendarScript {
    function run() external {
        address calendarAddr = vm.envAddress("CALENDAR_ADDR");
        address reactiveAddr = vm.envAddress("CALENDAR_REACTIVE_ADDR");
        _refuseKnown(calendarAddr);
        _refuseKnown(reactiveAddr);
        ClarityCalendar calendar = ClarityCalendar(payable(calendarAddr));
        require(calendar.CLARITY_DEMO(), "not the clarity calendar");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        calendar.bindReactive(reactiveAddr);
        vm.stopBroadcast();

        console.log("reactive", calendar.reactive());
    }
}

///   forge script script/DeployCalendar.s.sol:BindCalendarOnLasna --rpc-url %LASNA% --broadcast --chain 5318007 --evm-version cancun
contract BindCalendarOnLasna is CalendarScript {
    function run() external {
        address calendarAddr = vm.envAddress("CALENDAR_ADDR");
        address reactiveAddr = vm.envAddress("CALENDAR_REACTIVE_ADDR");
        _refuseKnown(calendarAddr);
        _refuseKnown(reactiveAddr);
        ClarityReactive reactive = ClarityReactive(payable(reactiveAddr));
        require(reactive.ORIGIN_CONTRACT() == calendarAddr, "reactive is not watching this calendar");
        require(reactive.WINDOW() > 0, "not a clarity reactive");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        reactive.setRecipient(calendarAddr);
        vm.stopBroadcast();

        console.log("recipient", reactive.recipient());
        console.log("subscribedEvents", reactive.subscribedEvents());
        console.log("subscribedCron", reactive.subscribedCron());
    }
}

/// 演示：开一团并承诺放下。这是作业源链交易之一。
///   forge script script/DeployCalendar.s.sol:DemoPledge --rpc-url %SEPOLIA% --broadcast --chain 11155111 --evm-version cancun
contract DemoPledge is CalendarScript {
    function run() external {
        address calendarAddr = vm.envAddress("CALENDAR_ADDR");
        _refuseKnown(calendarAddr);
        ClarityCalendar calendar = ClarityCalendar(payable(calendarAddr));
        require(calendar.CLARITY_DEMO(), "not the clarity calendar");
        require(calendar.reactive() != address(0), "bind reactive first");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        uint256 id = calendar.openThread();
        calendar.pledgeLetGo(id);
        vm.stopBroadcast();

        console.log("threadId", id);
        console.log("source pledge tx for homework path");
    }
}

/// 演示：对已有一团再 touch（重置窗口）。需要 CALENDAR_DEMO_THREAD_ID。
///   forge script script/DeployCalendar.s.sol:DemoTouch --rpc-url %SEPOLIA% --broadcast --chain 11155111 --evm-version cancun
contract DemoTouch is CalendarScript {
    function run() external {
        address calendarAddr = vm.envAddress("CALENDAR_ADDR");
        uint256 threadId = vm.envUint("CALENDAR_DEMO_THREAD_ID");
        _refuseKnown(calendarAddr);
        require(threadId != 0, "CALENDAR_DEMO_THREAD_ID missing");
        ClarityCalendar calendar = ClarityCalendar(payable(calendarAddr));
        require(calendar.CLARITY_DEMO(), "not the clarity calendar");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        calendar.touch(threadId);
        vm.stopBroadcast();

        console.log("touched thread", threadId);
    }
}

/// 紧急退订。
///   forge script script/DeployCalendar.s.sol:StopCalendar --rpc-url %LASNA% --broadcast --chain 5318007 --evm-version cancun
contract StopCalendar is CalendarScript {
    function run() external {
        address reactiveAddr = vm.envAddress("CALENDAR_REACTIVE_ADDR");
        _refuseKnown(reactiveAddr);
        ClarityReactive reactive = ClarityReactive(payable(reactiveAddr));

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        reactive.stop();
        vm.stopBroadcast();

        console.log("subscribedEvents", reactive.subscribedEvents());
        console.log("subscribedCron", reactive.subscribedCron());
        console.log("stopped", reactive.stopped());
    }
}
