// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

contract MerkleTreeHelper is Test {
    struct Allocation {
        address user;
        uint256 amount;
    }
    
    function buildTree(
        Allocation[] memory allocations
    ) internal pure returns (
        bytes32 root,
        bytes32[] memory proof1,
        bytes32[] memory proof2,
        bytes32[] memory proof3
    ) {
        // Simplified: In real tests, use merkletreejs via FFI
        // For Foundry, you can use Murky library
        bytes32[] memory leaves = new bytes32[](allocations.length);
        
        for (uint256 i = 0; i < allocations.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(
                allocations[i].user,
                allocations[i].amount
            ));
        }
        
        // Build tree (simplified example)
        // In production, use proper merkle tree library
        if (leaves.length == 3) {
            bytes32 left = _hashPair(leaves[0], leaves[1]);
            root = _hashPair(left, leaves[2]);
            
            proof1 = new bytes32[](2);
            proof1[0] = leaves[1];
            proof1[1] = leaves[2];
            
            proof2 = new bytes32[](2);
            proof2[0] = leaves[0];
            proof2[1] = leaves[2];
            
            proof3 = new bytes32[](1);
            proof3[0] = left;
        }
    }
    
    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}