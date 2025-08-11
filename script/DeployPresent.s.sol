// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Present} from "../src/Present.sol";

/**
 * @title DeployPresent
 * @dev 用于部署Present合约到Arbitrum测试网（Sepolia）
 * 运行命令: forge script script/DeployPresent.s.sol:DeployPresent --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
 */
contract DeployPresent is Script {
    function setUp() public {}

    function run() public {
        // 从环境变量或配置中获取部署者私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // 开始广播交易
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署Present合约
        address owner = vm.addr(deployerPrivateKey);
        Present present = new Present(owner);
        
        // 输出部署地址
        console.log("Present contract deployed at:", address(present));
        
        // 结束广播
        vm.stopBroadcast();
    }
}

/**
 * @title DeployPresentWithNFTs
 * @dev 完整部署Present合约及其关联的NFT合约（如果有）
 */
contract DeployPresentWithNFTs is Script {
    function setUp() public {}

    function run() public {
        // 从环境变量或配置中获取部署者私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // 开始广播交易
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署Present合约
        address owner = vm.addr(deployerPrivateKey);
        Present present = new Present(owner);
        
        // 输出部署地址
        console.log("Present contract deployed at:", address(present));
        
        // 这里可以部署NFT合约，并设置它们的地址
        // 例如：
        // WrappedPresentNFT wrappedNFT = new WrappedPresentNFT();
        // UnwrappedPresentNFT unwrappedNFT = new UnwrappedPresentNFT();
        // present.setNFTContracts(address(wrappedNFT), address(unwrappedNFT));
        
        // 结束广播
        vm.stopBroadcast();
    }
}

/**
 * @title TestPresentCalls
 * @dev 在已部署的Present合约上执行测试调用
 */
contract TestPresentCalls is Script {
    function setUp() public {}

    function run() public {
        // 从环境变量或配置中获取发送者私钥和合约地址
        uint256 senderPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable presentAddress = payable(vm.envAddress("PRESENT_ADDRESS"));
        
        Present present = Present(presentAddress);
        
        // 开始广播交易
        vm.startBroadcast(senderPrivateKey);
        
        // 创建测试礼物
        address[] memory recipients = new address[](1);
        recipients[0] = address(0x1234567890123456789012345678901234567890); // 测试接收者
        
        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(0), 0.01 ether); // 发送0.01 ETH
        
        // 包装礼物
        present.wrapPresent{value: 0.01 ether}(recipients, assets);
        console.log("Gift created successfully");
        
        // 结束广播
        vm.stopBroadcast();
    }
} 