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
        address presentAddr = vm.envAddress("PRESENT_ADDRESS");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);
        WrappedPresentNFT wrapped = new WrappedPresentNFT("FarGift Wrapped", "FGW", deployer);
        UnwrappedPresentNFT unwrapped = new UnwrappedPresentNFT("FarGift Unwrapped", "FGU", deployer);

        INFTAdmin(address(wrapped)).setPresentContract(presentAddr);
        INFTAdmin(address(unwrapped)).setPresentContract(presentAddr);

        Present(payable(presentAddr)).setNFTContracts(address(wrapped), address(unwrapped));

        console.log("Wrapped NFT:", address(wrapped));
        console.log("Unwrapped NFT:", address(unwrapped));
        vm.stopBroadcast();
    }
} 