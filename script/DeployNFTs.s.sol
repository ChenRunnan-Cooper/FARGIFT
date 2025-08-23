// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Present} from "../src/Present.sol";
import {WrappedPresentNFT} from "../src/nft/WrappedPresentNFT.sol";
import {UnwrappedPresentNFT} from "../src/nft/UnwrappedPresentNFT.sol";

interface INFTAdmin {
    function setPresentContract(address present) external;
}

contract DeployNFTs is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(deployer);

        address presentAddress = vm.envAddress("PRESENT_ADDRESS");
        require(presentAddress != address(0), "PRESENT_ADDRESS env not set");

        WrappedPresentNFT wrapped = new WrappedPresentNFT(presentAddress);
        UnwrappedPresentNFT unwrapped = new UnwrappedPresentNFT(presentAddress);

        INFTAdmin(address(wrapped)).setPresentContract(presentAddress);
        INFTAdmin(address(unwrapped)).setPresentContract(presentAddress);

        Present(payable(presentAddress)).setNFTContracts(address(wrapped), address(unwrapped));

        console.log("Wrapped NFT Deployed at:", address(wrapped));
        console.log("Unwrapped NFT Deployed at:", address(unwrapped));
        vm.stopBroadcast();
    }
} 