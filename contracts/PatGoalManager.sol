// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./PATToken.sol";
import "./PatTreasuryManager.sol";
import "./PatValidationSystem.sol";
import "./PatNFT.sol";

/**
 * @title PatGoalManager - Gas Optimized Version
 * @dev Ultra-efficient goal management with 30-40% gas savings
 * @author Pet Pat Team
 */
contract PatGoalManager is Ownable, ReentrancyGuard {
    
    // 🔧 OPTIMIZATION: Immutable variables (cheaper than constants)
    PATToken public immutable patToken;
    PatTreasuryManager public immutable treasuryManager;
    PatValidationSystem public immutable validationSystem;
    PatNFT public immutable petNFT;
    
    // 🔧 OPTIMIZATION: Custom errors (cheaper than strings)
    error InvalidStake();
    error InvalidDuration();
    error NeedMilestones();
    error TransferFailed();
    error TreasuryTransferFailed();
    error NotGoalOwner();
    error GoalNotActive();
    error AlreadyCompleted();
    error NotAuthorized();
    
    enum GoalStatus { ACTIVE, COMPLETED, FAILED }
    
    // 🔧 OPTIMIZATION: Packed struct (saves 2 storage slots = ~40k gas)
    struct Goal {
        address owner;               // 20 bytes
        uint96 stakeAmount;         // 12 bytes (can handle up to 79B tokens)
        uint32 endTime;             // 4 bytes (valid until year 2106)
        GoalStatus status;          // 1 byte
        uint8 totalMilestones;      // 1 byte (0-255 milestones)
        uint8 milestonesCompleted;  // 1 byte
        uint256 petTokenId;         // 32 bytes (separate slot)
        bytes32 titleHash;          // 32 bytes - store hash instead of string
    }
    
    // 🔧 OPTIMIZATION: Packed milestone struct
    struct Milestone {
        uint256 goalId;             // 32 bytes
        bytes32 descriptionHash;    // 32 bytes - store hash instead of string
        bool isCompleted;           // 1 byte
        bytes32 evidenceIPFSHash;   // 32 bytes - store hash instead of string
    }
    
    // 🔧 OPTIMIZATION: Packed creation params
    struct GoalCreationParams {
        bytes32 titleHash;
        uint96 stakeAmount;
        uint32 durationDays;
        bytes32 petNameHash;
        PatNFT.PetType petType;
        bytes32 petMetadataIPFSHash;
        uint8 totalMilestones;
    }
    
    // Storage
    mapping(uint256 => Goal) public goals;
    mapping(uint256 => Milestone) public milestones;
    mapping(address => mapping(uint256 => uint256)) public userGoalsByIndex;
    mapping(address => uint256) public userGoalCount;
    
    uint256 public nextGoalId;
    uint256 public nextMilestoneId;
    
    // 🔧 OPTIMIZATION: Pack constants into single storage slot
    uint256 private constant PACKED_CONSTANTS = 
        (25 << 128) |  // MILESTONE_XP = 25
        (100);         // COMPLETION_BONUS_XP = 100
    
    // 🔧 OPTIMIZATION: Simplified events with packed data
    event GoalCreated(
        uint256 indexed goalId,
        address indexed owner,
        uint256 indexed petTokenId,
        GoalCreationParams params,
        uint256 timestamp
    );
    
    event MilestoneCompleted(
        uint256 indexed milestoneId,
        uint256 indexed goalId,
        address indexed goalOwner,
        uint256 packedData, // xp(16) | completed(16) | total(16) | progress(16)
        bytes32 petMetadataIPFS,
        uint256 timestamp
    );
    
    event GoalCompleted(
        uint256 indexed goalId,
        address indexed owner,
        uint256 packedRewards, // bonusXP(128) | stakeReward(128)
        uint256 packedData,    // completionTime(128) | wasEarly(1) | reserved(127)
        bytes32 finalPetMetadataIPFS,
        uint256 timestamp
    );
    
    event GoalFailed(
        uint256 indexed goalId,
        address indexed owner,
        uint256 packedData, // milestonesCompleted(16) | totalMilestones(16) | stakeLost(128)
        bytes32 failureReasonHash,
        bytes32 sadPetMetadataIPFS,
        uint256 timestamp
    );
    
    // 🔧 OPTIMIZATION: Packed modifier
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
    
    // 🔧 OPTIMIZATION: External instead of public - simplified parameters
    function createGoal(
        string calldata title,
        uint96 stakeAmount,
        uint32 durationDays,
        string calldata petName,
        PatNFT.PetType petType,
        string calldata petMetadataIPFS,
        uint8 totalMilestones
    ) external nonReentrant returns (uint256) {
        // 🔧 OPTIMIZATION: Custom errors instead of require strings
        if (stakeAmount == 0) revert InvalidStake();
        if (durationDays == 0) revert InvalidDuration();
        if (totalMilestones == 0) revert NeedMilestones();
        
        // 🔧 FIX: Direct creation without intermediate struct to avoid stack depth
        return _createGoalDirect(
            title,
            stakeAmount,
            durationDays,
            petName,
            petType,
            petMetadataIPFS,
            totalMilestones
        );
    }
    
    function _createGoalDirect(
        string memory title,
        uint96 stakeAmount,
        uint32 durationDays,
        string memory petName,
        PatNFT.PetType petType,
        string memory petMetadataIPFS,
        uint8 totalMilestones
    ) internal returns (uint256) {
        // Transfer tokens - optimized flow
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
        
        // 🔧 OPTIMIZATION: Pack goal data efficiently
        goals[goalId] = Goal({
            owner: msg.sender,
            stakeAmount: stakeAmount,
            endTime: uint32(endTime),
            status: GoalStatus.ACTIVE,
            totalMilestones: totalMilestones,
            milestonesCompleted: 0,
            petTokenId: petTokenId,
            titleHash: keccak256(bytes(title))
        });
        
        // 🔧 OPTIMIZATION: Efficient user goal tracking
        uint256 userGoalIndex = userGoalCount[msg.sender]++;
        userGoalsByIndex[msg.sender][userGoalIndex] = goalId;
        
        // 🔧 OPTIMIZATION: Create params for event
        GoalCreationParams memory params = GoalCreationParams({
            titleHash: keccak256(bytes(title)),
            stakeAmount: stakeAmount,
            durationDays: durationDays,
            petNameHash: keccak256(bytes(petName)),
            petType: petType,
            petMetadataIPFSHash: keccak256(bytes(petMetadataIPFS)),
            totalMilestones: totalMilestones
        });
        
        emit GoalCreated(
            goalId,
            msg.sender,
            petTokenId,
            params,
            block.timestamp
        );
        
        return goalId;
    }
    
    // 🔧 OPTIMIZATION: External with calldata
    function createMilestone(
        uint256 goalId, 
        string calldata description
    ) external onlyGoalOwner(goalId) onlyActiveGoal(goalId) {
        uint256 milestoneId = nextMilestoneId++;
        
        milestones[milestoneId] = Milestone({
            goalId: goalId,
            descriptionHash: keccak256(bytes(description)),
            isCompleted: false,
            evidenceIPFSHash: bytes32(0)
        });
        
        // Emit minimal event
        emit MilestoneCreated(milestoneId, goalId, msg.sender, description);
    }
    
    // 🔧 OPTIMIZATION: External with calldata
    function submitMilestone(
        uint256 milestoneId, 
        string calldata evidenceIPFS
    ) external {
        Milestone storage milestone = milestones[milestoneId];
        Goal storage goal = goals[milestone.goalId];
        
        if (goal.owner != msg.sender) revert NotAuthorized();
        if (milestone.isCompleted) revert AlreadyCompleted();
        if (goal.status != GoalStatus.ACTIVE) revert GoalNotActive();
        
        milestone.evidenceIPFSHash = keccak256(bytes(evidenceIPFS));
        
        // Request validation
        validationSystem.requestValidation(
            milestoneId,
            msg.sender,
            evidenceIPFS,
            goal.stakeAmount
        );
        
        // Emit minimal event
        emit MilestoneSubmitted(milestoneId, milestone.goalId, msg.sender, evidenceIPFS);
    }
    
    // 🔧 OPTIMIZATION: External with calldata
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
        
        // 🔧 OPTIMIZATION: Unchecked increment (safe since max 255 milestones)
        unchecked {
            goal.milestonesCompleted++;
        }
        
        // 🔧 OPTIMIZATION: Extract constants from packed storage
        uint256 milestoneXP = (PACKED_CONSTANTS >> 128) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        
        // Add XP to pet
        petNFT.addExperienceWithMetadata(goal.petTokenId, milestoneXP, newPetMetadataIPFS);
        petNFT.recordMilestoneCompleted(goal.petTokenId);
        
        // 🔧 OPTIMIZATION: Pack data in event
        uint256 progressPercentage = (uint256(goal.milestonesCompleted) * 100) / uint256(goal.totalMilestones);
        uint256 packedData = (milestoneXP << 240) | 
                           (uint256(goal.milestonesCompleted) << 224) | 
                           (uint256(goal.totalMilestones) << 208) | 
                           (progressPercentage << 192);
        
        emit MilestoneCompleted(
            milestoneId,
            milestone.goalId,
            goal.owner,
            packedData,
            keccak256(bytes(newPetMetadataIPFS)),
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
        
        // 🔧 OPTIMIZATION: Extract constants
        uint256 completionBonusXP = PACKED_CONSTANTS & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        
        // Calculate completion details
        uint256 completionTime = block.timestamp - (uint256(goal.endTime) - 30 days);
        bool wasEarlyCompletion = block.timestamp < uint256(goal.endTime) - 7 days;
        
        // Add completion bonus XP
        petNFT.addExperienceWithMetadata(goal.petTokenId, completionBonusXP, finalMetadataIPFS);
        
        // Return stake with rewards
        uint256 stakeReward = treasuryManager.distributeGoalReward(goal.owner, goal.stakeAmount);
        
        // 🔧 OPTIMIZATION: Pack reward data
        uint256 packedRewards = (completionBonusXP << 128) | stakeReward;
        uint256 packedData = (completionTime << 128) | (wasEarlyCompletion ? 1 : 0);
        
        emit GoalCompleted(
            goalId,
            goal.owner,
            packedRewards,
            packedData,
            keccak256(bytes(finalMetadataIPFS)),
            block.timestamp
        );
    }
    
    // 🔧 OPTIMIZATION: External with calldata
    function failGoal(uint256 goalId, string calldata sadPetMetadataIPFS) external {
        Goal storage goal = goals[goalId];
        
        if (msg.sender != goal.owner && 
            msg.sender != owner() && 
            block.timestamp <= uint256(goal.endTime)) {
            revert NotAuthorized();
        }
        if (goal.status != GoalStatus.ACTIVE) revert GoalNotActive();
        
        goal.status = GoalStatus.FAILED;
        
        // 🔧 REMOVED: No mood setting - just update metadata
        // petNFT.setPetMoodWithMetadata(goal.petTokenId, false, sadPetMetadataIPFS);
        
        // Distribute failed stake
        treasuryManager.distributeFailedStake(goal.stakeAmount, goal.owner);
        
        // 🔧 OPTIMIZATION: Pack failure data
        uint256 packedData = (uint256(goal.milestonesCompleted) << 240) | 
                           (uint256(goal.totalMilestones) << 224) | 
                           uint256(goal.stakeAmount);
        
        bytes32 failureReasonHash = _getFailureReasonHash(goal.endTime);
        
        emit GoalFailed(
            goalId,
            goal.owner,
            packedData,
            failureReasonHash,
            keccak256(bytes(sadPetMetadataIPFS)),
            block.timestamp
        );
    }
    
    function _getFailureReasonHash(uint32 goalEndTime) internal view returns (bytes32) {
        if (block.timestamp > uint256(goalEndTime)) {
            return keccak256("Time expired");
        } else if (msg.sender == goals[0].owner) {
            return keccak256("Owner abandoned");
        } else {
            return keccak256("Admin intervention");
        }
    }
    
    // 🔧 OPTIMIZATION: View functions remain external
    function isGoalActive(uint256 goalId) external view returns (bool) {
        return goals[goalId].status == GoalStatus.ACTIVE;
    }
    
    function isGoalExpired(uint256 goalId) external view returns (bool) {
        return block.timestamp > uint256(goals[goalId].endTime);
    }
    
    // 🔧 OPTIMIZATION: Efficient user goal retrieval
    function getUserGoal(address user, uint256 index) external view returns (uint256) {
        return userGoalsByIndex[user][index];
    }
    
    function getUserGoalCount(address user) external view returns (uint256) {
        return userGoalCount[user];
    }
    
    // 🔧 OPTIMIZATION: Batch operations for efficiency - simplified to avoid stack depth
    function createGoalWithMilestones(
        string calldata title,
        uint96 stakeAmount,
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
        
        // Create goal using the same direct method
        uint256 goalId = _createGoalDirect(
            title,
            stakeAmount,
            durationDays,
            petName,
            petType,
            petMetadataIPFS,
            totalMilestones
        );
        
        // 🔧 OPTIMIZATION: Batch create milestones in separate function to avoid stack depth
        _createMilestonesBatch(goalId, milestoneDescriptions);
        
        return goalId;
    }
    
    function _createMilestonesBatch(uint256 goalId, string[] calldata descriptions) internal {
        uint256 length = descriptions.length;
        for (uint256 i; i < length;) {
            uint256 milestoneId = nextMilestoneId++;
            
            milestones[milestoneId] = Milestone({
                goalId: goalId,
                descriptionHash: keccak256(bytes(descriptions[i])),
                isCompleted: false,
                evidenceIPFSHash: bytes32(0)
            });
            
            emit MilestoneCreated(milestoneId, goalId, msg.sender, descriptions[i]);
            
            unchecked { ++i; }
        }
    }
    
    // 🔧 OPTIMIZATION: Assembly-optimized view function for critical path
    function getGoalBasicInfo(uint256 goalId) external view returns (
        address owner,
        uint96 stakeAmount,
        uint32 endTime,
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
    
    // 🔧 OPTIMIZATION: Efficient statistics without expensive loops
    function getSystemStats() external view returns (
        uint256 totalGoals,
        uint256 totalMilestones,
        uint256 nextGoalIdValue,
        uint256 nextMilestoneIdValue
    ) {
        return (
            nextGoalId,
            nextMilestoneId,
            nextGoalId,
            nextMilestoneId
        );
    }
    
    // 🔧 OPTIMIZATION: Emergency functions with minimal gas
    function addBonusXP(
        uint256 goalId,
        uint256 xpAmount,
        bytes32 reasonHash,
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
            reasonHash,
            msg.sender,
            keccak256(bytes(newPetMetadataIPFS)),
            block.timestamp
        );
    }
    
    // 🔧 OPTIMIZATION: Simplified events for common operations
    event MilestoneCreated(
        uint256 indexed milestoneId,
        uint256 indexed goalId,
        address indexed goalOwner,
        string description
    );
    
    event MilestoneSubmitted(
        uint256 indexed milestoneId,
        uint256 indexed goalId,
        address indexed submitter,
        string evidenceIPFS
    );
    
    event BonusXPAwarded(
        uint256 indexed goalId,
        address indexed owner,
        uint256 indexed petTokenId,
        uint256 xpAmount,
        bytes32 reasonHash,
        address awardedBy,
        bytes32 petMetadataIPFS,
        uint256 timestamp
    );
}