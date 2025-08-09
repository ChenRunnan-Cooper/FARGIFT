// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/WrappedPresentNFT.sol";
import "../src/UnwrappedPresentNFT.sol";
// import "../src/wrapPresent_unwrapPresent_takeBack.sol"; // 主合约

contract DeployScript is Script {
    
    function run() external {
        // 从环境变量获取私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // 开始广播交易
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying contracts...");
        console.log("Deployer address:", vm.addr(deployerPrivateKey));
        
        // 部署 WrappedPresentNFT
        WrappedPresentNFT wrappedNFT = new WrappedPresentNFT();
        console.log("WrappedPresentNFT deployed at:", address(wrappedNFT));
        
        // 部署 UnwrappedPresentNFT  
        UnwrappedPresentNFT unwrappedNFT = new UnwrappedPresentNFT();
        console.log("UnwrappedPresentNFT deployed at:", address(unwrappedNFT));
        
        // 部署主合约 (如果有的话)
        // YourMainContract mainContract = new YourMainContract(
        //     address(wrappedNFT),
        //     address(unwrappedNFT)
        // );
        // console.log("Main contract deployed at:", address(mainContract));
        
        // 验证部署
        require(address(wrappedNFT) != address(0), "WrappedPresentNFT deployment failed");
        require(address(unwrappedNFT) != address(0), "UnwrappedPresentNFT deployment failed");
        
        console.log("All contracts deployed successfully!");
        
        // 停止广播
        vm.stopBroadcast();
        
        // 保存部署地址到文件 (可选)
        _saveDeploymentAddresses(address(wrappedNFT), address(unwrappedNFT));
    }
    
    function _saveDeploymentAddresses(address wrappedNFT, address unwrappedNFT) internal {
        string memory deployments = string(abi.encodePacked(
            "WRAPPED_PRESENT_NFT_ADDRESS=", vm.toString(wrappedNFT), "\n",
            "UNWRAPPED_PRESENT_NFT_ADDRESS=", vm.toString(unwrappedNFT), "\n"
        ));
        
        vm.writeFile("deployments.txt", deployments);
        console.log("Deployment addresses saved to deployments.txt");
    }
}