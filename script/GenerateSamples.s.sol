// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {Present, DistributionType, Asset} from "../src/Present.sol";

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

        // 2) 样例 A：wrap + unwrap（定向给自己, FIRST_COME_FIRST_SERVED 模式）
        {
            address[] memory recipients = new address[](1);
            recipients[0] = sender;
            Asset[] memory assets = new Asset[](1);
            assets[0] = Asset(address(0), 0.0005 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0005 ether}(
                recipients,
                "Sample A: Simple Gift",
                "A simple gift for myself",
                assets,
                DistributionType.FIRST_COME_FIRST_SERVED,
                0 // claimLimit is ignored in this mode
            );
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE] A wrapped:", _toHex(presentId));

            present.claimPresent(presentId);
            console.log("[SAMPLE] A unwrapped by sender");
        }

        // 3) 样例 B：wrap + takeBack（定向给自己, FIRST_COME_FIRST_SERVED 模式）
        {
            address[] memory recipients = new address[](1);
            recipients[0] = sender;
            Asset[] memory assets = new Asset[](1);
            assets[0] = Asset(address(0), 0.0004 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0004 ether}(
                recipients,
                "Sample B: Take Back",
                "A gift to be taken back",
                assets,
                DistributionType.FIRST_COME_FIRST_SERVED,
                0 // claimLimit is ignored
            );
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE] B wrapped:", _toHex(presentId));

            present.takeBack(presentId);
            console.log("[SAMPLE] B taken back by sender");
        }

        // 4) 样例 C：公开礼物, FIRST_COME_FIRST_SERVED 模式
        {
            address[] memory recipients = new address[](0); // 公开
            Asset[] memory assets = new Asset[](1);
            assets[0] = Asset(address(0), 0.0003 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0003 ether}(
                recipients,
                "Sample C: Public Gift",
                "Anyone can claim this",
                assets,
                DistributionType.FIRST_COME_FIRST_SERVED,
                0 // claimLimit is ignored
            );
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE] C wrapped (public):", _toHex(presentId));

            present.claimPresent(presentId);
            console.log("[SAMPLE] C unwrapped by sender (public)");
        }

        // 5) 样例 D：仅打包（保持 ACTIVE 状态供查询）
        {
            address[] memory recipients = new address[](1);
            recipients[0] = sender;
            Asset[] memory assets = new Asset[](1);
            assets[0] = Asset(address(0), 0.0002 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0002 ether}(
                recipients,
                "Sample D: Active Gift",
                "This gift will remain active",
                assets,
                DistributionType.FIRST_COME_FIRST_SERVED,
                0 // claimLimit is ignored
            );
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE] D wrapped (left active):", _toHex(presentId));
        }

        // 6) 样例 E：白名单均分
        {
            address alice = vm.addr(100);
            address bob = vm.addr(101);
            address[] memory recipients = new address[](3);
            recipients[0] = sender;
            recipients[1] = alice;
            recipients[2] = bob;

            Asset[] memory assets = new Asset[](1);
            assets[0] = Asset(address(0), 0.0006 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0006 ether}(
                recipients,
                "Sample E: Whitelist Split",
                "A gift for the team",
                assets,
                DistributionType.WHITELIST_EQUAL_SPLIT,
                0 // claimLimit is ignored, will be recipients.length
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
            Asset[] memory assets = new Asset[](1);
            assets[0] = Asset(address(0), 0.001 ether);
            
            vm.recordLogs();
            present.wrapPresent{value: 0.001 ether}(
                new address[](0),
                "Sample F: Limited Split",
                "Public gift for 10 people",
                assets,
                DistributionType.LIMITED_QUANTITY_EQUAL_SPLIT,
                10
            );
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE] F wrapped (limited quantity split):", _toHex(presentId));
        }

        // 8) 样例 G: 限量随机 (现在是均分)
        {
            Asset[] memory assets = new Asset[](1);
            assets[0] = Asset(address(0), 0.01 ether); 

            vm.recordLogs();
            present.wrapPresent{value: 0.01 ether}(
                new address[](0),
                "Sample G: Random Split",
                "A lucky draw!",
                assets,
                DistributionType.LIMITED_QUANTITY_RANDOM_SPLIT,
                7 // 7 winners
            );
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