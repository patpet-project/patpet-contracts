// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./PATToken.sol";
import "./PatTreasuryManager.sol";

/**
 * @title PatValidationSystem - Clean & Integration-Friendly Version
 * @dev Community validation with clean events and readable data structures
 */
contract PatValidationSystem is Ownable, ReentrancyGuard {
    using Math for uint256;
    
    PATToken public patToken;
    PatTreasuryManager public treasuryManager;
    
    enum ValidationStatus { PENDING, APPROVED, REJECTED, DISPUTED }
    
    // Clean Validator struct
    struct Validator {
        address validatorAddress;
        uint256 stakedAmount;
        uint256 reputationScore;
        uint256 totalValidations;
        uint256 accurateValidations;
        bool isActive;
        uint256 registrationTime;
        uint256 lastValidationTime;
    }
    
    // Clean ValidationRequest struct
    struct ValidationRequest {
        uint256 milestoneId;
        address submitter;
        string evidenceIPFS;
        uint256 goalStakeAmount;
        uint256 requiredValidators;
        address[] assignedValidators;
        mapping(address => bool) hasVoted;
        mapping(address => bool) votes;
        mapping(address => string) comments;
        uint256 approvals;
        uint256 rejections;
        uint256 deadline;
        ValidationStatus status;
        bool isResolved;
        uint256 createdAt;
        uint256 resolvedAt;
    }
    
    // Constants
    uint256 public constant MIN_VALIDATOR_STAKE = 50 * 10**18;
    uint256 public constant VALIDATION_REWARD_BASE = 5 * 10**18;
    uint256 public constant VALIDATION_DEADLINE = 72 hours;
    uint256 public constant TIER_1_VALIDATORS = 3;
    uint256 public constant TIER_2_VALIDATORS = 5;
    uint256 public constant TIER_3_VALIDATORS = 7;
    
    // Storage
    mapping(address => Validator) public validators;
    mapping(uint256 => ValidationRequest) public validationRequests;
    address[] public activeValidators;
    
    // Statistics
    uint256 public totalValidationRequests;
    uint256 public totalValidationsCompleted;
    uint256 public totalValidatorRewardsDistributed;
    
    mapping(address => bool) public authorizedContracts;
    
    // Clean, readable events
    event ValidationSystemInitialized(
        address indexed owner,
        address indexed patToken,
        address indexed treasuryManager,
        uint256 minValidatorStake,
        uint256 validationRewardBase,
        uint256 validationDeadline,
        uint256 timestamp
    );
    
    event ValidatorRegistered(
        address indexed validator,
        uint256 stakedAmount,
        uint256 initialReputationScore,
        uint256 totalActiveValidators,
        uint256 timestamp
    );
    
    event ValidatorDeactivated(
        address indexed validator,
        string reason,
        uint256 stakedAmountReturned,
        uint256 finalReputationScore,
        uint256 totalValidationsCompleted,
        uint256 accuracyRate, // basis points
        address indexed deactivatedBy,
        uint256 timestamp
    );
    
    event ValidationRequested(
        uint256 indexed milestoneId,
        address indexed submitter,
        string evidenceIPFS,
        uint256 goalStakeAmount,
        uint256 requiredValidators,
        address[] assignedValidators,
        uint256 deadline,
        uint256 timestamp
    );
    
    event ValidatorAssigned(
        uint256 indexed milestoneId,
        address indexed validator,
        uint256 validatorReputationScore,
        uint256 validatorTotalValidations,
        uint256 assignmentIndex,
        uint256 timestamp
    );
    
    event ValidationSubmitted(
        uint256 indexed milestoneId,
        address indexed validator,
        bool approved,
        string comment,
        uint256 currentApprovals,
        uint256 currentRejections,
        uint256 requiredValidators,
        uint256 timestamp
    );
    
    event ValidationResolved(
        uint256 indexed milestoneId,
        ValidationStatus status,
        uint256 totalApprovals,
        uint256 totalRejections,
        uint256 totalValidators,
        address[] validators,
        bool[] votes,
        uint256 resolutionTime,
        uint256 timestamp
    );
    
    event ValidatorRewarded(
        address indexed validator,
        uint256 indexed milestoneId,
        uint256 amount,
        bool wasAccurate,
        uint256 bonusPercentage,
        uint256 newReputationScore,
        string reason,
        uint256 timestamp
    );
    
    event ReputationUpdated(
        address indexed validator,
        uint256 oldReputationScore,
        uint256 newReputationScore,
        bool wasAccurate,
        uint256 totalValidations,
        uint256 accurateValidations,
        uint256 accuracyRate, // basis points
        string reason,
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
    
    modifier onlyActiveValidator() {
        require(validators[msg.sender].isActive, "Not an active validator");
        _;
    }
    
    constructor(address _patToken, address _treasuryManager) Ownable(msg.sender) {
        patToken = PATToken(_patToken);
        treasuryManager = PatTreasuryManager(_treasuryManager);
        
        emit ValidationSystemInitialized(
            msg.sender,
            _patToken,
            _treasuryManager,
            MIN_VALIDATOR_STAKE,
            VALIDATION_REWARD_BASE,
            VALIDATION_DEADLINE,
            block.timestamp
        );
    }
    
    function registerValidator(uint256 stakeAmount) external nonReentrant {
        require(stakeAmount >= MIN_VALIDATOR_STAKE, "Insufficient stake amount");
        require(!validators[msg.sender].isActive, "Already registered as validator");
        require(patToken.transferFrom(msg.sender, address(this), stakeAmount), "Stake transfer failed");
        
        validators[msg.sender] = Validator({
            validatorAddress: msg.sender,
            stakedAmount: stakeAmount,
            reputationScore: 1000,
            totalValidations: 0,
            accurateValidations: 0,
            isActive: true,
            registrationTime: block.timestamp,
            lastValidationTime: 0
        });
        
        activeValidators.push(msg.sender);
        
        emit ValidatorRegistered(
            msg.sender,
            stakeAmount,
            1000, // initial reputation
            activeValidators.length,
            block.timestamp
        );
    }
    
    function deactivateValidator() external nonReentrant onlyActiveValidator {
        Validator storage validator = validators[msg.sender];
        
        uint256 accuracyRate = validator.totalValidations > 0 ? 
            (validator.accurateValidations * 10000) / validator.totalValidations : 0;
        
        // Return stake
        require(patToken.transfer(msg.sender, validator.stakedAmount), "Stake return failed");
        
        validator.isActive = false;
        _removeFromActiveValidators(msg.sender);
        
        emit ValidatorDeactivated(
            msg.sender,
            "Self-deactivation",
            validator.stakedAmount,
            validator.reputationScore,
            validator.totalValidations,
            accuracyRate,
            msg.sender,
            block.timestamp
        );
    }
    
    function requestValidation(
        uint256 milestoneId,
        address submitter,
        string memory evidenceIPFS,
        uint256 goalStakeAmount
    ) external onlyAuthorized {
        require(bytes(evidenceIPFS).length > 0, "Evidence IPFS hash required");
        
        uint256 requiredValidators = _getRequiredValidators(goalStakeAmount);
        require(activeValidators.length >= requiredValidators, "Insufficient active validators");
        
        ValidationRequest storage request = validationRequests[milestoneId];
        request.milestoneId = milestoneId;
        request.submitter = submitter;
        request.evidenceIPFS = evidenceIPFS;
        request.goalStakeAmount = goalStakeAmount;
        request.requiredValidators = requiredValidators;
        request.deadline = block.timestamp + VALIDATION_DEADLINE;
        request.status = ValidationStatus.PENDING;
        request.createdAt = block.timestamp;
        
        // Assign validators
        _assignValidators(milestoneId, requiredValidators);
        
        totalValidationRequests += 1;
        
        emit ValidationRequested(
            milestoneId,
            submitter,
            evidenceIPFS,
            goalStakeAmount,
            requiredValidators,
            request.assignedValidators,
            request.deadline,
            block.timestamp
        );
    }
    
    function submitValidation(
        uint256 milestoneId,
        bool approve,
        string memory comment
    ) external onlyActiveValidator nonReentrant {
        ValidationRequest storage request = validationRequests[milestoneId];
        
        require(request.status == ValidationStatus.PENDING, "Validation not pending");
        require(block.timestamp <= request.deadline, "Validation deadline passed");
        require(!request.hasVoted[msg.sender], "Already voted");
        require(_isAssignedValidator(milestoneId, msg.sender), "Not assigned to this validation");
        
        // Record vote
        request.hasVoted[msg.sender] = true;
        request.votes[msg.sender] = approve;
        request.comments[msg.sender] = comment;
        
        if (approve) {
            request.approvals += 1;
        } else {
            request.rejections += 1;
        }
        
        // Update validator stats
        validators[msg.sender].totalValidations += 1;
        validators[msg.sender].lastValidationTime = block.timestamp;
        
        emit ValidationSubmitted(
            milestoneId,
            msg.sender,
            approve,
            comment,
            request.approvals,
            request.rejections,
            request.requiredValidators,
            block.timestamp
        );
        
        // Check if validation is complete
        if (request.approvals + request.rejections >= request.requiredValidators) {
            _resolveValidation(milestoneId);
        }
    }
    
    function _resolveValidation(uint256 milestoneId) internal {
        ValidationRequest storage request = validationRequests[milestoneId];
        
        // Determine final status
        if (request.approvals > request.rejections) {
            request.status = ValidationStatus.APPROVED;
        } else {
            request.status = ValidationStatus.REJECTED;
        }
        
        request.isResolved = true;
        request.resolvedAt = block.timestamp;
        
        // Prepare data for event
        bool[] memory votes = new bool[](request.assignedValidators.length);
        for (uint256 i = 0; i < request.assignedValidators.length; i++) {
            votes[i] = request.votes[request.assignedValidators[i]];
        }
        
        emit ValidationResolved(
            milestoneId,
            request.status,
            request.approvals,
            request.rejections,
            request.assignedValidators.length,
            request.assignedValidators,
            votes,
            block.timestamp - request.createdAt,
            block.timestamp
        );
        
        // Distribute rewards
        _distributeValidatorRewards(milestoneId);
        
        totalValidationsCompleted += 1;
    }
    
    function _distributeValidatorRewards(uint256 milestoneId) internal {
        ValidationRequest storage request = validationRequests[milestoneId];
        bool finalDecision = request.status == ValidationStatus.APPROVED;
        
        uint256 baseReward = VALIDATION_REWARD_BASE;
        
        for (uint256 i = 0; i < request.assignedValidators.length; i++) {
            address validatorAddr = request.assignedValidators[i];
            
            if (request.hasVoted[validatorAddr]) {
                bool validatorVote = request.votes[validatorAddr];
                bool wasAccurate = (validatorVote == finalDecision);
                
                uint256 reward = baseReward;
                uint256 bonusPercentage = 0;
                string memory rewardReason;
                
                if (wasAccurate) {
                    bonusPercentage = 25; // 25% bonus
                    reward = reward + ((baseReward * bonusPercentage) / 100);
                    validators[validatorAddr].accurateValidations += 1;
                    rewardReason = "Accurate validation with bonus";
                } else {
                    reward = (reward * 50) / 100; // 50% penalty
                    rewardReason = "Inaccurate validation with penalty";
                }
                
                // Update reputation
                uint256 oldReputation = validators[validatorAddr].reputationScore;
                _updateReputation(validatorAddr, wasAccurate);
                
                // Distribute reward
                treasuryManager.distributeValidatorReward(validatorAddr, reward);
                totalValidatorRewardsDistributed += reward;
                
                emit ValidatorRewarded(
                    validatorAddr,
                    milestoneId,
                    reward,
                    wasAccurate,
                    bonusPercentage,
                    validators[validatorAddr].reputationScore,
                    rewardReason,
                    block.timestamp
                );
            }
        }
    }
    
    function _updateReputation(address validatorAddr, bool wasAccurate) internal {
        Validator storage validator = validators[validatorAddr];
        uint256 oldReputation = validator.reputationScore;
        string memory reason;
        
        if (wasAccurate) {
            validator.reputationScore += 10;
            if (validator.reputationScore > 2000) {
                validator.reputationScore = 2000;
            }
            reason = "Accurate validation";
        } else {
            if (validator.reputationScore > 10) {
                validator.reputationScore -= 10;
            }
            reason = "Inaccurate validation";
        }
        
        uint256 accuracyRate = validator.totalValidations > 0 ? 
            (validator.accurateValidations * 10000) / validator.totalValidations : 0;
        
        emit ReputationUpdated(
            validatorAddr,
            oldReputation,
            validator.reputationScore,
            wasAccurate,
            validator.totalValidations,
            validator.accurateValidations,
            accuracyRate,
            reason,
            block.timestamp
        );
        
        // Deactivate if reputation too low
        if (validator.reputationScore < 500) {
            validator.isActive = false;
            _removeFromActiveValidators(validatorAddr);
            
            emit ValidatorDeactivated(
                validatorAddr,
                "Low reputation",
                0, // No stake returned for poor performance
                validator.reputationScore,
                validator.totalValidations,
                accuracyRate,
                address(this),
                block.timestamp
            );
        }
    }
    
    function _assignValidators(uint256 milestoneId, uint256 requiredValidators) internal {
        ValidationRequest storage request = validationRequests[milestoneId];
        
        uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, milestoneId, block.prevrandao)));
        
        for (uint256 i = 0; i < requiredValidators && i < activeValidators.length; i++) {
            uint256 index = (seed + i) % activeValidators.length;
            address validator = activeValidators[index];
            
            bool alreadyAssigned = false;
            for (uint256 j = 0; j < request.assignedValidators.length; j++) {
                if (request.assignedValidators[j] == validator) {
                    alreadyAssigned = true;
                    break;
                }
            }
            
            if (!alreadyAssigned && validators[validator].isActive) {
                request.assignedValidators.push(validator);
                
                emit ValidatorAssigned(
                    milestoneId,
                    validator,
                    validators[validator].reputationScore,
                    validators[validator].totalValidations,
                    request.assignedValidators.length - 1,
                    block.timestamp
                );
            }
        }
    }
    
    function _isAssignedValidator(uint256 milestoneId, address validator) internal view returns (bool) {
        ValidationRequest storage request = validationRequests[milestoneId];
        
        for (uint256 i = 0; i < request.assignedValidators.length; i++) {
            if (request.assignedValidators[i] == validator) {
                return true;
            }
        }
        return false;
    }
    
    function _getRequiredValidators(uint256 stakeAmount) internal pure returns (uint256) {
        if (stakeAmount < 500 * 10**18) {
            return TIER_1_VALIDATORS;
        } else if (stakeAmount < 2000 * 10**18) {
            return TIER_2_VALIDATORS;
        } else {
            return TIER_3_VALIDATORS;
        }
    }
    
    function _removeFromActiveValidators(address validator) internal {
        for (uint256 i = 0; i < activeValidators.length; i++) {
            if (activeValidators[i] == validator) {
                activeValidators[i] = activeValidators[activeValidators.length - 1];
                activeValidators.pop();
                break;
            }
        }
    }
    
    function forceResolveValidation(uint256 milestoneId, ValidationStatus status, string memory reason) 
        external onlyOwner {
        ValidationRequest storage request = validationRequests[milestoneId];
        require(!request.isResolved, "Already resolved");
        
        request.status = status;
        request.isResolved = true;
        request.resolvedAt = block.timestamp;
        
        bool[] memory emptyVotes = new bool[](0);
        address[] memory emptyValidators = new address[](0);
        
        emit ValidationResolved(
            milestoneId,
            status,
            request.approvals,
            request.rejections,
            0,
            emptyValidators,
            emptyVotes,
            block.timestamp - request.createdAt,
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
    
    // View functions
    function getValidatorInfo(address validatorAddr) external view returns (Validator memory) {
        return validators[validatorAddr];
    }
    
    function getValidationRequestBasicInfo(uint256 milestoneId) external view returns (
        uint256 milestoneIdReturn,
        address submitter,
        string memory evidenceIPFS,
        uint256 goalStakeAmount,
        uint256 requiredValidators,
        uint256 approvals,
        uint256 rejections,
        uint256 deadline,
        ValidationStatus status,
        bool isResolved
    ) {
        ValidationRequest storage request = validationRequests[milestoneId];
        return (
            request.milestoneId,
            request.submitter,
            request.evidenceIPFS,
            request.goalStakeAmount,
            request.requiredValidators,
            request.approvals,
            request.rejections,
            request.deadline,
            request.status,
            request.isResolved
        );
    }
    
    function getValidationRequestValidators(uint256 milestoneId) external view returns (address[] memory) {
        return validationRequests[milestoneId].assignedValidators;
    }
    
    function getValidatorVote(uint256 milestoneId, address validator) external view returns (bool hasVoted, bool vote, string memory comment) {
        ValidationRequest storage request = validationRequests[milestoneId];
        return (
            request.hasVoted[validator],
            request.votes[validator],
            request.comments[validator]
        );
    }
    
    function getActiveValidators() external view returns (address[] memory) {
        return activeValidators;
    }
    
    function getSystemStats() external view returns (
        uint256 totalRequests,
        uint256 totalCompleted,
        uint256 totalActiveValidatorsCount,
        uint256 totalRewardsDistributed
    ) {
        return (
            totalValidationRequests,
            totalValidationsCompleted,
            activeValidators.length,
            totalValidatorRewardsDistributed
        );
    }
}