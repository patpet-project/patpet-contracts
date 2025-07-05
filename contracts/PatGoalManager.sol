// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./PATToken.sol";
import "./PatTreasuryManager.sol";
import "./PatValidationSystem.sol";
import "./PatNFT.sol";

/**
 * @title PatGoalManager - Clean & Integration-Friendly Version
 * @dev Goal management with clean events and readable data structures
 */
contract PatGoalManager is Ownable, ReentrancyGuard {
    
    // Immutable contracts
    PATToken public immutable patToken;
    PatTreasuryManager public immutable treasuryManager;
    PatValidationSystem public immutable validationSystem;
    PatNFT public immutable petNFT;
    
    uint8 public constant MAX_MILESTONES = 4;
    
    // Custom errors
    error InvalidStake();
    error InvalidDuration();
    error NeedMilestones();
    error TooManyMilestones();
    error TransferFailed();
    error TreasuryTransferFailed();
    error NotGoalOwner();
    error GoalNotActive();
    error AlreadyCompleted();
    error NotAuthorized();
    error MaxMilestonesReached();
    
    enum GoalStatus { ACTIVE, COMPLETED, FAILED }
    
    // Clean Goal struct
    struct Goal {
        address owner;
        uint256 stakeAmount;
        uint256 endTime;
        GoalStatus status;
        uint8 totalMilestones;
        uint8 milestonesCompleted;
        uint256 petTokenId;
        string title;
        uint256 createdAt;
    }
    
    // Clean Milestone struct
    struct Milestone {
        uint256 goalId;
        string description;
        bool isCompleted;
        string evidenceIPFS;
        uint256 createdAt;
        uint256 completedAt;
    }
    
    // Storage
    mapping(uint256 => Goal) public goals;
    mapping(uint256 => Milestone) public milestones;
    mapping(address => uint256[]) public userGoals;
    mapping(uint256 => uint256[]) public goalMilestones; // goalId => milestoneIds
    
    uint256 public nextGoalId;
    uint256 public nextMilestoneId;
    
    // Clean, readable events
    event GoalCreated(
        uint256 indexed goalId,
        address indexed owner,
        uint256 indexed petTokenId,
        string title,
        uint256 stakeAmount,
        uint256 durationDays,
        string petName,
        PatNFT.PetType petType,
        string petMetadataIPFS,
        uint8 totalMilestones,
        uint256 endTime,
        uint256 timestamp
    );
    
    event MilestoneCreated(
        uint256 indexed milestoneId,
        uint256 indexed goalId,
        address indexed goalOwner,
        string description,
        uint256 timestamp
    );
    
    event MilestoneSubmitted(
        uint256 indexed milestoneId,
        uint256 indexed goalId,
        address indexed submitter,
        string evidenceIPFS,
        uint256 timestamp
    );
    
    event MilestoneCompleted(
        uint256 indexed milestoneId,
        uint256 indexed goalId,
        address indexed goalOwner,
        uint256 xpAwarded,
        uint8 milestonesCompleted,
        uint8 totalMilestones,
        uint256 progressPercentage,
        string petMetadataIPFS,
        uint256 timestamp
    );
    
    event GoalCompleted(
        uint256 indexed goalId,
        address indexed owner,
        uint256 bonusXP,
        uint256 stakeReward,
        uint256 completionTime,
        bool wasEarlyCompletion,
        bool allMilestonesCompleted,
        string finalPetMetadataIPFS,
        uint256 timestamp
    );
    
    event GoalFailed(
        uint256 indexed goalId,
        address indexed owner,
        uint8 milestonesCompleted,
        uint8 totalMilestones,
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
    
    modifier onlyGoalOwner(uint256 goalId) {
        if (goals[goalId].owner != msg.sender) revert NotGoalOwner();
        _;
    }
    
    modifier onlyActiveGoal(uint256 goalId) {
        if (goals[goalId].status != GoalStatus.ACTIVE) revert GoalNotActive();
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
    }
    
    function createGoal(
        string calldata title,
        uint256 stakeAmount,
        uint32 durationDays,
        string calldata petName,
        PatNFT.PetType petType,
        string calldata petMetadataIPFS,
        uint8 totalMilestones
    ) external nonReentrant returns (uint256) {
        if (stakeAmount == 0) revert InvalidStake();
        if (durationDays == 0) revert InvalidDuration();
        if (totalMilestones == 0) revert NeedMilestones();
        if (totalMilestones > MAX_MILESTONES) revert TooManyMilestones();
        
        return _createGoalInternal(
            title,
            stakeAmount,
            durationDays,
            petName,
            petType,
            petMetadataIPFS,
            totalMilestones
        );
    }
    
    function _createGoalInternal(
        string memory title,
        uint256 stakeAmount,
        uint32 durationDays,
        string memory petName,
        PatNFT.PetType petType,
        string memory petMetadataIPFS,
        uint8 totalMilestones
    ) internal returns (uint256) {
        // Transfer tokens
        if (!patToken.transferFrom(msg.sender, address(this), stakeAmount)) {
            revert TransferFailed();
        }
        if (!patToken.transfer(address(treasuryManager), stakeAmount)) {
            revert TreasuryTransferFailed();
        }
        
        uint256 goalId = nextGoalId++;
        uint256 endTime = block.timestamp + (uint256(durationDays) * 1 days);
        
        // Mint pet
        uint256 petTokenId = petNFT.mintPet(
            msg.sender, 
            petName, 
            goalId, 
            petType, 
            petMetadataIPFS
        );
        
        // Create goal
        goals[goalId] = Goal({
            owner: msg.sender,
            stakeAmount: stakeAmount,
            endTime: endTime,
            status: GoalStatus.ACTIVE,
            totalMilestones: totalMilestones,
            milestonesCompleted: 0,
            petTokenId: petTokenId,
            title: title,
            createdAt: block.timestamp
        });
        
        // Add to user goals
        userGoals[msg.sender].push(goalId);
        
        emit GoalCreated(
            goalId,
            msg.sender,
            petTokenId,
            title,
            stakeAmount,
            durationDays,
            petName,
            petType,
            petMetadataIPFS,
            totalMilestones,
            endTime,
            block.timestamp
        );
        
        return goalId;
    }
    
    function createMilestone(
        uint256 goalId, 
        string calldata description
    ) external onlyGoalOwner(goalId) onlyActiveGoal(goalId) {
        Goal storage goal = goals[goalId];
        
        // Check milestone limit
        if (goalMilestones[goalId].length >= goal.totalMilestones) {
            revert MaxMilestonesReached();
        }
        
        uint256 milestoneId = nextMilestoneId++;
        
        milestones[milestoneId] = Milestone({
            goalId: goalId,
            description: description,
            isCompleted: false,
            evidenceIPFS: "",
            createdAt: block.timestamp,
            completedAt: 0
        });
        
        goalMilestones[goalId].push(milestoneId);
        
        emit MilestoneCreated(milestoneId, goalId, msg.sender, description, block.timestamp);
    }
    
    function submitMilestone(
        uint256 milestoneId, 
        string calldata evidenceIPFS
    ) external {
        Milestone storage milestone = milestones[milestoneId];
        Goal storage goal = goals[milestone.goalId];
        
        if (goal.owner != msg.sender) revert NotAuthorized();
        if (milestone.isCompleted) revert AlreadyCompleted();
        if (goal.status != GoalStatus.ACTIVE) revert GoalNotActive();
        
        milestone.evidenceIPFS = evidenceIPFS;
        
        // Request validation
        validationSystem.requestValidation(
            milestoneId,
            msg.sender,
            evidenceIPFS,
            goal.stakeAmount
        );
        
        emit MilestoneSubmitted(milestoneId, milestone.goalId, msg.sender, evidenceIPFS, block.timestamp);
    }
    
    function completeMilestone(
        uint256 milestoneId, 
        string calldata newPetMetadataIPFS
    ) external {
        if (msg.sender != address(validationSystem) && msg.sender != owner()) {
            revert NotAuthorized();
        }
        
        Milestone storage milestone = milestones[milestoneId];
        Goal storage goal = goals[milestone.goalId];
        
        if (milestone.isCompleted) revert AlreadyCompleted();
        if (goal.status != GoalStatus.ACTIVE) revert GoalNotActive();
        
        milestone.isCompleted = true;
        milestone.completedAt = block.timestamp;
        goal.milestonesCompleted++;
        
        // Record milestone completion on pet
        petNFT.recordMilestoneCompleted(goal.petTokenId, newPetMetadataIPFS);
        
        uint256 progressPercentage = (uint256(goal.milestonesCompleted) * 100) / uint256(goal.totalMilestones);
        
        emit MilestoneCompleted(
            milestoneId,
            milestone.goalId,
            goal.owner,
            25, // XP awarded per milestone
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
    }
    
    function _completeGoal(uint256 goalId, string memory finalMetadataIPFS) internal {
        Goal storage goal = goals[goalId];
        goal.status = GoalStatus.COMPLETED;
        
        // Award completion bonus to pet
        petNFT.awardCompletionBonus(goal.petTokenId, finalMetadataIPFS);
        
        // Calculate completion details
        uint256 completionTime = block.timestamp - goal.createdAt;
        bool wasEarlyCompletion = block.timestamp < goal.endTime - 7 days;
        bool allMilestonesCompleted = goal.milestonesCompleted >= goal.totalMilestones;
        
        // Return stake with rewards
        uint256 stakeReward = treasuryManager.distributeGoalReward(goal.owner, goal.stakeAmount);
        
        emit GoalCompleted(
            goalId,
            goal.owner,
            100, // Completion bonus XP
            stakeReward,
            completionTime,
            wasEarlyCompletion,
            allMilestonesCompleted,
            finalMetadataIPFS,
            block.timestamp
        );
    }
    
    function failGoal(uint256 goalId, string calldata sadPetMetadataIPFS) external {
        Goal storage goal = goals[goalId];
        
        if (msg.sender != goal.owner && 
            msg.sender != owner() && 
            block.timestamp <= goal.endTime) {
            revert NotAuthorized();
        }
        if (goal.status != GoalStatus.ACTIVE) revert GoalNotActive();
        
        goal.status = GoalStatus.FAILED;
        
        // Distribute failed stake
        treasuryManager.distributeFailedStake(goal.stakeAmount, goal.owner);
        
        string memory failureReason = _getFailureReason(goal.endTime);
        
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
    }
    
    function _getFailureReason(uint256 goalEndTime) internal view returns (string memory) {
        if (block.timestamp > goalEndTime) {
            return "Time expired";
        } else if (msg.sender == goals[0].owner) {
            return "Owner abandoned";
        } else {
            return "Admin intervention";
        }
    }
    
    function createGoalWithMilestones(
        string calldata title,
        uint256 stakeAmount,
        uint32 durationDays,
        string calldata petName,
        PatNFT.PetType petType,
        string calldata petMetadataIPFS,
        string[] calldata milestoneDescriptions
    ) external nonReentrant returns (uint256) {
        uint8 totalMilestones = uint8(milestoneDescriptions.length);
        
        if (stakeAmount == 0) revert InvalidStake();
        if (durationDays == 0) revert InvalidDuration();
        if (totalMilestones == 0) revert NeedMilestones();
        if (totalMilestones > MAX_MILESTONES) revert TooManyMilestones();
        
        // Create goal
        uint256 goalId = _createGoalInternal(
            title,
            stakeAmount,
            durationDays,
            petName,
            petType,
            petMetadataIPFS,
            totalMilestones
        );
        
        // Create milestones
        for (uint256 i = 0; i < milestoneDescriptions.length; i++) {
            uint256 milestoneId = nextMilestoneId++;
            
            milestones[milestoneId] = Milestone({
                goalId: goalId,
                description: milestoneDescriptions[i],
                isCompleted: false,
                evidenceIPFS: "",
                createdAt: block.timestamp,
                completedAt: 0
            });
            
            goalMilestones[goalId].push(milestoneId);
            
            emit MilestoneCreated(milestoneId, goalId, msg.sender, milestoneDescriptions[i], block.timestamp);
        }
        
        return goalId;
    }
    
    function addBonusXP(
        uint256 goalId,
        uint256 xpAmount,
        string calldata reason,
        string calldata newPetMetadataIPFS
    ) external onlyOwner {
        Goal storage goal = goals[goalId];
        if (goal.status != GoalStatus.ACTIVE) revert GoalNotActive();
        
        petNFT.addExperienceWithMetadata(goal.petTokenId, xpAmount, newPetMetadataIPFS);
        
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
    
    // View functions
    function isGoalActive(uint256 goalId) external view returns (bool) {
        return goals[goalId].status == GoalStatus.ACTIVE;
    }
    
    function isGoalExpired(uint256 goalId) external view returns (bool) {
        return block.timestamp > goals[goalId].endTime;
    }
    
    function getUserGoals(address user) external view returns (uint256[] memory) {
        return userGoals[user];
    }
    
    function getGoalMilestones(uint256 goalId) external view returns (uint256[] memory) {
        return goalMilestones[goalId];
    }
    
    function getGoalBasicInfo(uint256 goalId) external view returns (
        address owner,
        uint256 stakeAmount,
        uint256 endTime,
        GoalStatus status,
        uint8 milestonesCompleted,
        uint8 totalMilestones
    ) {
        Goal storage goal = goals[goalId];
        return (
            goal.owner,
            goal.stakeAmount,
            goal.endTime,
            goal.status,
            goal.milestonesCompleted,
            goal.totalMilestones
        );
    }
    
    function getGoalFullInfo(uint256 goalId) external view returns (Goal memory) {
        return goals[goalId];
    }
    
    function getMilestoneFullInfo(uint256 milestoneId) external view returns (Milestone memory) {
        return milestones[milestoneId];
    }
    
    function getEvolutionInfo() external view returns (
        uint256 babyMilestoneThreshold,
        uint256 adultMilestoneThreshold,
        uint256 maxMilestones,
        uint256 xpPerMilestone,
        uint256 completionBonusXP
    ) {
        (
            uint256 babyThreshold,
            uint256 adultThreshold,
            uint256 milestoneXP,
            uint256 bonusXP
        ) = petNFT.getEvolutionThresholds();
        
        return (
            babyThreshold,
            adultThreshold,
            MAX_MILESTONES,
            milestoneXP,
            bonusXP
        );
    }
    
    function getSystemStats() external view returns (
        uint256 totalGoals,
        uint256 totalMilestones,
        uint256 maxMilestonesPerGoal
    ) {
        return (
            nextGoalId,
            nextMilestoneId,
            MAX_MILESTONES
        );
    }
}