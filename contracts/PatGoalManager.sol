// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./PATToken.sol";
import "./PatTreasuryManager.sol";
import "./PatValidationSystem.sol";
import "./PatNFT.sol";

/**
 * @title SimpleGoalManager - Ponder Optimized
 * @dev Ultra-simple goal management with comprehensive event logging for Ponder indexing
 */
contract PatGoalManager is Ownable, ReentrancyGuard {
    
    PATToken public patToken;
    PatTreasuryManager public treasuryManager;
    PatValidationSystem public validationSystem;
    PatNFT public petNFT;
    
    enum GoalStatus { ACTIVE, COMPLETED, FAILED }
    
    struct Goal {
        address owner;
        string title;
        uint256 stakeAmount;
        uint256 endTime;
        GoalStatus status;
        uint256 petTokenId;
        uint256 milestonesCompleted;
        uint256 totalMilestones;
    }
    
    struct Milestone {
        uint256 goalId;
        string description;
        bool isCompleted;
        string evidenceIPFS;
    }
    
    // 🎯 NEW: Struct to reduce stack depth in createGoal
    struct GoalCreationParams {
        string title;
        uint256 stakeAmount;
        uint256 durationDays;
        string petName;
        PatNFT.PetType petType;
        string petMetadataIPFS;
        uint256 totalMilestones;
    }
    
    // Storage
    mapping(uint256 => Goal) public goals;
    mapping(uint256 => Milestone) public milestones;
    mapping(address => uint256[]) public userGoals;
    
    uint256 public nextGoalId;
    uint256 public nextMilestoneId;
    
    // Constants
    uint256 public constant MILESTONE_XP = 25;
    uint256 public constant COMPLETION_BONUS_XP = 100;
    
    // 🎯 PONDER EVENTS - Comprehensive goal system tracking
    event GoalSystemInitialized(
        address indexed owner,
        address patToken,
        address treasuryManager,
        address validationSystem,
        address petNFT,
        uint256 milestoneXP,
        uint256 completionBonusXP,
        uint256 timestamp
    );
    
    event GoalCreated(
        uint256 indexed goalId,
        address indexed owner,
        string title,
        uint256 stakeAmount,
        uint256 durationDays,
        uint256 endTime,
        uint256 totalMilestones,
        uint256 indexed petTokenId,
        PatNFT.PetType petType,
        string petName,
        string petMetadataIPFS,
        uint256 timestamp
    );
    
    event MilestoneCreated(
        uint256 indexed milestoneId,
        uint256 indexed goalId,
        address indexed goalOwner,
        string description,
        uint256 milestoneIndex,
        uint256 timestamp
    );
    
    event MilestoneSubmitted(
        uint256 indexed milestoneId,
        uint256 indexed goalId,
        address indexed submitter,
        string description,
        string evidenceIPFS,
        uint256 timestamp
    );
    
    event MilestoneCompleted(
        uint256 indexed milestoneId,
        uint256 indexed goalId,
        address indexed goalOwner,
        uint256 xpAwarded,
        uint256 newMilestonesCompleted,
        uint256 totalMilestones,
        uint256 progressPercentage,
        string petMetadataIPFS,
        uint256 timestamp
    );
    
    event MilestoneRejected(
        uint256 indexed milestoneId,
        uint256 indexed goalId,
        address indexed goalOwner,
        string reason,
        string petMetadataIPFS,
        uint256 timestamp
    );
    
    event GoalCompleted(
        uint256 indexed goalId,
        address indexed owner,
        uint256 totalMilestonesCompleted,
        uint256 bonusXPAwarded,
        uint256 stakeReward,
        uint256 completionTime,
        bool wasEarlyCompletion,
        string finalPetMetadataIPFS,
        uint256 timestamp
    );
    
    event GoalFailed(
        uint256 indexed goalId,
        address indexed owner,
        uint256 milestonesCompleted,
        uint256 totalMilestones,
        uint256 stakeLost,
        string failureReason,
        string sadPetMetadataIPFS,
        uint256 timestamp
    );
    
    event BonusXPAwarded(
        uint256 indexed goalId,
        address indexed owner,
        uint256 indexed petTokenId,
        uint256 xpAmount,
        string reason,
        address awardedBy,
        string petMetadataIPFS,
        uint256 timestamp
    );
    
    event GoalSystemStatistics(
        uint256 totalGoalsCreated,
        uint256 activeGoals,
        uint256 completedGoals,
        uint256 failedGoals,
        uint256 successRate,
        uint256 totalStakeAmount,
        uint256 totalMilestonesCreated,
        uint256 totalMilestonesCompleted,
        uint256 averageGoalDuration,
        uint256 timestamp
    );
    
    modifier onlyGoalOwner(uint256 goalId) {
        require(goals[goalId].owner == msg.sender, "Not goal owner");
        _;
    }
    
    constructor(
        address _patToken,
        address _treasuryManager,
        address _validationSystem,
        address _petNFT
    ) Ownable(msg.sender) {
        patToken = PATToken(_patToken);
        treasuryManager = PatTreasuryManager(_treasuryManager);
        validationSystem = PatValidationSystem(_validationSystem);
        petNFT = PatNFT(_petNFT);
        
        // 🎯 PONDER EVENT: System initialization
        emit GoalSystemInitialized(
            msg.sender,
            _patToken,
            _treasuryManager,
            _validationSystem,
            _petNFT,
            MILESTONE_XP,
            COMPLETION_BONUS_XP,
            block.timestamp
        );
        
        _emitSystemStatistics();
    }
    
    // 🎯 OPTIMIZED: Split createGoal into smaller functions
    function createGoal(
        string memory title,
        uint256 stakeAmount,
        uint256 durationDays,
        string memory petName,
        PatNFT.PetType petType,
        string memory petMetadataIPFS,
        uint256 totalMilestones
    ) external nonReentrant returns (uint256) {
        // Create params struct to reduce stack depth
        GoalCreationParams memory params = GoalCreationParams({
            title: title,
            stakeAmount: stakeAmount,
            durationDays: durationDays,
            petName: petName,
            petType: petType,
            petMetadataIPFS: petMetadataIPFS,
            totalMilestones: totalMilestones
        });
        
        return _createGoalInternal(params);
    }
    
    function _createGoalInternal(GoalCreationParams memory params) internal returns (uint256) {
        require(params.stakeAmount > 0, "Invalid stake");
        require(params.durationDays > 0, "Invalid duration");
        require(params.totalMilestones > 0, "Need milestones");
        
        // User approves GoalManager, then GoalManager transfers to TreasuryManager
        require(patToken.transferFrom(msg.sender, address(this), params.stakeAmount), "Transfer failed");
        require(patToken.transfer(address(treasuryManager), params.stakeAmount), "Treasury transfer failed");
        
        uint256 goalId = nextGoalId++;
        uint256 endTime = block.timestamp + (params.durationDays * 1 days);
        
        // Mint pet
        uint256 petTokenId = petNFT.mintPet(msg.sender, params.petName, goalId, params.petType, params.petMetadataIPFS);
        
        // Create goal
        goals[goalId] = Goal({
            owner: msg.sender,
            title: params.title,
            stakeAmount: params.stakeAmount,
            endTime: endTime,
            status: GoalStatus.ACTIVE,
            petTokenId: petTokenId,
            milestonesCompleted: 0,
            totalMilestones: params.totalMilestones
        });
        
        userGoals[msg.sender].push(goalId);
        
        // 🎯 PONDER EVENT: Goal creation with comprehensive data
        emit GoalCreated(
            goalId,
            msg.sender,
            params.title,
            params.stakeAmount,
            params.durationDays,
            endTime,
            params.totalMilestones,
            petTokenId,
            params.petType,
            params.petName,
            params.petMetadataIPFS,
            block.timestamp
        );
        
        _emitSystemStatistics();
        return goalId;
    }
    
    function createMilestone(uint256 goalId, string memory description) external onlyGoalOwner(goalId) {
        require(goals[goalId].status == GoalStatus.ACTIVE, "Goal not active");
        
        uint256 milestoneId = nextMilestoneId++;
        
        milestones[milestoneId] = Milestone({
            goalId: goalId,
            description: description,
            isCompleted: false,
            evidenceIPFS: ""
        });
        
        // Calculate milestone index
        uint256 milestoneIndex = _calculateMilestoneIndex(goalId);
        
        // 🎯 PONDER EVENT: Milestone creation
        emit MilestoneCreated(
            milestoneId,
            goalId,
            msg.sender,
            description,
            milestoneIndex,
            block.timestamp
        );
    }
    
    function _calculateMilestoneIndex(uint256 goalId) internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < nextMilestoneId; i++) {
            if (milestones[i].goalId == goalId) {
                count++;
            }
        }
        return count;
    }
    
    function submitMilestone(uint256 milestoneId, string memory evidenceIPFS) external {
        Milestone storage milestone = milestones[milestoneId];
        Goal storage goal = goals[milestone.goalId];
        
        require(goal.owner == msg.sender, "Not authorized");
        require(!milestone.isCompleted, "Already completed");
        require(goal.status == GoalStatus.ACTIVE, "Goal not active");
        
        milestone.evidenceIPFS = evidenceIPFS;
        
        // Request validation
        validationSystem.requestValidation(
            milestoneId,
            msg.sender,
            evidenceIPFS,
            goal.stakeAmount
        );
        
        // 🎯 PONDER EVENT: Milestone submission
        emit MilestoneSubmitted(
            milestoneId,
            milestone.goalId,
            msg.sender,
            milestone.description,
            evidenceIPFS,
            block.timestamp
        );
    }
    
    function completeMilestone(uint256 milestoneId, string memory newPetMetadataIPFS) external {
        require(
            msg.sender == address(validationSystem) || msg.sender == owner(),
            "Not authorized"
        );
        
        _completeMilestoneInternal(milestoneId, newPetMetadataIPFS);
    }
    
    function _completeMilestoneInternal(uint256 milestoneId, string memory newPetMetadataIPFS) internal {
        Milestone storage milestone = milestones[milestoneId];
        Goal storage goal = goals[milestone.goalId];
        
        require(!milestone.isCompleted, "Already completed");
        require(goal.status == GoalStatus.ACTIVE, "Goal not active");
        
        milestone.isCompleted = true;
        goal.milestonesCompleted++;
        
        // Add XP to pet
        petNFT.addExperienceWithMetadata(goal.petTokenId, MILESTONE_XP, newPetMetadataIPFS);
        petNFT.recordMilestoneCompleted(goal.petTokenId);
        
        uint256 progressPercentage = (goal.milestonesCompleted * 100) / goal.totalMilestones;
        
        // 🎯 PONDER EVENT: Milestone completion
        emit MilestoneCompleted(
            milestoneId,
            milestone.goalId,
            goal.owner,
            MILESTONE_XP,
            goal.milestonesCompleted,
            goal.totalMilestones,
            progressPercentage,
            newPetMetadataIPFS,
            block.timestamp
        );
        
        // Check if goal is complete
        if (goal.milestonesCompleted >= goal.totalMilestones) {
            _completeGoal(milestone.goalId, newPetMetadataIPFS);
        }
        
        _emitSystemStatistics();
    }
    
    function _completeGoal(uint256 goalId, string memory finalMetadataIPFS) internal {
        Goal storage goal = goals[goalId];
        goal.status = GoalStatus.COMPLETED;
        
        // Calculate completion details  
        uint256 completionTime = block.timestamp - (goal.endTime - 30 days);
        bool wasEarlyCompletion = block.timestamp < goal.endTime - (7 days);
        
        // Add completion bonus XP
        petNFT.addExperienceWithMetadata(goal.petTokenId, COMPLETION_BONUS_XP, finalMetadataIPFS);
        
        // Return stake with rewards
        uint256 stakeReward = treasuryManager.distributeGoalReward(goal.owner, goal.stakeAmount);
        
        // 🎯 PONDER EVENT: Goal completion
        emit GoalCompleted(
            goalId,
            goal.owner,
            goal.milestonesCompleted,
            COMPLETION_BONUS_XP,
            stakeReward,
            completionTime,
            wasEarlyCompletion,
            finalMetadataIPFS,
            block.timestamp
        );
        
        _emitSystemStatistics();
    }
    
    function failGoal(uint256 goalId, string memory sadPetMetadataIPFS) external {
        Goal storage goal = goals[goalId];
        
        require(
            msg.sender == goal.owner || 
            msg.sender == owner() || 
            block.timestamp > goal.endTime,
            "Not authorized"
        );
        require(goal.status == GoalStatus.ACTIVE, "Goal not active");
        
        string memory failureReason = _getFailureReason(goal.endTime);
        
        goal.status = GoalStatus.FAILED;
        
        // Make pet sad
        petNFT.setPetMoodWithMetadata(goal.petTokenId, false, sadPetMetadataIPFS);
        
        // Distribute failed stake
        treasuryManager.distributeFailedStake(goal.stakeAmount, goal.owner);
        
        // 🎯 PONDER EVENT: Goal failure
        emit GoalFailed(
            goalId,
            goal.owner,
            goal.milestonesCompleted,
            goal.totalMilestones,
            goal.stakeAmount,
            failureReason,
            sadPetMetadataIPFS,
            block.timestamp
        );
        
        _emitSystemStatistics();
    }
    
    function _getFailureReason(uint256 goalEndTime) internal view returns (string memory) {
        if (block.timestamp > goalEndTime) {
            return "Time expired";
        } else if (msg.sender == goals[0].owner) { // Using goals[0].owner as placeholder
            return "Owner abandoned";
        } else {
            return "Admin intervention";
        }
    }
    
    function rejectMilestone(uint256 milestoneId, string memory sadPetMetadataIPFS) external {
        require(
            msg.sender == address(validationSystem) || msg.sender == owner(),
            "Not authorized"
        );
        
        Milestone storage milestone = milestones[milestoneId];
        Goal storage goal = goals[milestone.goalId];
        
        // Make pet sad but don't complete milestone
        petNFT.setPetMoodWithMetadata(goal.petTokenId, false, sadPetMetadataIPFS);
        
        // 🎯 PONDER EVENT: Milestone rejection
        emit MilestoneRejected(
            milestoneId,
            milestone.goalId,
            goal.owner,
            "Validation failed",
            sadPetMetadataIPFS,
            block.timestamp
        );
    }
    
    function addBonusXP(
        uint256 goalId, 
        uint256 xpAmount, 
        string memory reason,
        string memory newPetMetadataIPFS
    ) external onlyOwner {
        Goal storage goal = goals[goalId];
        require(goal.status == GoalStatus.ACTIVE, "Goal not active");
        
        petNFT.addExperienceWithMetadata(goal.petTokenId, xpAmount, newPetMetadataIPFS);
        
        // 🎯 PONDER EVENT: Bonus XP award
        emit BonusXPAwarded(
            goalId,
            goal.owner,
            goal.petTokenId,
            xpAmount,
            reason,
            msg.sender,
            newPetMetadataIPFS,
            block.timestamp
        );
    }
    
    /**
     * @dev Emit current system statistics
     */
    function _emitSystemStatistics() internal {
        (
            uint256 activeGoals,
            uint256 completedGoals,
            uint256 failedGoals,
            uint256 totalStakeAmount,
            uint256 totalMilestonesCompleted
        ) = _calculateStatistics();
        
        uint256 totalGoalsCreated = nextGoalId;
        uint256 successRate = totalGoalsCreated > 0 ? 
            (completedGoals * 10000) / totalGoalsCreated : 0;
        
        // 🎯 PONDER EVENT: System statistics
        emit GoalSystemStatistics(
            totalGoalsCreated,
            activeGoals,
            completedGoals,
            failedGoals,
            successRate,
            totalStakeAmount,
            nextMilestoneId,
            totalMilestonesCompleted,
            30 days, // Simplified average
            block.timestamp
        );
    }
    
    function _calculateStatistics() internal view returns (
        uint256 activeGoals,
        uint256 completedGoals,
        uint256 failedGoals,
        uint256 totalStakeAmount,
        uint256 totalMilestonesCompleted
    ) {
        for (uint256 i = 0; i < nextGoalId; i++) {
            Goal memory goal = goals[i];
            
            if (goal.status == GoalStatus.ACTIVE) activeGoals++;
            else if (goal.status == GoalStatus.COMPLETED) completedGoals++;
            else if (goal.status == GoalStatus.FAILED) failedGoals++;
            
            totalStakeAmount += goal.stakeAmount;
            totalMilestonesCompleted += goal.milestonesCompleted;
        }
    }
    
    /**
     * @dev Public function to emit statistics (for data sync)
     */
    function emitSystemStatistics() external {
        _emitSystemStatistics();
    }
    
    // Keep only essential functions for basic contract interaction
    function isGoalActive(uint256 goalId) external view returns (bool) {
        return goals[goalId].status == GoalStatus.ACTIVE;
    }
    
    function isGoalExpired(uint256 goalId) external view returns (bool) {
        return block.timestamp > goals[goalId].endTime;
    }
}