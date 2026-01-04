// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MerkleDistributor.sol";
import "../src/mocks/MockERC20.sol";

/**
 * FUZZ TESTS - MerkleDistributor
 * ===============================
 *
 * Fuzz testing menggunakan random inputs untuk menemukan edge cases
 * dan vulnerabilities yang tidak terdeteksi di unit tests.
 *
 * Foundry akan run setiap test dengan random inputs (default: 256 runs)
 * Gunakan: forge test --fuzz-runs 10000 untuk more comprehensive testing
 */

contract MerkleDistributorFuzzTest is Test {
    MerkleDistributor public distributor;
    MockERC20 public token;

    address public owner;
    address public alice;
    address public bob;

    bytes32 public validMerkleRoot;
    uint256 public constant DISTRIBUTION_AMOUNT = 1000 ether;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.startPrank(owner);

        distributor = new MerkleDistributor();
        token = new MockERC20("Test Token", "TEST");

        // Create a valid merkle root for testing
        validMerkleRoot = keccak256(abi.encodePacked("valid_root"));

        // Fund distributor
        token.mint(address(distributor), DISTRIBUTION_AMOUNT * 10);

        // Create initial distribution
        distributor.createDistribution(
            validMerkleRoot, DISTRIBUTION_AMOUNT, address(token), block.timestamp, block.timestamp + 365 days
        );

        vm.stopPrank();
    }

    // ============================================
    // FUZZ: CREATE DISTRIBUTION
    // ============================================

    /**
     * Fuzz test: CreateDistribution dengan random parameters
     * Memastikan contract handle semua input combinations dengan benar
     */
    function testFuzz_CreateDistribution(bytes32 merkleRoot, uint256 totalYield, uint256 startTime, uint256 duration)
        public
    {
        // Bound inputs to valid ranges
        vm.assume(merkleRoot != bytes32(0));
        totalYield = bound(totalYield, 1, type(uint128).max);
        startTime = bound(startTime, block.timestamp, block.timestamp + 365 days);
        duration = bound(duration, 1 days, 365 days);

        uint256 endTime = startTime + duration;

        vm.startPrank(owner);

        // Mint tokens
        token.mint(address(distributor), totalYield);

        // Should succeed with valid parameters
        uint256 distId = distributor.createDistribution(merkleRoot, totalYield, address(token), startTime, endTime);

        vm.stopPrank();

        // Verify distribution was created correctly
        (
            bytes32 storedRoot,
            uint256 storedYield,
            address storedToken,
            bool active,
            uint256 claimedAmount,
            uint256 storedStart,
            uint256 storedEnd
        ) = distributor.distributions(distId);

        assertEq(storedRoot, merkleRoot);
        assertEq(storedYield, totalYield);
        assertEq(storedToken, address(token));
        assertTrue(active);
        assertEq(claimedAmount, 0);
        assertEq(storedStart, startTime);
        assertEq(storedEnd, endTime);
    }

    /**
     * Fuzz test: Invalid merkle root (bytes32(0)) should revert
     */
    function testFuzz_RevertWhen_InvalidMerkleRoot(uint256 totalYield, uint256 startTime, uint256 duration) public {
        totalYield = bound(totalYield, 1, type(uint128).max);
        startTime = bound(startTime, block.timestamp, block.timestamp + 365 days);
        duration = bound(duration, 1 days, 365 days);

        vm.startPrank(owner);
        token.mint(address(distributor), totalYield);

        vm.expectRevert(MerkleDistributor.InvalidAmount.selector);
        distributor.createDistribution(
            bytes32(0), // Invalid root
            totalYield,
            address(token),
            startTime,
            startTime + duration
        );

        vm.stopPrank();
    }

    /**
     * Fuzz test: Zero totalYield should revert
     */
    function testFuzz_RevertWhen_ZeroTotalYield(bytes32 merkleRoot, uint256 startTime, uint256 duration) public {
        vm.assume(merkleRoot != bytes32(0));
        startTime = bound(startTime, block.timestamp, block.timestamp + 365 days);
        duration = bound(duration, 1 days, 365 days);

        vm.prank(owner);
        vm.expectRevert(MerkleDistributor.InvalidAmount.selector);
        distributor.createDistribution(
            merkleRoot,
            0, // Zero amount
            address(token),
            startTime,
            startTime + duration
        );
    }

    /**
     * Fuzz test: Invalid time window should revert
     */
    function testFuzz_RevertWhen_EndTimeBeforeStartTime(
        bytes32 merkleRoot,
        uint256 totalYield,
        uint256 startTime,
        uint256 endTime
    ) public {
        vm.assume(merkleRoot != bytes32(0));
        totalYield = bound(totalYield, 1, type(uint128).max);
        startTime = bound(startTime, block.timestamp, type(uint32).max);
        endTime = bound(endTime, block.timestamp, startTime); // endTime <= startTime

        vm.assume(endTime <= startTime);

        vm.startPrank(owner);
        token.mint(address(distributor), totalYield);

        vm.expectRevert(MerkleDistributor.InvalidTimeWindow.selector);
        distributor.createDistribution(merkleRoot, totalYield, address(token), startTime, endTime);

        vm.stopPrank();
    }

    // ============================================
    // FUZZ: CLAIM FUNCTION
    // ============================================

    /**
     * Fuzz test: Claim dengan random amount dan proof
     * Semua invalid claims harus revert
     */
    function testFuzz_ClaimWithRandomProof(
        address claimer,
        uint256 amount,
        bytes32 proof1,
        bytes32 proof2,
        bytes32 proof3
    ) public {
        // Bound inputs
        vm.assume(claimer != address(0));
        vm.assume(claimer != address(distributor));
        vm.assume(claimer != address(token));
        amount = bound(amount, 1, DISTRIBUTION_AMOUNT);

        bytes32[] memory proof = new bytes32[](3);
        proof[0] = proof1;
        proof[1] = proof2;
        proof[2] = proof3;

        // Random proof should fail (extremely unlikely to be valid)
        vm.prank(claimer);
        vm.expectRevert(); // Will revert with InvalidProof or InvalidAmount
        distributor.claim(0, amount, proof);

        // Verify no tokens were transferred
        assertEq(token.balanceOf(claimer), 0);
        assertFalse(distributor.hasClaimed(0, claimer));
    }

    /**
     * Fuzz test: Zero amount should always revert
     */
    function testFuzz_RevertWhen_ZeroAmount(address claimer, bytes32[] calldata proof) public {
        vm.assume(claimer != address(0));

        vm.prank(claimer);
        vm.expectRevert(MerkleDistributor.InvalidAmount.selector);
        distributor.claim(0, 0, proof);
    }

    /**
     * Fuzz test: Claim dari inactive distribution
     */
    function testFuzz_RevertWhen_DistributionInactive(address claimer, uint256 amount, bytes32[] calldata proof)
        public
    {
        vm.assume(claimer != address(0));
        amount = bound(amount, 1, DISTRIBUTION_AMOUNT);

        // Deactivate distribution
        vm.prank(owner);
        distributor.setDistributionActive(0, false);

        vm.prank(claimer);
        vm.expectRevert(MerkleDistributor.DistributionNotActive.selector);
        distributor.claim(0, amount, proof);
    }

    /**
     * Fuzz test: Claim before start time
     */
    function testFuzz_RevertWhen_BeforeStartTime(address claimer, uint256 amount, uint256 startOffset) public {
        vm.assume(claimer != address(0));
        amount = bound(amount, 1, DISTRIBUTION_AMOUNT);
        startOffset = bound(startOffset, 1 hours, 30 days);

        vm.startPrank(owner);
        token.mint(address(distributor), DISTRIBUTION_AMOUNT);

        uint256 futureStart = block.timestamp + startOffset;
        distributor.createDistribution(
            validMerkleRoot, DISTRIBUTION_AMOUNT, address(token), futureStart, futureStart + 30 days
        );
        vm.stopPrank();

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(claimer);
        vm.expectRevert(MerkleDistributor.DistributionNotStarted.selector);
        distributor.claim(1, amount, proof);
    }

    /**
     * Fuzz test: Claim after end time
     */
    function testFuzz_RevertWhen_AfterEndTime(address claimer, uint256 amount, uint256 warpTime) public {
        vm.assume(claimer != address(0));
        amount = bound(amount, 1, DISTRIBUTION_AMOUNT);
        warpTime = bound(warpTime, 366 days, 500 days);

        // Warp past end time
        vm.warp(block.timestamp + warpTime);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(claimer);
        vm.expectRevert(MerkleDistributor.DistributionEnded.selector);
        distributor.claim(0, amount, proof);
    }

    /**
     * Fuzz test: Invalid distribution ID
     */
    function testFuzz_RevertWhen_InvalidDistributionId(address claimer, uint256 amount, uint256 invalidId) public {
        vm.assume(claimer != address(0));
        amount = bound(amount, 1, DISTRIBUTION_AMOUNT);
        invalidId = bound(invalidId, 10, type(uint256).max);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(claimer);
        vm.expectRevert(MerkleDistributor.InvalidDistribution.selector);
        distributor.claim(invalidId, amount, proof);
    }

    // ============================================
    // FUZZ: BATCH CLAIM
    // ============================================

    /**
     * Fuzz test: Batch claim dengan varying array lengths
     */
    function testFuzz_BatchClaimArrayLengths(uint8 arrayLength) public {
        // Bound to reasonable size (1-20 distributions)
        arrayLength = uint8(bound(arrayLength, 1, 20));

        uint256[] memory ids = new uint256[](arrayLength);
        uint256[] memory amounts = new uint256[](arrayLength);
        bytes32[][] memory proofs = new bytes32[][](arrayLength);

        for (uint256 i = 0; i < arrayLength; i++) {
            ids[i] = 0;
            amounts[i] = 1 ether;
            proofs[i] = new bytes32[](1);
            proofs[i][0] = bytes32(i);
        }

        // Should revert due to invalid proofs, but not due to array handling
        vm.prank(alice);
        vm.expectRevert(); // InvalidProof expected
        distributor.claimMultiple(ids, amounts, proofs);
    }

    /**
     * Fuzz test: Batch claim dengan mismatched array lengths
     */
    function testFuzz_RevertWhen_MismatchedArrayLengths(uint8 idsLength, uint8 amountsLength, uint8 proofsLength)
        public
    {
        idsLength = uint8(bound(idsLength, 1, 10));
        amountsLength = uint8(bound(amountsLength, 1, 10));
        proofsLength = uint8(bound(proofsLength, 1, 10));

        // Only test when lengths are different
        vm.assume(idsLength != amountsLength || idsLength != proofsLength || amountsLength != proofsLength);

        uint256[] memory ids = new uint256[](idsLength);
        uint256[] memory amounts = new uint256[](amountsLength);
        bytes32[][] memory proofs = new bytes32[][](proofsLength);

        vm.prank(alice);
        vm.expectRevert("Array length mismatch");
        distributor.claimMultiple(ids, amounts, proofs);
    }

    // ============================================
    // FUZZ: TIME MANIPULATION
    // ============================================

    /**
     * Fuzz test: Time window boundaries
     * Test behavior at various points in distribution lifecycle
     */
    function testFuzz_TimeWindowBoundaries(uint256 startOffset, uint256 duration, uint256 claimTime) public {
        startOffset = bound(startOffset, 1 hours, 30 days);
        duration = bound(duration, 1 days, 365 days);
        claimTime = bound(claimTime, 0, 400 days);

        vm.startPrank(owner);
        token.mint(address(distributor), DISTRIBUTION_AMOUNT);

        uint256 startTime = block.timestamp + startOffset;
        uint256 endTime = startTime + duration;

        uint256 distId =
            distributor.createDistribution(validMerkleRoot, DISTRIBUTION_AMOUNT, address(token), startTime, endTime);
        vm.stopPrank();

        // Warp to claim time
        vm.warp(block.timestamp + claimTime);

        // Check if distribution should be claimable
        bool shouldBeClaimable = block.timestamp >= startTime && block.timestamp <= endTime;

        assertEq(distributor.isClaimable(distId), shouldBeClaimable);
    }

    /**
     * Fuzz test: Block timestamp manipulation resistance
     */
    function testFuzz_BlockTimestampManipulation(uint256 timestamp) public {
        timestamp = bound(timestamp, block.timestamp, type(uint32).max);

        vm.warp(timestamp);

        // Distribution created at current timestamp should work
        vm.startPrank(owner);
        token.mint(address(distributor), DISTRIBUTION_AMOUNT);

        if (timestamp + 1 days <= type(uint32).max) {
            distributor.createDistribution(
                validMerkleRoot, DISTRIBUTION_AMOUNT, address(token), timestamp, timestamp + 1 days
            );

            // Should be claimable at current time
            assertTrue(distributor.isClaimable(distributor.distributionCount() - 1));
        }

        vm.stopPrank();
    }

    // ============================================
    // FUZZ: AMOUNT BOUNDARIES
    // ============================================

    /**
     * Fuzz test: Extreme amount values
     */
    function testFuzz_ExtremeAmounts(uint256 amount) public {
        // Test from 1 wei to max uint128
        amount = bound(amount, 1, type(uint128).max);

        vm.startPrank(owner);

        // Try to mint (might fail if amount too large)
        try token.mint(address(distributor), amount) {
            distributor.createDistribution(
                validMerkleRoot, amount, address(token), block.timestamp, block.timestamp + 30 days
            );

            // Verify distribution was created
            (, uint256 storedAmount,,,,,) = distributor.distributions(distributor.distributionCount() - 1);
            assertEq(storedAmount, amount);
        } catch {
            // If mint fails, that's expected for very large amounts
        }

        vm.stopPrank();
    }

    /**
     * Fuzz test: Amount precision (wei level)
     */
    function testFuzz_AmountPrecision(uint256 amount) public {
        // Test amounts including odd wei values
        amount = bound(amount, 1, 1000 ether);

        bytes32 leaf1 = keccak256(abi.encodePacked(alice, amount));
        bytes32 leaf2 = keccak256(abi.encodePacked(alice, amount + 1));

        // Even 1 wei difference should create different leaf
        assertNotEq(leaf1, leaf2);
    }

    // ============================================
    // FUZZ: ADDRESS VALIDATION
    // ============================================

    /**
     * Fuzz test: Various address inputs
     */
    function testFuzz_AddressValidation(address claimer) public {
        // Filter out special addresses
        vm.assume(claimer != address(0));
        vm.assume(claimer != address(distributor));
        vm.assume(claimer != address(token));
        vm.assume(claimer.code.length == 0); // Not a contract

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(uint256(1));

        // Should revert with InvalidProof (not with address validation)
        vm.prank(claimer);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        distributor.claim(0, 1 ether, proof);
    }

    /**
     * Fuzz test: Contract addresses as claimers
     */
    function testFuzz_ContractClaimers() public {
        // Deploy a tiny contract and use its address as caller
        DummyCaller d = new DummyCaller();

        bytes32[] memory proof = new bytes32[](1);

        vm.prank(address(d));
        vm.expectRevert(); // Should revert (InvalidProof or other)
        distributor.claim(0, 1 ether, proof);
    }

    // ============================================
    // FUZZ: MERKLE PROOF STRUCTURE
    // ============================================

    /**
     * Fuzz test: Proof array length variations
     */
    function testFuzz_ProofArrayLength(uint8 proofLength) public {
        proofLength = uint8(bound(proofLength, 0, 32)); // Max reasonable depth

        bytes32[] memory proof = new bytes32[](proofLength);
        for (uint256 i = 0; i < proofLength; i++) {
            proof[i] = bytes32(i);
        }

        vm.prank(alice);
        vm.expectRevert(); // Invalid proof expected
        distributor.claim(0, 1 ether, proof);
    }

    /**
     * Fuzz test: Duplicate proof elements
     */
    function testFuzz_DuplicateProofElements(bytes32 proofElement) public {
        bytes32[] memory proof = new bytes32[](5);
        // All same element
        for (uint256 i = 0; i < 5; i++) {
            proof[i] = proofElement;
        }

        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        distributor.claim(0, 1 ether, proof);
    }

    // ============================================
    // FUZZ: STATE CONSISTENCY
    // ============================================

    /**
     * Fuzz test: Distribution state remains consistent
     */
    function testFuzz_DistributionStateConsistency(uint256 numOperations) public {
        numOperations = bound(numOperations, 1, 20);

        for (uint256 i = 0; i < numOperations; i++) {
            // Get initial state
            (
                bytes32 rootBefore,
                uint256 yieldBefore,
                address tokenBefore,
                bool activeBefore,
                uint256 claimedBefore,
                uint256 startBefore,
                uint256 endBefore
            ) = distributor.distributions(0);

            // Try random operation (will likely fail)
            bytes32[] memory proof = new bytes32[](1);
            vm.prank(makeAddr(string(abi.encodePacked("user", i))));
            try distributor.claim(0, 1 ether, proof) {} catch {}

            // Get state after
            (
                bytes32 rootAfter,
                uint256 yieldAfter,
                address tokenAfter,
                bool activeAfter,
                uint256 claimedAfter,
                uint256 startAfter,
                uint256 endAfter
            ) = distributor.distributions(0);

            // Core parameters should never change
            assertEq(rootBefore, rootAfter);
            assertEq(yieldBefore, yieldAfter);
            assertEq(tokenBefore, tokenAfter);
            assertEq(startBefore, startAfter);
            assertEq(endBefore, endAfter);

            // ClaimedAmount should only increase or stay same
            assertGe(claimedAfter, claimedBefore);
        }
    }

    /**
     * Fuzz test: Total supply conservation
     * (contract balance + claimed amount = total yield)
     */
    function testFuzz_TotalSupplyConservation(uint256 seed) public {
        // Get distribution state
        (, uint256 totalYield,,, uint256 claimedAmount,,) = distributor.distributions(0);

        uint256 contractBalance = token.balanceOf(address(distributor));

        // Total should be conserved
        // contractBalance + claimedAmount should equal totalYield (for dist 0)
        // Note: Contract might hold tokens for multiple distributions
        assertGe(contractBalance + claimedAmount, totalYield);
    }
}

contract DummyCaller {
    fallback() external payable {}
}
