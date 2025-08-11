// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Present} from "../src/Present.sol";

contract WrapOnly is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address presentAddr = vm.envAddress("PRESENT_ADDRESS");
        address sender = vm.addr(pk);

        // 控制是否公开礼物（WRAP_PUBLIC=1 表示公开，默认定向给自己）
        bool isPublic = false;
        try vm.envUint("WRAP_PUBLIC") returns (uint256 v) { isPublic = (v == 1); } catch {}

        // ETH 金额（默认为 0.0005 ETH）
        uint256 amount = 5e14;
        try vm.envUint("WRAP_ETH_AMOUNT_WEI") returns (uint256 a) { amount = a; } catch {}

        Present present = Present(payable(presentAddr));

        // 组装 recipients
        address[] memory recipients;
        if (isPublic) {
            recipients = new address[](0);
        } else {
            recipients = new address[](1);
            recipients[0] = sender;
        }

        Present.Asset[] memory content = new Present.Asset[](1);
        content[0] = Present.Asset(address(0), amount);

        vm.startBroadcast(pk);
        present.wrapPresent{value: amount}(recipients, content);
        console.log("[WRAP_ONLY] wrapped ETH:", amount, "public:", isPublic);
        vm.stopBroadcast();
    }
} 