// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Present} from "../src/Present.sol";

contract WrapOnceTest is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address presentAddr = vm.envAddress("PRESENT_ADDRESS");
        address sender = vm.addr(pk);
        vm.startBroadcast(pk);

        Present present = Present(payable(presentAddr));

        address[] memory recipients = new address[](1);
        recipients[0] = address(0); // 设为空地址以模拟公开领取（或填入指定地址）

        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(0), 0.01 ether);

        present.wrapPresentTest{value: 0.01 ether}(recipients, "Demo Gift", "On local fork with NFTs", assets);
        console.log("wrapPresentTest executed");

        vm.stopBroadcast();
    }
} 