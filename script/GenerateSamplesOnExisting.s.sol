// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {Present, DistributionType, Asset} from "../src/Present.sol";

contract GenerateSamplesOnExisting is Script {
    // WrapPresent(bytes32,address)
    bytes32 constant WRAP_PRESENT_EVENT_SIG = 0xf57d75a06786ec46ba529c7c6a4a8c5f0c1eae07a3a01fa6c75da0320a9f7588;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address presentAddr = vm.envAddress("PRESENT_ADDRESS");
        address sender = vm.addr(pk);

        Present present = Present(payable(presentAddr));

        vm.startBroadcast(pk);

        // A: wrap -> unwrap (recipient = sender)
        {
            address[] memory recipients = new address[](1);
            recipients[0] = sender;
            Asset[] memory assets = new Asset[](1);
            assets[0] = Asset(address(0), 0.0005 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0005 ether}(
                recipients,
                "Sample A on Existing",
                "Simple gift",
                assets,
                DistributionType.FIRST_COME_FIRST_SERVED,
                0
            );
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE_EXIST] A wrapped:", _toHex(presentId));

            present.claimPresent(presentId);
            console.log("[SAMPLE_EXIST] A unwrapped by sender");
        }

        // B: wrap -> takeBack (recipient = sender)
        {
            address[] memory recipients = new address[](1);
            recipients[0] = sender;
            Asset[] memory assets = new Asset[](1);
            assets[0] = Asset(address(0), 0.0004 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0004 ether}(
                recipients,
                "Sample B on Existing",
                "To be taken back",
                assets,
                DistributionType.FIRST_COME_FIRST_SERVED,
                0
            );
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE_EXIST] B wrapped:", _toHex(presentId));

            present.takeBack(presentId);
            console.log("[SAMPLE_EXIST] B taken back");
        }

        // C: public wrap -> unwrap
        {
            address[] memory recipients = new address[](0);
            Asset[] memory assets = new Asset[](1);
            assets[0] = Asset(address(0), 0.0003 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0003 ether}(
                recipients,
                "Sample C on Existing",
                "Public gift",
                assets,
                DistributionType.FIRST_COME_FIRST_SERVED,
                0
            );
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE_EXIST] C wrapped (public):", _toHex(presentId));

            present.claimPresent(presentId);
            console.log("[SAMPLE_EXIST] C unwrapped by sender (public)");
        }

        // D: keep ACTIVE
        {
            address[] memory recipients = new address[](1);
            recipients[0] = sender;
            Asset[] memory assets = new Asset[](1);
            assets[0] = Asset(address(0), 0.0002 ether);

            vm.recordLogs();
            present.wrapPresent{value: 0.0002 ether}(
                recipients,
                "Sample D on Existing",
                "Left active",
                assets,
                DistributionType.FIRST_COME_FIRST_SERVED,
                0
            );
            bytes32 presentId = _getPresentIdFromLogs(vm.getRecordedLogs());
            console.log("[SAMPLE_EXIST] D wrapped (left active):", _toHex(presentId));
        }

        // E: 限量随机模式 (LIMITED_QUANTITY_RANDOM_SPLIT)
        console.log("-> Wrapping a LIMITED_QUANTITY_RANDOM_SPLIT present...");
        Asset[] memory content_E = new Asset[](1);
        content_E[0] = Asset({tokens: address(0), amounts: 0.0004 ether});
        uint256 claimLimit_E = 5; // 5 人随机分

        present.wrapPresent{value:0.0004 ether}(
            new address[](0),
            "Sample: Random Split (5 winners)",
            "A public gift where 5 winners will split the total amount.",
            content_E,
            DistributionType.LIMITED_QUANTITY_RANDOM_SPLIT,
            claimLimit_E
        );
        console.log("   Done wrapping random split.");
        
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