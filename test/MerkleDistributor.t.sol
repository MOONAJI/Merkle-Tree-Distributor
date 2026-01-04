// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MerkleDistributor.sol";
import "../src/mocks/MockERC20.sol";
import "./Utils/MerkleTreeHelper.sol";

contract MerkleDistributorTest is Test, MerkleTreeHelper {
    MerkleDistributor public distributor;
    MockERC20 public token;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    uint256 constant AMOUNT_USER1 = 100 ether;
    uint256 constant AMOUNT_USER2 = 200 ether;
    uint256 constant AMOUNT_USER3 = 300 ether;
    uint256 constant TOTAL_AMOUNT = 600 ether;

    bytes32 public merkleRoot;
    bytes32[] public proofUser1;
    bytes32[] public proofUser2;
    bytes32[] public proofUser3;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.startPrank(owner);

        // Deploy contracts
        distributor = new MerkleDistributor();
        token = new MockERC20("Test Token", "TEST");

        // Prepare allocations
        Allocation[] memory allocations = new Allocation[](3);
        allocations[0] = Allocation(user1, AMOUNT_USER1);
        allocations[1] = Allocation(user2, AMOUNT_USER2);
        allocations[2] = Allocation(user3, AMOUNT_USER3);

        // Build merkle tree
        (merkleRoot, proofUser1, proofUser2, proofUser3) = buildTree(allocations);

        // Fund distributor
        token.mint(address(distributor), TOTAL_AMOUNT);

        // Create distribution
        distributor.createDistribution(
            merkleRoot, TOTAL_AMOUNT, address(token), block.timestamp, block.timestamp + 30 days
        );

        vm.stopPrank();
    }

    function test_ValidClaim() public {
        vm.prank(user1);
        distributor.claim(0, AMOUNT_USER1, proofUser1);

        assertEq(token.balanceOf(user1), AMOUNT_USER1);
        assertTrue(distributor.hasClaimed(0, user1));
    }

    function test_RevertDoubleClaim() public {
        vm.startPrank(user1);
        distributor.claim(0, AMOUNT_USER1, proofUser1);

        vm.expectRevert(MerkleDistributor.AlreadyClaimed.selector);
        distributor.claim(0, AMOUNT_USER1, proofUser1);
        vm.stopPrank();
    }

    function test_RevertInvalidProof() public {
        bytes32[] memory fakeProof = new bytes32[](1);
        fakeProof[0] = bytes32(uint256(1));

        vm.prank(user1);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        distributor.claim(0, AMOUNT_USER1, fakeProof);
    }

    function test_RevertInvalidAmount() public {
        vm.prank(user1);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        distributor.claim(0, AMOUNT_USER2, proofUser1); // Wrong amount
    }

    function test_BatchClaim() public {
        // Batch claim only user's own allocation (single-entry batch)
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        bytes32[][] memory proofs = new bytes32[][](1);

        ids[0] = 0;
        amounts[0] = AMOUNT_USER1;
        proofs[0] = proofUser1;

        vm.prank(user1);
        distributor.claimMultiple(ids, amounts, proofs);

        assertEq(token.balanceOf(user1), AMOUNT_USER1);
    }
}
