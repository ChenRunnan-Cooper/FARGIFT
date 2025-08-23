// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Present, DistributionType, Asset} from "../src/Present.sol";

contract SimulatePresent is Script {
    function run(address presentAddr) external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(pk);

        // 在fork仿真环境中为发送者临时注入余额，避免lack of funds错误
        vm.deal(sender, 1 ether);

        vm.startBroadcast(pk);

        address owner = sender;
        Present present = new Present(owner);
        console.log("[SIM] Present deployed:", address(present));

        // 构造一次wrapPresent调用
        address[] memory recipients = new address[](1);
        recipients[0] = address(0x1234567890123456789012345678901234567890);

        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset(address(0), 0.01 ether);

        present.wrapPresent(
            recipients,
            "For Simulation",
            "This is a test present for simulation.",
            assets,
            DistributionType.FIRST_COME_FIRST_SERVED,
            0 // claimLimit is ignored for FCFS mode
        );
        console.log("[SIM] wrapPresent called successfully");

        vm.stopBroadcast();
    }
} 