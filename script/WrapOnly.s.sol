// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Present, DistributionType, Asset} from "../src/Present.sol";

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

        Asset[] memory content = new Asset[](1);
        content[0] = Asset(address(0), amount);

        vm.startBroadcast(pk);
        present.wrapPresent{value: amount}(
            recipients,
            "ETH-only Gift",
            "This is a sample gift containing only ETH.",
            content,
            DistributionType.FIRST_COME_FIRST_SERVED,
            0 // claimLimit is ignored for this mode
        );
        console.log("[WRAP_ONLY] wrapped ETH:", amount, "public:", isPublic);
        vm.stopBroadcast();
    }
} 