// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PatNFT - Clean & Integration-Friendly Version
 * @dev Dynamic NFT with milestone-based evolution, simplified for easy integration
 */
contract PatNFT is ERC721, Ownable {
    
    uint256 private _nextTokenId;
    
    enum PetType { DRAGON, CAT, PLANT }
    enum EvolutionStage { EGG, BABY, ADULT }
    
    // Simplified Pet struct - stores actual data instead of hashes
    struct Pet {
        address owner;
        uint256 experience;
        uint256 level;
        uint256 birthTime;
        uint256 goalId;
        uint8 milestonesCompleted;
        PetType petType;
        EvolutionStage stage;
        string name;
        string metadataIPFS;  // Store actual IPFS hash, not keccak256
    }
    
    // Storage
    mapping(uint256 => Pet) public pets;
    mapping(address => uint256[]) public ownerPets;
    mapping(address => bool) public authorizedContracts;
    
    // Evolution thresholds
    uint256 public constant BABY_MILESTONE_THRESHOLD = 2;
    uint256 public constant ADULT_MILESTONE_THRESHOLD = 4;
    uint256 public constant XP_PER_MILESTONE = 25;
    uint256 public constant COMPLETION_BONUS_XP = 100;
    
    string public baseTokenURI = "https://emerald-quiet-bobcat-167.mypinata.cloud/ipfs/";
    
    // Custom errors
    error PetDoesNotExist();
    error NotAuthorized();
    error ZeroAddress();
    error MaxMilestonesReached();
    
    // Clean, readable events
    event PetMinted(
        uint256 indexed tokenId,
        address indexed owner,
        address indexed minter,
        uint256 goalId,
        PetType petType,
        EvolutionStage stage,
        uint256 level,
        string name,
        string metadataIPFS,
        uint256 timestamp
    );
    
    event MilestoneCompleted(
        uint256 indexed tokenId,
        uint256 indexed goalId,
        address indexed owner,
        uint256 xpAwarded,
        uint256 newMilestones,
        uint256 newLevel,
        EvolutionStage newStage,
        string newMetadataIPFS,
        uint256 timestamp
    );
    
    event PetEvolved(
        uint256 indexed tokenId,
        uint256 indexed goalId,
        address indexed owner,
        EvolutionStage fromStage,
        EvolutionStage toStage,
        uint256 milestonesCompleted,
        uint256 totalExperience,
        string newMetadataIPFS,
        uint256 timestamp
    );
    
    event ExperienceGained(
        uint256 indexed tokenId,
        uint256 indexed goalId,
        address indexed owner,
        uint256 experienceAmount,
        uint256 newTotalExp,
        uint256 oldLevel,
        uint256 newLevel,
        string reason,
        string newMetadataIPFS,
        uint256 timestamp
    );
    
    event MetadataUpdated(
        uint256 indexed tokenId,
        uint256 indexed goalId,
        address indexed owner,
        string oldMetadataIPFS,
        string newMetadataIPFS,
        string updateReason,
        uint256 timestamp
    );
    
    event AuthorizationChanged(
        address indexed contractAddress,
        bool authorized,
        address indexed changedBy,
        uint256 timestamp
    );
    
    event BaseURIUpdated(
        string oldBaseURI,
        string newBaseURI,
        address indexed updatedBy,
        uint256 timestamp
    );
    
    modifier onlyAuthorized() {
        if (!authorizedContracts[msg.sender] && msg.sender != owner()) {
            revert NotAuthorized();
        }
        _;
    }
    
    constructor() ERC721("Pat Pet", "PPET") Ownable(msg.sender) {}
    
    function mintPet(
        address to,
        string calldata name,
        uint256 goalId,
        PetType petType,
        string calldata metadataIPFS
    ) external onlyAuthorized returns (uint256) {
        if (to == address(0)) revert ZeroAddress();
        
        uint256 tokenId = _nextTokenId++;
        
        // Store actual data, not hashes
        pets[tokenId] = Pet({
            owner: to,
            experience: 0,
            level: 1,
            birthTime: block.timestamp,
            goalId: goalId,
            milestonesCompleted: 0,
            petType: petType,
            stage: EvolutionStage.EGG,
            name: name,
            metadataIPFS: metadataIPFS  // Store actual IPFS hash
        });
        
        ownerPets[to].push(tokenId);
        _safeMint(to, tokenId);
        
        emit PetMinted(
            tokenId,
            to,
            msg.sender,
            goalId,
            petType,
            EvolutionStage.EGG,
            1,
            name,
            metadataIPFS,
            block.timestamp
        );
        
        return tokenId;
    }
    
    function recordMilestoneCompleted(
        uint256 tokenId, 
        string calldata newMetadataIPFS
    ) external onlyAuthorized {
        if (_ownerOf(tokenId) == address(0)) revert PetDoesNotExist();
        
        Pet storage pet = pets[tokenId];
        
        if (pet.milestonesCompleted >= 4) revert MaxMilestonesReached();
        
        // Update milestone count
        pet.milestonesCompleted++;
        
        // Award XP
        uint256 oldLevel = pet.level;
        pet.experience += XP_PER_MILESTONE;
        pet.level = (pet.experience / 50) + 1;
        
        // Check for evolution
        EvolutionStage oldStage = pet.stage;
        EvolutionStage newStage = _calculateEvolutionFromMilestones(pet.milestonesCompleted);
        
        if (newStage != oldStage) {
            pet.stage = newStage;
            
            emit PetEvolved(
                tokenId,
                pet.goalId,
                _ownerOf(tokenId),
                oldStage,
                newStage,
                pet.milestonesCompleted,
                pet.experience,
                newMetadataIPFS,
                block.timestamp
            );
        }
        
        // Update metadata
        string memory oldMetadata = pet.metadataIPFS;
        pet.metadataIPFS = newMetadataIPFS;
        
        emit MilestoneCompleted(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            XP_PER_MILESTONE,
            pet.milestonesCompleted,
            pet.level,
            pet.stage,
            newMetadataIPFS,
            block.timestamp
        );
        
        emit MetadataUpdated(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            oldMetadata,
            newMetadataIPFS,
            "Milestone completed",
            block.timestamp
        );
    }
    
    function _calculateEvolutionFromMilestones(uint256 milestonesCompleted) 
        internal pure returns (EvolutionStage) {
        if (milestonesCompleted >= ADULT_MILESTONE_THRESHOLD) {
            return EvolutionStage.ADULT;
        } else if (milestonesCompleted >= BABY_MILESTONE_THRESHOLD) {
            return EvolutionStage.BABY;
        } else {
            return EvolutionStage.EGG;
        }
    }
    
    function addExperienceWithMetadata(
        uint256 tokenId, 
        uint256 amount, 
        string calldata newMetadataIPFS
    ) external onlyAuthorized {
        if (_ownerOf(tokenId) == address(0)) revert PetDoesNotExist();
        
        Pet storage pet = pets[tokenId];
        uint256 oldLevel = pet.level;
        
        pet.experience += amount;
        pet.level = (pet.experience / 50) + 1;
        
        string memory oldMetadata = pet.metadataIPFS;
        pet.metadataIPFS = newMetadataIPFS;
        
        emit ExperienceGained(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            amount,
            pet.experience,
            oldLevel,
            pet.level,
            "Bonus experience",
            newMetadataIPFS,
            block.timestamp
        );
        
        emit MetadataUpdated(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            oldMetadata,
            newMetadataIPFS,
            "Experience gained",
            block.timestamp
        );
    }
    
    function awardCompletionBonus(
        uint256 tokenId,
        string calldata finalMetadataIPFS
    ) external onlyAuthorized {
        if (_ownerOf(tokenId) == address(0)) revert PetDoesNotExist();
        
        Pet storage pet = pets[tokenId];
        uint256 oldLevel = pet.level;
        
        pet.experience += COMPLETION_BONUS_XP;
        pet.level = (pet.experience / 50) + 1;
        
        string memory oldMetadata = pet.metadataIPFS;
        pet.metadataIPFS = finalMetadataIPFS;
        
        emit ExperienceGained(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            COMPLETION_BONUS_XP,
            pet.experience,
            oldLevel,
            pet.level,
            "Goal completion bonus",
            finalMetadataIPFS,
            block.timestamp
        );
    }
    
    function updateMetadata(uint256 tokenId, string calldata newMetadataIPFS) 
        external onlyOwner {
        if (_ownerOf(tokenId) == address(0)) revert PetDoesNotExist();
        
        Pet storage pet = pets[tokenId];
        string memory oldMetadata = pet.metadataIPFS;
        pet.metadataIPFS = newMetadataIPFS;
        
        emit MetadataUpdated(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            oldMetadata,
            newMetadataIPFS,
            "Emergency update",
            block.timestamp
        );
    }
    
    // Fixed tokenURI to use actual IPFS hash
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert PetDoesNotExist();
        
        Pet memory pet = pets[tokenId];
        return string(abi.encodePacked(baseTokenURI, pet.metadataIPFS));
    }
    
    function setBaseTokenURI(string calldata newBaseURI) external onlyOwner {
        string memory oldBaseURI = baseTokenURI;
        baseTokenURI = newBaseURI;
        
        emit BaseURIUpdated(oldBaseURI, newBaseURI, msg.sender, block.timestamp);
    }
    
    function setAuthorizedContract(address contractAddress, bool authorized) external onlyOwner {
        authorizedContracts[contractAddress] = authorized;
        
        emit AuthorizationChanged(contractAddress, authorized, msg.sender, block.timestamp);
    }
    
    // View functions
    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
    
    function getPetBasicInfo(uint256 tokenId) external view returns (
        address owner,
        uint256 experience,
        uint256 level,
        PetType petType,
        EvolutionStage stage,
        uint256 goalId,
        uint256 milestonesCompleted
    ) {
        Pet memory pet = pets[tokenId];
        return (
            pet.owner,
            pet.experience,
            pet.level,
            pet.petType,
            pet.stage,
            pet.goalId,
            pet.milestonesCompleted
        );
    }
    
    function getPetFullInfo(uint256 tokenId) external view returns (Pet memory) {
        return pets[tokenId];
    }
    
    function getEvolutionThresholds() external pure returns (
        uint256 babyMilestoneThreshold,
        uint256 adultMilestoneThreshold,
        uint256 xpPerMilestone,
        uint256 completionBonusXP
    ) {
        return (
            BABY_MILESTONE_THRESHOLD,
            ADULT_MILESTONE_THRESHOLD,
            XP_PER_MILESTONE,
            COMPLETION_BONUS_XP
        );
    }
    
    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }
    
    function getOwnerPets(address owner) external view returns (uint256[] memory) {
        return ownerPets[owner];
    }
}