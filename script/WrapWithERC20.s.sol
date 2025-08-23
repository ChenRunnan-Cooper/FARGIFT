// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Present, DistributionType, Asset} from "../src/Present.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WrapWithERC20 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address presentAddr = vm.envAddress("PRESENT_ADDRESS");
        address sender = vm.addr(pk);

        // 可选：使用已有 ERC20（通过 TOKEN_ADDRESS 指定），否则部署一个 MockERC20
        address tokenAddr;
        bool deployedLocal = false;
        try vm.envAddress("TOKEN_ADDRESS") returns (address t) {
            tokenAddr = t;
        } catch {
            vm.startBroadcast(pk);
            MockERC20 mock = new MockERC20("TestToken", "TT", 18);
            tokenAddr = address(mock);
            deployedLocal = true;
            vm.stopBroadcast();
        }

        vm.startBroadcast(pk);

        // 仅当由本脚本部署的 MockERC20 时才铸币
        if (deployedLocal) {
            MockERC20(tokenAddr).mint(sender, 1_000_000 ether);
        }

        // 授权 Present 合约（标准 ERC20 接口）
        MockERC20(tokenAddr).approve(presentAddr, type(uint256).max);

        // 组装 recipients 与 content，调用 wrapPresentTest（带元数据便于前端/Farcaster 展示）
        Present present = Present(payable(presentAddr));
        address[] memory recipients = new address[](1);
        recipients[0] = sender; // 定向给自己，便于后续 unwrap

        Asset[] memory content = new Asset[](1);
        content[0] = Asset(tokenAddr, 1234 ether); // 测试金额

        present.wrapPresent(
            recipients,
            "ERC20 Gift",
            "A sample gift containing MockERC20 tokens.",
            content,
            DistributionType.FIRST_COME_FIRST_SERVED,
            0 // claimLimit is ignored
        );
        vm.stopBroadcast();

        console.log("ERC20 gift wrapped successfully.");
    }
} 