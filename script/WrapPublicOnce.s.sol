// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Present, DistributionType, Asset} from "../src/Present.sol";

contract WrapPublicOnce is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address presentAddr = vm.envAddress("PRESENT_ADDRESS");
        vm.startBroadcast(pk);

        Present present = Present(payable(presentAddr));

        address[] memory recipients = new address[](0); // 公开领取
        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset(address(0), 0.01 ether);

        present.wrapPresent{value: 0.0001 ether}(
            new address[](0),
            "Public Gift",
            "This is a public gift for anyone to claim.",
            assets,
            DistributionType.FIRST_COME_FIRST_SERVED,
            0 // claimLimit is ignored
        );
        console.log("wrapPresent(public) executed");

        vm.stopBroadcast();
    }
} 