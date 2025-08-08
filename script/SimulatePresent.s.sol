// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Present} from "../src/Present.sol";

contract Simulate is Script {
    function setUp() public {}

    function run() public {
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

        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(0), 0.01 ether);

        present.wrapPresent{value: 0.01 ether}(recipients, assets);
        console.log("[SIM] wrapPresent called successfully");

        vm.stopBroadcast();
    }
} 