// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMerkleDistributor {
    struct Distribution {
        bytes32 merkleRoot;
        uint256 totalYield;
        address token;
        bool active;
        uint256 claimedAmount;
        uint256 startTime;
        uint256 endTime;
    }

    event DistributionCreated(
        uint256 indexed distributionId,
        bytes32 indexed merkleRoot,
        address indexed token,
        uint256 totalYield,
        uint256 startTime,
        uint256 endTime
    );

    event Claimed(uint256 indexed distributionId, address indexed user, uint256 amount, uint256 timestamp);

    function createDistribution(
        bytes32 merkleRoot,
        uint256 totalYield,
        address token,
        uint256 startTime,
        uint256 endTime
    ) external returns (uint256 distributionId);

    function claim(uint256 distributionId, uint256 amount, bytes32[] calldata merkleProof) external;

    function hasClaimed(uint256 distributionId, address user) external view returns (bool);

    function verifyProof(uint256 distributionId, address user, uint256 amount, bytes32[] calldata merkleProof)
        external
        view
        returns (bool);
}
