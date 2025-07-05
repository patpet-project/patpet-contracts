// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./PATToken.sol";

/**
 * @title PatTreasuryManager - Clean & Integration-Friendly Version
 * @dev Treasury management with clean events and readable data structures
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
    
    // Clean StakeTier struct
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
    
    // Clean, readable events
    event TreasuryInitialized(
        address indexed owner,
        address indexed patToken,
        uint256 timestamp
    );
    
    event StakeDistributed(
        uint256 stakeAmount,
        uint256 rewardPoolAmount,
        uint256 insurancePoolAmount,
        uint256 validatorPoolAmount,
        uint256 developmentPoolAmount,
        uint256 burnedAmount,
        address indexed staker,
        string reason,
        uint256 timestamp
    );
    
    event RewardCalculated(
        address indexed user,
        uint256 stakeAmount,
        uint256 totalReward,
        uint256 bonusReward,
        uint256 tier,
        string tierName,
        uint256 rewardMultiplier,
        uint256 timestamp
    );
    
    event RewardDistributed(
        address indexed user,
        uint256 stakeAmount,
        uint256 totalReward,
        uint256 bonusReward,
        uint256 tier,
        string tierName,
        uint256 timestamp
    );
    
    event ValidatorRewardDistributed(
        address indexed validator,
        uint256 amount,
        string reason,
        address indexed distributor,
        uint256 timestamp
    );
    
    event PoolBalanceUpdated(
        string poolName,
        uint256 oldBalance,
        uint256 newBalance,
        int256 change,
        string reason,
        uint256 timestamp
    );
    
    event TreasuryWithdrawal(
        address indexed recipient,
        uint256 amount,
        string poolName,
        string reason,
        address indexed withdrawnBy,
        uint256 timestamp
    );
    
    event EmergencyWithdrawal(
        address indexed recipient,
        uint256 amount,
        string reason,
        address indexed withdrawnBy,
        uint256 timestamp
    );
    
    event StakeTierUpdated(
        uint256 indexed tierIndex,
        uint256 minStake,
        uint256 maxStake,
        uint256 rewardMultiplier,
        string tierName,
        address indexed updatedBy,
        uint256 timestamp
    );
    
    event AuthorizationChanged(
        address indexed contractAddress,
        bool authorized,
        address indexed changedBy,
        uint256 timestamp
    );
    
    modifier onlyAuthorized() {
        require(authorizedContracts[msg.sender], "Not authorized");
        _;
    }
    
    constructor(address _patToken) Ownable(msg.sender) {
        patToken = PATToken(_patToken);
        _initializeStakeTiers();
        
        emit TreasuryInitialized(msg.sender, _patToken, block.timestamp);
    }
    
    function _initializeStakeTiers() internal {
        stakeTiers[0] = StakeTier(10 * 10**18, 99 * 10**18, 11000, "Sprout");      // 10-99 PAT, 110% return
        stakeTiers[1] = StakeTier(100 * 10**18, 499 * 10**18, 12500, "Bloom");     // 100-499 PAT, 125% return
        stakeTiers[2] = StakeTier(500 * 10**18, 1999 * 10**18, 15000, "Flourish"); // 500-1999 PAT, 150% return
        stakeTiers[3] = StakeTier(2000 * 10**18, 9999 * 10**18, 20000, "Thrive");  // 2000-9999 PAT, 200% return
        stakeTiers[4] = StakeTier(10000 * 10**18, 50000 * 10**18, 30000, "Legend"); // 10000+ PAT, 300% return
        
        // Emit initial tier setup
        for (uint256 i = 0; i < 5; i++) {
            emit StakeTierUpdated(
                i,
                stakeTiers[i].minStake,
                stakeTiers[i].maxStake,
                stakeTiers[i].rewardMultiplier,
                stakeTiers[i].tierName,
                msg.sender,
                block.timestamp
            );
        }
    }
    
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
        
        // Update pool balances and emit events
        _updatePoolBalance("reward", rewardPool, rewardPool + rewardAmount, "Failed stake distribution");
        rewardPool += rewardAmount;
        
        _updatePoolBalance("insurance", insurancePool, insurancePool + insuranceAmount, "Failed stake distribution");
        insurancePool += insuranceAmount;
        
        _updatePoolBalance("validator", validatorPool, validatorPool + validatorAmount, "Failed stake distribution");
        validatorPool += validatorAmount;
        
        _updatePoolBalance("development", developmentPool, developmentPool + developmentAmount, "Failed stake distribution");
        developmentPool += developmentAmount;
        
        // Send tokens to dead address for burning
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
            burnAmount,
            staker,
            "Goal failed",
            block.timestamp
        );
    }
    
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
            bonusReward = rewardPool;
            totalReward = stakeAmount + bonusReward;
        }
    }
    
    function distributeGoalReward(address user, uint256 stakeAmount) 
        external onlyAuthorized nonReentrant returns (uint256) {
        (uint256 totalReward, uint256 bonusReward, uint256 tier) = calculateReward(stakeAmount);
        StakeTier memory stakeTier = stakeTiers[tier];
        
        emit RewardCalculated(
            user,
            stakeAmount,
            totalReward,
            bonusReward,
            tier,
            stakeTier.tierName,
            stakeTier.rewardMultiplier,
            block.timestamp
        );
        
        // Transfer original stake back
        require(patToken.transfer(user, stakeAmount), "Failed to return stake");
        
        // Mint bonus reward from reward pool
        if (bonusReward > 0) {
            _updatePoolBalance("reward", rewardPool, rewardPool - bonusReward, "Goal completion reward");
            rewardPool -= bonusReward;
            
            patToken.distributeReward(user, bonusReward, "Goal completion bonus");
            totalRewardsDistributed += bonusReward;
        }
        
        // Update statistics
        totalGoalsCompleted += 1;
        
        emit RewardDistributed(
            user,
            stakeAmount,
            totalReward,
            bonusReward,
            tier,
            stakeTier.tierName,
            block.timestamp
        );
        
        return totalReward;
    }
    
    function distributeValidatorReward(address validator, uint256 amount) 
        external onlyAuthorized nonReentrant {
        require(amount <= validatorPool, "Insufficient validator pool balance");
        
        _updatePoolBalance("validator", validatorPool, validatorPool - amount, "Validator reward");
        validatorPool -= amount;
        
        patToken.distributeReward(validator, amount, "Validation reward");
        
        emit ValidatorRewardDistributed(
            validator,
            amount,
            "Validation reward",
            msg.sender,
            block.timestamp
        );
    }
    
    function _updatePoolBalance(string memory poolName, uint256 oldBalance, uint256 newBalance, string memory reason) internal {
        int256 change = int256(newBalance) - int256(oldBalance);
        
        emit PoolBalanceUpdated(
            poolName,
            oldBalance,
            newBalance,
            change,
            reason,
            block.timestamp
        );
    }
    
    function getStakeTier(uint256 stakeAmount) public view returns (uint256) {
        for (uint256 i = 0; i < stakeTiers.length; i++) {
            if (stakeAmount >= stakeTiers[i].minStake && stakeAmount <= stakeTiers[i].maxStake) {
                return i;
            }
        }
        // If amount is higher than max tier, return highest tier
        return stakeTiers.length - 1;
    }
    
    function getStakeTierInfo(uint256 tier) external view returns (StakeTier memory) {
        require(tier < stakeTiers.length, "Invalid tier");
        return stakeTiers[tier];
    }
    
    function getAllStakeTiers() external view returns (StakeTier[5] memory) {
        return stakeTiers;
    }
    
    function getPoolBalances() external view returns (
        uint256 reward,
        uint256 insurance,
        uint256 validator,
        uint256 development
    ) {
        return (rewardPool, insurancePool, validatorPool, developmentPool);
    }
    
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
    
    function canSupportReward(uint256 stakeAmount) external view returns (bool) {
        (, uint256 bonusReward,) = calculateReward(stakeAmount);
        return bonusReward <= rewardPool;
    }
    
    function emergencyWithdraw(address recipient, uint256 amount, string memory reason) 
        external onlyOwner nonReentrant {
        require(amount <= developmentPool, "Insufficient development pool balance");
        
        _updatePoolBalance("development", developmentPool, developmentPool - amount, reason);
        developmentPool -= amount;
        
        patToken.mintWithReason(recipient, amount, reason);
        
        emit EmergencyWithdrawal(recipient, amount, reason, msg.sender, block.timestamp);
    }
    
    function withdrawFromPool(string memory poolName, address recipient, uint256 amount, string memory reason) 
        external onlyOwner nonReentrant {
        
        if (keccak256(bytes(poolName)) == keccak256(bytes("development"))) {
            require(amount <= developmentPool, "Insufficient balance");
            _updatePoolBalance("development", developmentPool, developmentPool - amount, reason);
            developmentPool -= amount;
        } else if (keccak256(bytes(poolName)) == keccak256(bytes("insurance"))) {
            require(amount <= insurancePool, "Insufficient balance");
            _updatePoolBalance("insurance", insurancePool, insurancePool - amount, reason);
            insurancePool -= amount;
        } else {
            revert("Invalid pool name");
        }
        
        patToken.mintWithReason(recipient, amount, reason);
        
        emit TreasuryWithdrawal(recipient, amount, poolName, reason, msg.sender, block.timestamp);
    }
    
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
        
        emit StakeTierUpdated(
            tierIndex,
            minStake,
            maxStake,
            rewardMultiplier,
            tierName,
            msg.sender,
            block.timestamp
        );
    }
    
    function addAuthorizedContract(address contractAddress) external onlyOwner {
        authorizedContracts[contractAddress] = true;
        
        emit AuthorizationChanged(contractAddress, true, msg.sender, block.timestamp);
    }
    
    function removeAuthorizedContract(address contractAddress) external onlyOwner {
        authorizedContracts[contractAddress] = false;
        
        emit AuthorizationChanged(contractAddress, false, msg.sender, block.timestamp);
    }
    
    function receiveStake(uint256 amount) external onlyAuthorized {
        require(patToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    }
}