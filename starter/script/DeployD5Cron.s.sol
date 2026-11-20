// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { D5CronReactive } from "../src/d5/D5CronReactive.sol";
import { D5CronCallback } from "../src/d5/D5CronCallback.sol";

/// @dev 已经在 Sepolia / Lasna 上的 D3/D4 合约。本脚本拒绝再对它们发交易。
library D5Guard {
    address internal constant OLD_ORIGIN = 0x6cfe6d08F328b5f067B9ba7F10dc08ca515De950;
    address internal constant OLD_REACTIVE = 0x9a30c9bc9c6dC4101679A735e121e3856cC12FB6;
    address internal constant OLD_CALLBACK = 0x9bebaFE458DaF45faB88Abd42A2Efc36B38A7A32;

    function refuse(address a) internal pure {
        require(
            a != OLD_ORIGIN && a != OLD_REACTIVE && a != OLD_CALLBACK,
            "refusing to touch the existing D3/D4 contracts"
        );
    }
}

/// 第 1 步：只在 Lasna 部署。此时还不订阅 Cron，所以不会立刻开始扣费。
///   forge script script/DeployD5Cron.s.sol:DeployD5Reactive --rpc-url %LASNA% --broadcast --chain 5318007
contract DeployD5Reactive is Script {
    function run() external {
        uint256 destChain = vm.envOr("DEST_CHAIN_ID", uint256(11155111));
        uint256 limit = vm.envOr("D5_MAX_EXECUTIONS", uint256(2));
        uint256 fund = vm.envOr("D5_REACTIVE_FUND", uint256(0.15 ether));

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        D5CronReactive reactive = new D5CronReactive{ value: fund }(destChain, limit);
        vm.stopBroadcast();

        console.log("D5_REACTIVE_ADDR=", address(reactive));
        console.log("funded lREACT wei", fund);
        console.log("max executions", limit);
        console.log("subscribed", reactive.subscribed());
    }
}

/// 第 2 步：在 Ethereum Sepolia 部署回调合约。构造参数是本链 Proxy + 第 1 步的地址。
///   forge script script/DeployD5Cron.s.sol:DeployD5Callback --rpc-url %SEPOLIA% --broadcast --chain 11155111
contract DeployD5Callback is Script {
    function run() external {
        address proxy = vm.envAddress("CALLBACK_PROXY");
        address reactive = vm.envAddress("D5_REACTIVE_ADDR");
        uint256 fund = vm.envOr("D5_CALLBACK_FUND", uint256(0.02 ether));
        D5Guard.refuse(reactive);
        require(proxy != address(0), "CALLBACK_PROXY missing");
        require(fund > 0, "callback needs ETH for gas");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        D5CronCallback callback = new D5CronCallback{ value: fund }(IPayable(payable(proxy)), reactive);
        vm.stopBroadcast();

        console.log("D5_CALLBACK_ADDR=", address(callback));
        console.log("funded ETH wei", fund);
    }
}

/// 第 3 步：回到 Lasna，绑定回调地址。这一步才订阅 Cron100。
///   forge script script/DeployD5Cron.s.sol:SetD5Recipient --rpc-url %LASNA% --broadcast --chain 5318007
contract SetD5Recipient is Script {
    function run() external {
        address reactiveAddr = vm.envAddress("D5_REACTIVE_ADDR");
        address callbackAddr = vm.envAddress("D5_CALLBACK_ADDR");
        D5Guard.refuse(reactiveAddr);
        D5Guard.refuse(callbackAddr);

        D5CronReactive reactive = D5CronReactive(payable(reactiveAddr));
        // CampReactive 也有 setRecipient(address)。先确认这是本次的 Cron 合约，再发交易。
        require(reactive.MAX_EXECUTIONS() > 0, "not a D5 cron reactive");
        require(reactive.CRON100_TOPIC0() != 0, "not a D5 cron reactive");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        reactive.setRecipient(callbackAddr);
        vm.stopBroadcast();

        console.log("recipient", reactive.recipient());
        console.log("subscribed", reactive.subscribed());
        console.log("remaining", reactive.remaining());
    }
}

/// 紧急刹车：满 2 次之后合约会自己退订。只有 subscribed 仍为 true 时才需要跑这一步。
///   forge script script/DeployD5Cron.s.sol:StopD5 --rpc-url %LASNA% --broadcast --chain 5318007
contract StopD5 is Script {
    function run() external {
        address reactiveAddr = vm.envAddress("D5_REACTIVE_ADDR");
        D5Guard.refuse(reactiveAddr);
        D5CronReactive reactive = D5CronReactive(payable(reactiveAddr));
        require(reactive.MAX_EXECUTIONS() > 0, "not a D5 cron reactive");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        reactive.stop();
        vm.stopBroadcast();

        console.log("subscribed", reactive.subscribed());
        console.log("stopped", reactive.stopped());
        console.log("remaining", reactive.remaining());
    }
}
