// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MerkleDistributor.sol";

contract DeployScript is Script {
    function run() external returns (MerkleDistributor) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        MerkleDistributor distributor = new MerkleDistributor();

        vm.stopBroadcast();

        console.log("MerkleDistributor deployed at:", address(distributor));
        console.log("Owner:", distributor.owner());

        return distributor;
    }
}
