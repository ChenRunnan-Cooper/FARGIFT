// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {Present} from "../src/Present.sol";

contract GenerateSamples is Script {
    // WrapPresent(bytes32,address)
    bytes32 constant WRAP_PRESENT_EVENT_SIG = 0xf57d75a06786ec46ba529c7c6a4a8c5f0c1eae07a3a01fa6c75da0320a9f7588;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(pk);

        vm.startBroadcast(pk);

        // 1) 部署一个新的 Present 合约（owner=sender）
        Present present = new Present(sender);
        console.log("[SAMPLE] Present deployed:", address(present));

        // 2) 样例 A：wrap + unwrap（定向给自己）
        {
            address[] memory recipients = new address[](1);
            recipients[0] = sender;
            Present.Asset[] memory assets = new Present.Asset[](1);
            assets[0] = Present.Asset(address(0), 0.0005 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0005 ether}(recipients, assets);
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE] A wrapped:", _toHex(presentId));

            present.claimPresent(presentId);
            console.log("[SAMPLE] A unwrapped by sender");
        }

        // 3) 样例 B：wrap + takeBack（定向给自己，立即收回）
        {
            address[] memory recipients = new address[](1);
            recipients[0] = sender;
            Present.Asset[] memory assets = new Present.Asset[](1);
            assets[0] = Present.Asset(address(0), 0.0004 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0004 ether}(recipients, assets);
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE] B wrapped:", _toHex(presentId));

            present.takeBack(presentId);
            console.log("[SAMPLE] B taken back by sender");
        }

        // 4) 样例 C：公开礼物（anyone 可拆），这里仍由 sender 拆开
        {
            address[] memory recipients = new address[](0); // 公开
            Present.Asset[] memory assets = new Present.Asset[](1);
            assets[0] = Present.Asset(address(0), 0.0003 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0003 ether}(recipients, assets);
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE] C wrapped (public):", _toHex(presentId));

            present.claimPresent(presentId);
            console.log("[SAMPLE] C unwrapped by sender (public)");
        }

        // 5) 样例 D：仅打包（保持 ACTIVE 状态供查询）
        {
            address[] memory recipients = new address[](1);
            recipients[0] = sender;
            Present.Asset[] memory assets = new Present.Asset[](1);
            assets[0] = Present.Asset(address(0), 0.0002 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0002 ether}(recipients, assets);
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE] D wrapped (left active):", _toHex(presentId));
        }

        // 6) 样例 E: 白名单均分
        {
            address alice = vm.addr(100);
            address bob = vm.addr(101);
            address[] memory recipients = new address[](3);
            recipients[0] = sender;
            recipients[1] = alice;
            recipients[2] = bob;

            Present.Asset[] memory assets = new Present.Asset[](1);
            assets[0] = Present.Asset(address(0), 0.0006 ether);

            vm.recordLogs();
            present.wrapPresentWithOptions{value: 0.0006 ether}(
                recipients, assets, Present.DistributionType.WHITELIST_EQUAL_SPLIT, 0
            );
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE] E wrapped (whitelist split):", _toHex(presentId));
            
            // 模拟 sender 和 alice 领取
            present.claimPresent(presentId);
            console.log("[SAMPLE] E claimed by sender");
            vm.prank(alice);
            present.claimPresent(presentId);
            console.log("[SAMPLE] E claimed by alice (bob can still claim)");
        }

        // 7) 样例 F: 限量均分 (公开抢)
        {
            Present.Asset[] memory assets = new Present.Asset[](1);
            assets[0] = Present.Asset(address(0), 0.001 ether);
            
            vm.recordLogs();
            present.wrapPresentWithOptions{value: 0.001 ether}(
                new address[](0), assets, Present.DistributionType.LIMITED_QUANTITY_EQUAL_SPLIT, 10
            );
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE] F wrapped (limited quantity split):", _toHex(presentId));
        }

        // 8) 样例 G: 限量随机
        {
            Present.Asset[] memory assets = new Present.Asset[](1);
            assets[0] = Present.Asset(address(0), 0.01 ether); // 100%

            Present.PrizeTier[] memory prizeTiers = new Present.PrizeTier[](3);
            // 大奖: 1份, 50%
            prizeTiers[0] = Present.PrizeTier({ valuePercent: 5000, count: 1, claimedCount: 0 });
            // 中奖: 2份, 15% each (30%)
            prizeTiers[1] = Present.PrizeTier({ valuePercent: 1500, count: 2, claimedCount: 0 });
            // 小奖: 4份, 5% each (20%)
            prizeTiers[2] = Present.PrizeTier({ valuePercent: 500, count: 4, claimedCount: 0 });
            // Total: 1+2+4=7 prizes, 50+30+20=100%

            vm.recordLogs();
            present.wrapPresentRandom{value: 0.01 ether}(assets, prizeTiers);
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE] G wrapped (random split):", _toHex(presentId));
        }

        vm.stopBroadcast();
    }

    function _getPresentIdFromLogs(Vm.Log[] memory entries) internal pure returns (bytes32) {
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == WRAP_PRESENT_EVENT_SIG) {
                return bytes32(entries[i].topics[1]);
            }
        }
        revert("WrapPresent event not found");
    }

    function _toHex(bytes32 x) internal pure returns (string memory) {
        bytes memory s = new bytes(66);
        s[0] = "0";
        s[1] = "x";
        for (uint i = 0; i < 32; i++) {
            uint8 b = uint8(uint256(x) >> (8 * (31 - i)));
            uint8 hi = b / 16;
            uint8 lo = b % 16;
            s[2 + 2 * i] = _hexChar(hi);
            s[3 + 2 * i] = _hexChar(lo);
        }
        return string(s);
    }

    function _hexChar(uint8 c) private pure returns (bytes1) {
        if (c < 10) return bytes1(c + 48);
        return bytes1(c + 87);
    }
} 