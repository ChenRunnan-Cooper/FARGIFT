// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Present, DistributionType, Asset} from "../src/Present.sol";

contract WrapOnceTest is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address presentAddr = vm.envAddress("PRESENT_ADDRESS");
        vm.startBroadcast(pk);

        Present present = Present(payable(presentAddr));

        address[] memory recipients = new address[](1);
        recipients[0] = address(0); // 设为空地址以模拟公开领取（或填入指定地址）

        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset(address(0), 0.01 ether);

        present.wrapPresent{value: 0.01 ether}(
            new address[](0),
            "Test Gift",
            "This is a test present.",
            assets,
            DistributionType.FIRST_COME_FIRST_SERVED,
            0 // claimLimit is ignored for FCFS
        );
        console.log("wrapPresent executed");

        vm.stopBroadcast();
    }
} 