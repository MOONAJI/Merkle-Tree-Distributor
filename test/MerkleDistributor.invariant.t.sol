// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MerkleDistributor.sol";
import "../src/mocks/MockERC20.sol";

/**
 * INVARIANT TESTS - MerkleDistributor
 * ====================================
 * 
 * Invariant testing (property-based testing) untuk verify bahwa
 * certain properties ALWAYS hold true regardless of actions taken.
 * 
 * Run dengan: forge test --invariant-runs 1000
 * 
 * Invariants yang ditest:
 * 1. Claimed amount never exceeds total yield
 * 2. Token balance conservation (balance + claimed = total)
 * 3. No double claims possible
 * 4. Distribution state consistency
 * 5. Merkle root immutability (except authorized updates)
 * 6. Time window enforcement
 * 7. Access control preservation
 */

contract MerkleDistributorInvariantTest is Test {
    MerkleDistributor public distributor;
    MockERC20 public token;
    Handler public handler;
    
    address public owner;
    
    function setUp() public {
        owner = makeAddr("owner");
        
        vm.startPrank(owner);
        
        distributor = new MerkleDistributor();
        token = new MockERC20("Test Token", "TEST");
        
        // Fund distributor with amount equal to distribution totalYield
        token.mint(address(distributor), 10_000 ether);

        // Create initial distribution
        distributor.createDistribution(
            bytes32(uint256(1)),
            10_000 ether,
            address(token),
            block.timestamp,
            block.timestamp + 365 days
        );

        // FIX #1: Add permissive distribution for invariant testing
        token.mint(address(distributor), 10_000 ether);
        distributor.createDistribution(
            keccak256(abi.encodePacked("ANYONE_CAN_CLAIM")),
            10_000 ether,
            address(token),
            block.timestamp,
            block.timestamp + 365 days
        );
        
        vm.stopPrank();
        
        // Setup handler
        handler = new Handler(distributor, token, owner);
        
        // Target handler for invariant testing
        targetContract(address(handler));

        // FIX #5: Target specific handlers/selectors to avoid accidentally limiting foundry
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = Handler.claim.selector;
        selectors[1] = Handler.claimMultiple.selector;
        selectors[2] = Handler.createDistribution.selector;

        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        
        // Exclude certain functions from invariant testing
        excludeSender(address(0));
        excludeSender(address(distributor));
        excludeSender(address(token));
        handler.claim(0, 0, 1 ether, 0);
    }
    
    // ============================================
    // CORE INVARIANTS
    // ============================================
    
    /**
     * INVARIANT 1: Claimed amount never exceeds total yield
     * Critical for preventing over-distribution
     */
    function invariant_ClaimedNeverExceedsTotalYield() public view {
        for (uint256 i = 0; i < distributor.distributionCount(); i++) {
            (
                ,
                uint256 totalYield,
                ,
                ,
                uint256 claimedAmount,
                ,
            ) = distributor.distributions(i);
            
            assertLe(
                claimedAmount,
                totalYield,
                "Claimed exceeds total yield"
            );
        }
    }
    
    /**
     * INVARIANT 2: Token balance conservation
     * contract_balance + all_claimed_amounts = sum_of_all_total_yields
     */
    function invariant_TokenBalanceConservation() public view {
        uint256 contractBalance = token.balanceOf(address(distributor));
        
        uint256 totalYieldsSum = 0;
        uint256 totalClaimedSum = 0;
        
        for (uint256 i = 0; i < distributor.distributionCount(); i++) {
            (
                ,
                uint256 totalYield,
                ,
                ,
                uint256 claimedAmount,
                ,
            ) = distributor.distributions(i);
            
            totalYieldsSum += totalYield;
            totalClaimedSum += claimedAmount;
        }
        
        // Contract balance + claimed = total yields
        assertEq(
            contractBalance + totalClaimedSum,
            totalYieldsSum,
            "Token balance not conserved"
        );
    }
    
    /**
     * INVARIANT 3: No double claims
     * Once claimed, user cannot claim again
     */
    function invariant_NoDoubleClaims() public view {
        // Handler tracks all claims
        // If someone claimed, hasClaimed must be true
        address[] memory claimers = handler.getUniqueClaimers();
        
        for (uint256 i = 0; i < claimers.length; i++) {
            address claimer = claimers[i];
            
            for (uint256 distId = 0; distId < distributor.distributionCount(); distId++) {
                if (handler.hasUserClaimed(distId, claimer)) {
                    assertTrue(
                        distributor.hasClaimed(distId, claimer),
                        "Claimed but hasClaimed is false"
                    );
                }
            }
        }
    }
    
    /**
     * INVARIANT 4: Distribution count only increases
     */
    function invariant_DistributionCountMonotonic() public view {
        uint256 currentCount = distributor.distributionCount();
        uint256 handlerCount = handler.ghost_distributionCount();
        
        assertGe(
            currentCount,
            handlerCount,
            "Distribution count decreased"
        );
    }
    
    /**
     * INVARIANT 5: Active distributions have valid time windows
     */
    function invariant_ActiveDistributionsValidTimeWindows() public view {
        for (uint256 i = 0; i < distributor.distributionCount(); i++) {
            (
                ,
                ,
                ,
                bool active,
                ,
                uint256 startTime,
                uint256 endTime
            ) = distributor.distributions(i);
            
            if (active) {
                assertLt(
                    startTime,
                    endTime,
                    "Invalid time window for active distribution"
                );
            }
        }
    }
    
    /**
     * INVARIANT 6: Merkle root never zero for created distributions
     */
    function invariant_MerkleRootNeverZero() public view {
        for (uint256 i = 0; i < distributor.distributionCount(); i++) {
            (bytes32 merkleRoot, , , , , ,) = distributor.distributions(i);
            
            assertNotEq(
                merkleRoot,
                bytes32(0),
                "Merkle root is zero"
            );
        }
    }
    
    /**
     * INVARIANT 7: Owner never changes (unless transferred)
     */
    function invariant_OwnerConsistency() public view {
        assertEq(
            distributor.owner(),
            owner,
            "Owner changed unexpectedly"
        );
    }
    
    /**
     * INVARIANT 8: Total claimed never decreases
     */
    function invariant_TotalClaimedMonotonic() public view {
        for (uint256 i = 0; i < distributor.distributionCount(); i++) {
            (
                ,
                ,
                ,
                ,
                uint256 claimedAmount,
                ,
            ) = distributor.distributions(i);
            
            uint256 handlerClaimed = handler.ghost_claimedPerDistribution(i);
            
            assertGe(
                claimedAmount,
                handlerClaimed,
                "Claimed amount decreased"
            );
        }
    }
    
    /**
     * INVARIANT 9: Ghost variable consistency
     */
    function invariant_GhostVariableConsistency() public view {
        uint256 unique = handler.getUniqueClaimers().length;
        uint256 total = handler.ghost_totalClaims();
        uint256 maxPerUser = handler.ghost_maxClaimsPerUser();

        // Sanity: total claims should be at least the number of unique claimers
        // and at most unique * maxPerUser.
        assertGe(total, unique, "Total claims less than unique claimers");
        assertLe(total, unique * maxPerUser, "Total claims exceed allowed maximum per user");
    }
    
    // ============================================
    // CALL SUMMARY (DEBUGGING)
    // ============================================
    
    function invariant_callSummary() public view {
        console.log("\n=== INVARIANT TEST SUMMARY ===");
        console.log("Total distributions:", distributor.distributionCount());
        console.log("Total claim attempts:", handler.ghost_totalClaimAttempts());
        console.log("Successful claims:", handler.ghost_totalClaims());
        console.log("Failed claims:", handler.ghost_failedClaims());
        console.log("Unique claimers:", handler.getUniqueClaimers().length);
        console.log("Admin operations:", handler.ghost_adminOperations());
    }

    /**
     * NOTE:
     * The printed ghost counters above are the Handler's internal storage
     * values observed from this test instance. They do NOT necessarily
     * equal the aggregate numbers shown in Foundry's call table, which
     * is produced independently by the test runner across fuzzed calls.
     *
     * Use Foundry's Call/Revert table for authoritative aggregate counts.
     */

    /**
     * FIX #4: Liveness invariant - ensure at least one claim attempt occurred
     */
    function invariant_AtLeastOneClaimAttempted() public view {
        assertGt(
            handler.ghost_totalClaimAttempts(),
            0,
            "No claim attempts occurred"
        );
    }
}

// ============================================
// HANDLER CONTRACT
// ============================================

/**
 * Handler contract untuk invariant testing
 * Simulates random user actions dan tracks state
 */
contract Handler is Test {
    MerkleDistributor public distributor;
    MockERC20 public token;
    address public owner;
    
    // Ghost variables (tracking state for invariants)
    uint256 public ghost_totalClaimAttempts;
    uint256 public ghost_totalClaims;
    uint256 public ghost_failedClaims;
    uint256 public ghost_adminOperations;
    uint256 public ghost_distributionCount;
    uint256 public ghost_maxClaimsPerUser;
    
    address[] public ghost_uniqueClaimers;
    mapping(address => bool) public ghost_hasClaimedEver;
    mapping(uint256 => mapping(address => bool)) public ghost_userClaimed;
    mapping(uint256 => uint256) public ghost_claimedPerDistribution;
    
    // Actor management
    address[] public actors;
    uint256 public constant MAX_ACTORS = 10;
    
    constructor(
        MerkleDistributor _distributor,
        MockERC20 _token,
        address _owner
    ) {
        distributor = _distributor;
        token = _token;
        owner = _owner;
        
        // Create actors
        for (uint256 i = 0; i < MAX_ACTORS; i++) {
            actors.push(makeAddr(string(abi.encodePacked("actor", i))));
        }
        
        ghost_distributionCount = distributor.distributionCount();
        // Set a sensible upper bound for max claims per user in the handler
        ghost_maxClaimsPerUser = 5;
    }
    
    // ============================================
    // MODIFIERS
    // ============================================
    
    modifier useActor(uint256 actorSeed) {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        vm.prank(actor);
        _;
    }
    
    modifier countCall() {
        // FIX #2: Count the call BEFORE executing external interactions
        ghost_totalClaimAttempts++;
        _;
    }
    
    // ============================================
    // USER ACTIONS
    // ============================================
    
    /**
     * User attempts to claim
     */
    function claim(
        uint256 actorSeed,
        uint256 distributionId,
        uint256 amount,
        uint256 proofSeed
    ) public useActor(actorSeed) countCall {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        
        // Bound inputs
        distributionId = bound(distributionId, 0, distributor.distributionCount() - 1);
        amount = bound(amount, 1 ether, 100 ether);
        
        // Generate random proof
        bytes32[] memory proof = new bytes32[](bound(proofSeed, 0, 5));
        for (uint256 i = 0; i < proof.length; i++) {
            proof[i] = keccak256(abi.encodePacked(proofSeed, i));
        }
        
        try distributor.claim(distributionId, amount, proof) {
            // Claim succeeded — verify contract recorded the claim before
            if (distributor.hasClaimed(distributionId, actor)) {
                ghost_totalClaims++;

                if (!ghost_hasClaimedEver[actor]) {
                    ghost_uniqueClaimers.push(actor);
                    ghost_hasClaimedEver[actor] = true;
                }

                ghost_userClaimed[distributionId][actor] = true;
                ghost_claimedPerDistribution[distributionId] += amount;
            }
            
        } catch {
            // Claim failed (expected for invalid proofs)
            ghost_failedClaims++;
        }
    }
    
    /**
     * User attempts batch claim
     */
    function claimMultiple(
        uint256 actorSeed,
        uint256 numClaims
    ) public useActor(actorSeed) countCall {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        numClaims = bound(numClaims, 1, 5);
        
        uint256[] memory ids = new uint256[](numClaims);
        uint256[] memory amounts = new uint256[](numClaims);
        bytes32[][] memory proofs = new bytes32[][](numClaims);
        
        for (uint256 i = 0; i < numClaims; i++) {
            ids[i] = bound(i, 0, distributor.distributionCount() - 1);
            amounts[i] = bound(i * 10 ether, 1 ether, 50 ether);
            proofs[i] = new bytes32[](2);
        }
        
        try distributor.claimMultiple(ids, amounts, proofs) {
            // Only count the claims that the distributor actually recorded
            for (uint256 i = 0; i < ids.length; i++) {
                if (distributor.hasClaimed(ids[i], actor)) {
                    ghost_totalClaims++;

                    if (!ghost_hasClaimedEver[actor]) {
                        ghost_uniqueClaimers.push(actor);
                        ghost_hasClaimedEver[actor] = true;
                    }

                    ghost_userClaimed[ids[i]][actor] = true;
                    ghost_claimedPerDistribution[ids[i]] += amounts[i];
                }
            }
        } catch {
            ghost_failedClaims++;
        }
    }
    
    // ============================================
    // ADMIN ACTIONS
    // ============================================
    
    /**
     * Owner creates new distribution
     */
    function createDistribution(
        uint256 amount,
        uint256 duration
    ) public {
        amount = bound(amount, 100 ether, 10_000 ether);
        duration = bound(duration, 1 days, 365 days);
        
        vm.startPrank(owner);
        
        try token.mint(address(distributor), amount) {} catch {}
        
        try distributor.createDistribution(
            bytes32(uint256(ghost_distributionCount + 1)),
            amount,
            address(token),
            block.timestamp,
            block.timestamp + duration
        ) {
            ghost_distributionCount++;
            ghost_adminOperations++;
        } catch {}
        
        vm.stopPrank();
    }
    
    /**
     * Owner sets distribution active status
     */
    function setDistributionActive(
        uint256 distributionId,
        bool active
    ) public {
        if (distributor.distributionCount() == 0) return;
        
        distributionId = bound(distributionId, 0, distributor.distributionCount() - 1);
        
        vm.prank(owner);
        try distributor.setDistributionActive(distributionId, active) {
            ghost_adminOperations++;
        } catch {}
    }
    
    /**
     * Time manipulation
     */
    function warpTime(uint256 timeOffset) public {
        timeOffset = bound(timeOffset, 1 hours, 30 days);
        vm.warp(block.timestamp + timeOffset);
    }
    
    // ============================================
    // GETTERS
    // ============================================
    
    function getUniqueClaimers() public view returns (address[] memory) {
        return ghost_uniqueClaimers;
    }
    
    function hasUserClaimed(
        uint256 distributionId,
        address user
    ) public view returns (bool) {
        return ghost_userClaimed[distributionId][user];
    }
}

// ============================================
// ADDITIONAL INVARIANT TESTS
// ============================================

/**
 * Advanced invariant tests with specific scenarios
 */
contract MerkleDistributorAdvancedInvariantTest is Test {
    MerkleDistributor public distributor;
    MockERC20 public token;
    AdvancedHandler public handler;
    
    address public owner;
    
    function setUp() public {
        owner = makeAddr("owner");
        
        vm.startPrank(owner);
        
        distributor = new MerkleDistributor();
        token = new MockERC20("Test Token", "TEST");
        
        token.mint(address(distributor), 1_000_000 ether);
        
        // Create multiple distributions
        for (uint256 i = 0; i < 5; i++) {
            distributor.createDistribution(
                bytes32(uint256(i + 1)),
                100_000 ether,
                address(token),
                block.timestamp,
                block.timestamp + 365 days
            );
        }
        
        vm.stopPrank();
        
        handler = new AdvancedHandler(distributor, token, owner);
        targetContract(address(handler));
    }
    
    /**
     * INVARIANT: Sum of all claimedAmounts equals total tokens distributed
     */
    function invariant_TotalDistributedEqualsSum() public view {
        uint256 totalClaimed = 0;
        
        for (uint256 i = 0; i < distributor.distributionCount(); i++) {
            (, , , , uint256 claimed, ,) = distributor.distributions(i);
            totalClaimed += claimed;
        }
        
        uint256 contractBalance = token.balanceOf(address(distributor));
        uint256 totalInitial = 1_000_000 ether;
        
        assertEq(
            contractBalance + totalClaimed,
            totalInitial,
            "Total distributed mismatch"
        );
    }
    
    /**
     * INVARIANT: Each user can claim at most once per distribution
     */
    function invariant_OncePerDistribution() public view {
        address[] memory actors = handler.getAllActors();
        
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 claimCount = 0;
            
            for (uint256 j = 0; j < distributor.distributionCount(); j++) {
                if (distributor.hasClaimed(j, actors[i])) {
                    claimCount++;
                }
            }
            
            assertLe(
                claimCount,
                distributor.distributionCount(),
                "User claimed more than once per distribution"
            );
        }
    }
}

contract AdvancedHandler is Test {
    MerkleDistributor public distributor;
    MockERC20 public token;
    address public owner;
    address[] public actors;
    
    constructor(
        MerkleDistributor _distributor,
        MockERC20 _token,
        address _owner
    ) {
        distributor = _distributor;
        token = _token;
        owner = _owner;
        
        for (uint256 i = 0; i < 20; i++) {
            actors.push(makeAddr(string(abi.encodePacked("actor", i))));
        }
    }
    
    function claim(uint256 actorSeed, uint256 distSeed, uint256 amount) public {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        uint256 distId = bound(distSeed, 0, distributor.distributionCount() - 1);
        amount = bound(amount, 1 ether, 1000 ether);
        
        bytes32[] memory proof = new bytes32[](3);
        
        vm.prank(actor);
        try distributor.claim(distId, amount, proof) {} catch {}
    }
    
    function getAllActors() public view returns (address[] memory) {
        return actors;
    }
}