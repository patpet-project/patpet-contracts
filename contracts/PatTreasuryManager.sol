// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./PATToken.sol";

/**
 * @title PatTreasuryManager
 * @dev Manages tokenomics, reward distribution, and treasury pools
 */
contract PatTreasuryManager is Ownable, ReentrancyGuard {
    using Math for uint256;
    
    PATToken public patToken;
    
    // Treasury pool allocations (basis points - 10000 = 100%)
    uint256 public constant REWARD_POOL_ALLOCATION = 6000;      // 60%
    uint256 public constant INSURANCE_POOL_ALLOCATION = 2500;   // 25%
    uint256 public constant VALIDATOR_POOL_ALLOCATION = 1000;   // 10%
    uint256 public constant DEVELOPMENT_POOL_ALLOCATION = 500;  // 5%
    
    // Burn percentage from failed stakes
    uint256 public constant BURN_PERCENTAGE = 1000; // 10%
    
    // Stake tier multipliers (basis points)
    struct StakeTier {
        uint256 minStake;
        uint256 maxStake;
        uint256 rewardMultiplier; // basis points (10000 = 100%)
        string tierName;
    }
    
    StakeTier[5] public stakeTiers;
    
    // Treasury pool balances
    uint256 public rewardPool;
    uint256 public insurancePool;
    uint256 public validatorPool;
    uint256 public developmentPool;
    
    // Statistics tracking
    uint256 public totalStakesReceived;
    uint256 public totalRewardsDistributed;
    uint256 public totalTokensBurned;
    uint256 public totalGoalsCompleted;
    uint256 public totalGoalsFailed;
    
    // Authorized contracts
    mapping(address => bool) public authorizedContracts;
    
    // Events
    event StakeDistributed(
        uint256 stakeAmount,
        uint256 rewardPool,
        uint256 insurancePool,
        uint256 validatorPool,
        uint256 developmentPool,
        uint256 burned
    );
    event RewardCalculated(address indexed user, uint256 stakeAmount, uint256 reward, uint256 tier);
    event RewardDistributed(address indexed user, uint256 stakeAmount, uint256 bonusReward);
    event ValidatorRewardDistributed(address indexed validator, uint256 amount);
    event TreasuryWithdrawal(address indexed recipient, uint256 amount, string pool);
    event EmergencyWithdrawal(address indexed recipient, uint256 amount);
    
    modifier onlyAuthorized() {
        require(authorizedContracts[msg.sender], "Not authorized");
        _;
    }
    
    constructor(address _patToken) Ownable(msg.sender) {
        patToken = PATToken(_patToken);
        _initializeStakeTiers();
    }
    
    function _initializeStakeTiers() internal {
        stakeTiers[0] = StakeTier(10 * 10**18, 99 * 10**18, 11000, "Sprout");      // 10-99 PAT, 110% return
        stakeTiers[1] = StakeTier(100 * 10**18, 499 * 10**18, 12500, "Bloom");     // 100-499 PAT, 125% return
        stakeTiers[2] = StakeTier(500 * 10**18, 1999 * 10**18, 15000, "Flourish"); // 500-1999 PAT, 150% return
        stakeTiers[3] = StakeTier(2000 * 10**18, 9999 * 10**18, 20000, "Thrive");  // 2000-9999 PAT, 200% return
        stakeTiers[4] = StakeTier(10000 * 10**18, 50000 * 10**18, 30000, "Legend"); // 10000+ PAT, 300% return
    }
    
    /**
     * @dev Distribute failed stake to treasury pools
     */
    function distributeFailedStake(uint256 stakeAmount, address staker) 
        external onlyAuthorized nonReentrant {
        require(stakeAmount > 0, "Stake amount must be greater than 0");
        
        // Calculate distribution amounts
        uint256 burnAmount = (stakeAmount * BURN_PERCENTAGE) / 10000;
        uint256 remainingAmount = stakeAmount - burnAmount;
        
        uint256 rewardAmount = (remainingAmount * REWARD_POOL_ALLOCATION) / 10000;
        uint256 insuranceAmount = (remainingAmount * INSURANCE_POOL_ALLOCATION) / 10000;
        uint256 validatorAmount = (remainingAmount * VALIDATOR_POOL_ALLOCATION) / 10000;
        uint256 developmentAmount = remainingAmount - rewardAmount - insuranceAmount - validatorAmount;
        
        // Update pool balances
        rewardPool += rewardAmount;
        insurancePool += insuranceAmount;
        validatorPool += validatorAmount;
        developmentPool += developmentAmount;
        
        // 🔧 FIX: Send tokens to dead address instead of burning (simpler approach)
        // Burn tokens for deflationary pressure by sending to 0x000...dead
        address deadAddress = 0x000000000000000000000000000000000000dEaD;
        patToken.transfer(deadAddress, burnAmount);
        totalTokensBurned += burnAmount;
        
        // Update statistics
        totalStakesReceived += stakeAmount;
        totalGoalsFailed += 1;
        
        // Record stake loss
        patToken.recordStakeLoss(staker, stakeAmount, "Goal failed");
        
        emit StakeDistributed(
            stakeAmount,
            rewardAmount,
            insuranceAmount,
            validatorAmount,
            developmentAmount,
            burnAmount
        );
    }
    
    /**
     * @dev Calculate reward for successful goal completion
     */
    function calculateReward(uint256 stakeAmount) 
        public view returns (uint256 totalReward, uint256 bonusReward, uint256 tier) {
        // Get stake tier
        tier = getStakeTier(stakeAmount);
        StakeTier memory stakeTier = stakeTiers[tier];
        
        // Calculate total reward (stake + bonus)
        totalReward = (stakeAmount * stakeTier.rewardMultiplier) / 10000;
        bonusReward = totalReward - stakeAmount;
        
        // Check if reward pool has enough balance
        if (bonusReward > rewardPool) {
            // Reduce bonus if insufficient funds
            bonusReward = rewardPool;
            totalReward = stakeAmount + bonusReward;
        }
    }
    
    /**
     * @dev Distribute reward for successful goal completion
     */
    function distributeGoalReward(address user, uint256 stakeAmount) 
        external onlyAuthorized nonReentrant returns (uint256) {
        (uint256 totalReward, uint256 bonusReward, uint256 tier) = calculateReward(stakeAmount);
        
        // Transfer original stake back
        require(patToken.transfer(user, stakeAmount), "Failed to return stake");
        
        // Mint bonus reward from reward pool
        if (bonusReward > 0) {
            rewardPool -= bonusReward;
            patToken.mint(user, bonusReward);
            totalRewardsDistributed += bonusReward;
        }
        
        // Update statistics
        totalGoalsCompleted += 1;
        
        emit RewardCalculated(user, stakeAmount, totalReward, tier);
        emit RewardDistributed(user, stakeAmount, bonusReward);
        
        return totalReward;
    }
    
    /**
     * @dev Distribute reward to validator
     */
    function distributeValidatorReward(address validator, uint256 amount) 
        external onlyAuthorized nonReentrant {
        require(amount <= validatorPool, "Insufficient validator pool balance");
        
        validatorPool -= amount;
        patToken.mint(validator, amount);
        
        emit ValidatorRewardDistributed(validator, amount);
    }
    
    /**
     * @dev Get stake tier based on amount
     */
    function getStakeTier(uint256 stakeAmount) public view returns (uint256) {
        for (uint256 i = 0; i < stakeTiers.length; i++) {
            if (stakeAmount >= stakeTiers[i].minStake && stakeAmount <= stakeTiers[i].maxStake) {
                return i;
            }
        }
        // If amount is higher than max tier, return highest tier
        return stakeTiers.length - 1;
    }
    
    /**
     * @dev Get stake tier info
     */
    function getStakeTierInfo(uint256 tier) external view returns (StakeTier memory) {
        require(tier < stakeTiers.length, "Invalid tier");
        return stakeTiers[tier];
    }
    
    /**
     * @dev Get all stake tiers
     */
    function getAllStakeTiers() external view returns (StakeTier[5] memory) {
        return stakeTiers;
    }
    
    /**
     * @dev Get treasury pool balances
     */
    function getPoolBalances() external view returns (
        uint256 reward,
        uint256 insurance,
        uint256 validator,
        uint256 development
    ) {
        return (rewardPool, insurancePool, validatorPool, developmentPool);
    }
    
    /**
     * @dev Get treasury statistics
     */
    function getTreasuryStats() external view returns (
        uint256 totalStakes,
        uint256 totalRewards,
        uint256 totalBurned,
        uint256 completedGoals,
        uint256 failedGoals,
        uint256 successRate
    ) {
        totalStakes = totalStakesReceived;
        totalRewards = totalRewardsDistributed;
        totalBurned = totalTokensBurned;
        completedGoals = totalGoalsCompleted;
        failedGoals = totalGoalsFailed;
        
        if (completedGoals + failedGoals > 0) {
            successRate = (completedGoals * 10000) / (completedGoals + failedGoals);
        } else {
            successRate = 0;
        }
    }
    
    /**
     * @dev Check if reward pool can support a potential reward
     */
    function canSupportReward(uint256 stakeAmount) external view returns (bool) {
        (, uint256 bonusReward,) = calculateReward(stakeAmount);
        return bonusReward <= rewardPool;
    }
    
    /**
     * @dev Emergency withdrawal from development pool (owner only)
     */
    function emergencyWithdraw(address recipient, uint256 amount) 
        external onlyOwner nonReentrant {
        require(amount <= developmentPool, "Insufficient development pool balance");
        
        developmentPool -= amount;
        patToken.mint(recipient, amount);
        
        emit EmergencyWithdrawal(recipient, amount);
    }
    
    /**
     * @dev Withdraw from specific treasury pool (owner only)
     */
    function withdrawFromPool(string memory poolName, address recipient, uint256 amount) 
        external onlyOwner nonReentrant {
        
        if (keccak256(bytes(poolName)) == keccak256(bytes("development"))) {
            require(amount <= developmentPool, "Insufficient balance");
            developmentPool -= amount;
        } else if (keccak256(bytes(poolName)) == keccak256(bytes("insurance"))) {
            require(amount <= insurancePool, "Insufficient balance");
            insurancePool -= amount;
        } else {
            revert("Invalid pool name");
        }
        
        patToken.mint(recipient, amount);
        emit TreasuryWithdrawal(recipient, amount, poolName);
    }
    
    /**
     * @dev Update stake tier multipliers (owner only)
     */
    function updateStakeTier(
        uint256 tierIndex,
        uint256 minStake,
        uint256 maxStake,
        uint256 rewardMultiplier,
        string memory tierName
    ) external onlyOwner {
        require(tierIndex < stakeTiers.length, "Invalid tier index");
        require(rewardMultiplier >= 10000, "Multiplier must be at least 100%");
        
        stakeTiers[tierIndex] = StakeTier(minStake, maxStake, rewardMultiplier, tierName);
    }
    
    /**
     * @dev Add authorized contract
     */
    function addAuthorizedContract(address contractAddress) external onlyOwner {
        authorizedContracts[contractAddress] = true;
    }
    
    /**
     * @dev Remove authorized contract
     */
    function removeAuthorizedContract(address contractAddress) external onlyOwner {
        authorizedContracts[contractAddress] = false;
    }
    
    /**
     * @dev Receive PAT tokens (for failed stakes)
     */
    function receiveStake(uint256 amount) external onlyAuthorized {
        require(patToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    }
}