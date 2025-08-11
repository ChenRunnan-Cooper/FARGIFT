// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Present} from "../src/Present.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract WrapWithERC20 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address presentAddr = vm.envAddress("PRESENT_ADDRESS");
        address sender = vm.addr(pk);

        // 可选：使用已有 ERC20（通过 TOKEN_ADDRESS 指定），否则部署一个 MockERC20
        address tokenAddr;
        try vm.envAddress("TOKEN_ADDRESS") returns (address t) {
            tokenAddr = t;
        } catch {
            vm.startBroadcast(pk);
            MockERC20 mock = new MockERC20("TestToken", "TT", 18);
            tokenAddr = address(mock);
            vm.stopBroadcast();
        }

        vm.startBroadcast(pk);

        // 给 sender 铸造代币（如果是我们部署的 MockERC20）
        if (_isContractDeployedByThisRun(tokenAddr)) {
            MockERC20(tokenAddr).mint(sender, 1_000_000 ether);
        }

        // 授权 Present 合约
        MockERC20(tokenAddr).approve(presentAddr, type(uint256).max);

        // 组装 recipients 与 content，调用 wrapPresentTest（带元数据便于前端/Farcaster 展示）
        Present present = Present(payable(presentAddr));
        address[] memory recipients = new address[](1);
        recipients[0] = sender; // 定向给自己，便于后续 unwrap

        Present.Asset[] memory content = new Present.Asset[](1);
        content[0] = Present.Asset(tokenAddr, 1234 ether); // 测试金额

        present.wrapPresentTest(recipients, "ERC20 Gift", "Test token wrapped via script", content);

        vm.stopBroadcast();
    }

    function _isContractDeployedByThisRun(address token) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(token) }
        return size > 0;
    }
} 