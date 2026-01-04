// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MerkleDistributor.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CreateDistributionScript is Script {
    function run() external {
        address distributorAddr = vm.envAddress("MERKLE_DISTRIBUTOR_ADDRESS");
        address tokenAddr = vm.envAddress("TOKEN_ADDRESS");
        uint256 ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");

        // Load from environment or JSON
        bytes32 merkleRoot = vm.envBytes32("MERKLE_ROOT");
        uint256 totalYield = vm.envUint("TOTAL_YIELD");
        uint256 startTime = vm.envUint("START_TIME");
        uint256 endTime = vm.envUint("END_TIME");

        vm.startBroadcast(ownerPrivateKey);

        MerkleDistributor distributor = MerkleDistributor(distributorAddr);
        IERC20 token = IERC20(tokenAddr);

        // Transfer tokens to distributor
        console.log("Transferring tokens...");
        token.transfer(distributorAddr, totalYield);

        // Create distribution
        console.log("Creating distribution...");
        uint256 distId = distributor.createDistribution(merkleRoot, totalYield, tokenAddr, startTime, endTime);

        vm.stopBroadcast();

        console.log("Distribution created with ID:", distId);
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Total yield:", totalYield);
    }
}
