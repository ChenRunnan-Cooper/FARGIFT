// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Present} from "../src/Present.sol";

contract WrapPublicOnce is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address presentAddr = vm.envAddress("PRESENT_ADDRESS");
        vm.startBroadcast(pk);

        Present present = Present(payable(presentAddr));

        address[] memory recipients = new address[](0); // 公开领取
        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(0), 0.01 ether);

        present.wrapPresentTest{value: 0.01 ether}(recipients, "Public Demo", "Anyone can unwrap", assets);
        console.log("wrapPresentTest(public) executed");

        vm.stopBroadcast();
    }
} 