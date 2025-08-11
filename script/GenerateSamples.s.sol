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

            present.unwrapPresent(presentId);
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

            present.unwrapPresent(presentId);
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