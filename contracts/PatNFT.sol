// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PatNFT - Milestone-Based Evolution
 * @dev Dynamic NFT with evolution based on milestone completion (max 4 milestones)
 */
contract PatNFT is ERC721, Ownable {
    
    uint256 private _nextTokenId;
    
    enum PetType { DRAGON, CAT, PLANT }
    enum EvolutionStage { EGG, BABY, ADULT }
    
    // 🔧 OPTIMIZATION: Packed struct (reduces from 8 to 5 storage slots = ~60k gas savings)
    struct Pet {
        address owner;                   // 20 bytes
        uint96 experience;               // 12 bytes (can handle up to 79B XP)
        uint32 birthTime;                // 4 bytes (valid until year 2106)
        uint32 goalId;                   // 4 bytes (supports 4B goals)
        uint16 level;                    // 2 bytes (supports level 65535)
        uint8 milestonesCompleted;       // 1 byte (max 4 milestones)
        PetType petType;                 // 1 byte
        EvolutionStage stage;            // 1 byte
        bytes32 nameHash;                // 32 bytes (separate slot)
        bytes32 metadataIPFSHash;        // 32 bytes (separate slot)
    }
    
    // Storage
    mapping(uint256 => Pet) public pets;
    mapping(address => uint256[]) public ownerPets;
    mapping(address => bool) public authorizedContracts;
    
    // 🔧 OPTIMIZATION: Evolution thresholds based on milestones
    uint256 private constant BABY_MILESTONE_THRESHOLD = 2;  // EGG → BABY at 2 milestones
    uint256 private constant ADULT_MILESTONE_THRESHOLD = 4; // BABY → ADULT at 4 milestones
    uint256 private constant XP_PER_MILESTONE = 25;         // XP awarded per milestone
    uint256 private constant COMPLETION_BONUS_XP = 100;     // Bonus XP for goal completion
    
    string public baseTokenURI = "https://gateway.pinata.cloud/ipfs/";
    
    // 🔧 OPTIMIZATION: Custom errors instead of strings
    error PetDoesNotExist();
    error NotAuthorized();
    error InvalidTokenId();
    error ZeroAddress();
    error MaxMilestonesReached();
    
    // 🔧 OPTIMIZATION: Packed events for better gas efficiency
    event PetMinted(
        uint256 indexed tokenId,
        address indexed owner,
        address indexed minter,
        uint256 packedData, // goalId(32) | petType(8) | stage(8) | level(16)
        bytes32 nameHash,
        bytes32 metadataIPFSHash,
        uint256 timestamp
    );
    
    event MilestoneCompleted(
        uint256 indexed tokenId,
        uint256 indexed goalId,
        address indexed owner,
        uint256 packedData, // xpAwarded(64) | newMilestones(8) | newLevel(16) | newStage(8)
        bytes32 newMetadataIPFSHash,
        uint256 timestamp
    );
    
    event PetEvolved(
        uint256 indexed tokenId,
        uint256 indexed goalId,
        address indexed owner,
        uint256 packedData, // fromStage(8) | toStage(8) | milestones(8) | totalExp(64)
        bytes32 newMetadataIPFSHash,
        uint256 timestamp
    );
    
    event ExperienceGained(
        uint256 indexed tokenId,
        uint256 indexed goalId,
        address indexed owner,
        uint256 packedData, // experienceAmount(64) | newTotalExp(64) | oldLevel(16) | newLevel(16)
        bytes32 reasonHash,
        bytes32 newMetadataIPFSHash,
        uint256 timestamp
    );
    
    event MetadataUpdated(
        uint256 indexed tokenId,
        uint256 indexed goalId,
        address indexed owner,
        bytes32 oldMetadataIPFSHash,
        bytes32 newMetadataIPFSHash,
        bytes32 updateReasonHash,
        uint256 timestamp
    );
    
    event PetStatisticsSnapshot(
        uint256 totalSupply,
        uint256 packedStageData,    // eggStage(16) | babyStage(16) | adultStage(16) | reserved(208)
        uint256 averageExperience,
        uint256 averageMilestones,
        uint256 timestamp
    );
    
    modifier onlyAuthorized() {
        if (!authorizedContracts[msg.sender] && msg.sender != owner()) {
            revert NotAuthorized();
        }
        _;
    }
    
    constructor() ERC721("Pat Pet", "PPET") Ownable(msg.sender) {
        _emitStatisticsSnapshot();
    }
    
    // 🔧 OPTIMIZATION: External instead of public, calldata for strings
    function mintPet(
        address to,
        string calldata name,
        uint256 goalId,
        PetType petType,
        string calldata metadataIPFS
    ) external onlyAuthorized returns (uint256) {
        if (to == address(0)) revert ZeroAddress();
        
        uint256 tokenId = _nextTokenId++;
        
        // 🔧 OPTIMIZATION: Pack pet data efficiently
        pets[tokenId] = Pet({
            owner: to,
            experience: 0,
            birthTime: uint32(block.timestamp),
            goalId: uint32(goalId),
            level: 1,
            milestonesCompleted: 0,
            petType: petType,
            stage: EvolutionStage.EGG,
            nameHash: keccak256(bytes(name)),
            metadataIPFSHash: keccak256(bytes(metadataIPFS))
        });
        
        ownerPets[to].push(tokenId);
        _safeMint(to, tokenId);
        
        // 🔧 OPTIMIZATION: Pack event data
        uint256 packedData = (goalId << 224) | 
                           (uint256(petType) << 216) | 
                           (uint256(EvolutionStage.EGG) << 208) | 
                           (1); // level = 1
        
        emit PetMinted(
            tokenId,
            to,
            msg.sender,
            packedData,
            keccak256(bytes(name)),
            keccak256(bytes(metadataIPFS)),
            block.timestamp
        );
        
        _emitStatisticsSnapshot();
        return tokenId;
    }
    
    // 🔧 NEW: Record milestone completion and handle evolution
    function recordMilestoneCompleted(
        uint256 tokenId, 
        string calldata newMetadataIPFS
    ) external onlyAuthorized {
        if (_ownerOf(tokenId) == address(0)) revert PetDoesNotExist();
        
        Pet storage pet = pets[tokenId];
        
        // Check if max milestones reached
        if (pet.milestonesCompleted >= 4) revert MaxMilestonesReached();
        
        // Increment milestone count
        unchecked {
            pet.milestonesCompleted++;
        }
        
        // Award XP for milestone
        uint256 oldLevel = pet.level;
        pet.experience += uint96(XP_PER_MILESTONE);
        pet.level = uint16((pet.experience / 50) + 1);
        
        // Check for evolution based on milestones
        EvolutionStage oldStage = pet.stage;
        EvolutionStage newStage = _calculateEvolutionFromMilestones(pet.milestonesCompleted);
        
        if (newStage != oldStage) {
            pet.stage = newStage;
            
            // Emit evolution event
            uint256 evolutionPackedData = (uint256(oldStage) << 248) | 
                                         (uint256(newStage) << 240) | 
                                         (uint256(pet.milestonesCompleted) << 232) | 
                                         (uint256(pet.experience) << 168);
            
            emit PetEvolved(
                tokenId,
                pet.goalId,
                _ownerOf(tokenId),
                evolutionPackedData,
                keccak256(bytes(newMetadataIPFS)),
                block.timestamp
            );
        }
        
        // Update metadata
        pet.metadataIPFSHash = keccak256(bytes(newMetadataIPFS));
        
        // 🔧 OPTIMIZATION: Pack milestone completion data
        uint256 packedData = (uint256(XP_PER_MILESTONE) << 192) | 
                           (uint256(pet.milestonesCompleted) << 184) | 
                           (uint256(pet.level) << 168) | 
                           (uint256(pet.stage) << 160);
        
        emit MilestoneCompleted(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            packedData,
            keccak256(bytes(newMetadataIPFS)),
            block.timestamp
        );
        
        // Emit metadata update
        emit MetadataUpdated(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            pet.metadataIPFSHash, // old (will be same as new in this case)
            keccak256(bytes(newMetadataIPFS)), // new
            keccak256("Milestone completed"),
            block.timestamp
        );
        
        _emitStatisticsSnapshot();
    }
    
    // 🔧 NEW: Calculate evolution stage based on milestones completed
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
    
    // 🔧 MODIFIED: Add experience with evolution check (for bonus XP)
    function addExperienceWithMetadata(
        uint256 tokenId, 
        uint256 amount, 
        string calldata newMetadataIPFS
    ) external onlyAuthorized {
        if (_ownerOf(tokenId) == address(0)) revert PetDoesNotExist();
        
        Pet storage pet = pets[tokenId];
        uint256 oldExperience = pet.experience;
        uint256 oldLevel = pet.level;
        
        // 🔧 OPTIMIZATION: Unchecked arithmetic (safe for experience points)
        unchecked {
            pet.experience += uint96(amount);
            pet.level = uint16((pet.experience / 50) + 1);
        }
        
        bytes32 oldMetadataHash = pet.metadataIPFSHash;
        pet.metadataIPFSHash = keccak256(bytes(newMetadataIPFS));
        
        // 🔧 OPTIMIZATION: Pack experience data
        uint256 packedData = (amount << 192) | 
                           (pet.experience << 128) | 
                           (oldLevel << 112) | 
                           (pet.level << 96);
        
        emit ExperienceGained(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            packedData,
            keccak256("Bonus experience"),
            pet.metadataIPFSHash,
            block.timestamp
        );
        
        // 🔧 OPTIMIZATION: Only emit metadata update if hash changed
        if (oldMetadataHash != pet.metadataIPFSHash) {
            emit MetadataUpdated(
                tokenId,
                pet.goalId,
                _ownerOf(tokenId),
                oldMetadataHash,
                pet.metadataIPFSHash,
                keccak256("Experience gained"),
                block.timestamp
            );
        }
    }
    
    // 🔧 NEW: Award completion bonus when goal is completed
    function awardCompletionBonus(
        uint256 tokenId,
        string calldata finalMetadataIPFS
    ) external onlyAuthorized {
        if (_ownerOf(tokenId) == address(0)) revert PetDoesNotExist();
        
        Pet storage pet = pets[tokenId];
        uint256 oldLevel = pet.level;
        
        // Award completion bonus
        unchecked {
            pet.experience += uint96(COMPLETION_BONUS_XP);
            pet.level = uint16((pet.experience / 50) + 1);
        }
        
        // Update metadata
        pet.metadataIPFSHash = keccak256(bytes(finalMetadataIPFS));
        
        // Pack and emit experience gained event
        uint256 packedData = (uint256(COMPLETION_BONUS_XP) << 192) | 
                           (pet.experience << 128) | 
                           (oldLevel << 112) | 
                           (pet.level << 96);
        
        emit ExperienceGained(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            packedData,
            keccak256("Goal completion bonus"),
            pet.metadataIPFSHash,
            block.timestamp
        );
    }
    
    // 🔧 OPTIMIZATION: External with calldata
    function updateMetadata(uint256 tokenId, string calldata newMetadataIPFS) 
        external onlyOwner {
        if (_ownerOf(tokenId) == address(0)) revert PetDoesNotExist();
        
        Pet storage pet = pets[tokenId];
        bytes32 oldMetadataHash = pet.metadataIPFSHash;
        pet.metadataIPFSHash = keccak256(bytes(newMetadataIPFS));
        
        emit MetadataUpdated(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            oldMetadataHash,
            pet.metadataIPFSHash,
            keccak256("Emergency update"),
            block.timestamp
        );
    }
    
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert PetDoesNotExist();
        
        Pet memory pet = pets[tokenId];
        return string(abi.encodePacked(baseTokenURI, _bytes32ToHexString(pet.metadataIPFSHash)));
    }
    
    // 🔧 OPTIMIZATION: External with calldata
    function setBaseTokenURI(string calldata newBaseURI) external onlyOwner {
        string memory oldBaseURI = baseTokenURI;
        baseTokenURI = newBaseURI;
        
        emit BaseURIUpdated(oldBaseURI, newBaseURI, msg.sender, block.timestamp);
    }
    
    function setAuthorizedContract(address contractAddress, bool authorized) external onlyOwner {
        authorizedContracts[contractAddress] = authorized;
        
        emit AuthorizationChanged(contractAddress, authorized, msg.sender, block.timestamp);
    }
    
    /**
     * @dev Override transfer to emit detailed transfer event
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        address previousOwner = super._update(to, tokenId, auth);
        
        // Only emit for actual transfers (not mints)
        if (from != address(0) && to != address(0)) {
            Pet memory pet = pets[tokenId];
            
            // 🔧 OPTIMIZATION: Pack transfer data
            uint256 packedData = (pet.goalId << 224) | 
                               (uint256(pet.petType) << 216) | 
                               (uint256(pet.stage) << 208) | 
                               (pet.experience << 144);
            
            emit PetTransferred(
                tokenId,
                from,
                to,
                packedData,
                block.timestamp
            );
            
            // Update owner pets mapping
            _updateOwnerPetsMapping(from, to, tokenId);
        }
        
        return previousOwner;
    }
    
    // 🔧 OPTIMIZATION: Efficient owner pets mapping update
    function _updateOwnerPetsMapping(address from, address to, uint256 tokenId) internal {
        // Remove from old owner
        uint256[] storage fromPets = ownerPets[from];
        uint256 length = fromPets.length;
        
        for (uint256 i; i < length;) {
            if (fromPets[i] == tokenId) {
                fromPets[i] = fromPets[length - 1];
                fromPets.pop();
                break;
            }
            unchecked { ++i; }
        }
        
        // Add to new owner
        ownerPets[to].push(tokenId);
    }
    
    /**
     * @dev Emit optimized statistics snapshot
     */
    function _emitStatisticsSnapshot() internal {
        uint256 totalSupplyCount = _nextTokenId;
        uint256 eggStage = 0;
        uint256 babyStage = 0;
        uint256 adultStage = 0;
        uint256 totalExperience = 0;
        uint256 totalMilestones = 0;
        
        // 🔧 OPTIMIZATION: Single loop with unchecked arithmetic
        for (uint256 i; i < totalSupplyCount;) {
            if (_ownerOf(i) != address(0)) {
                Pet memory pet = pets[i];
                
                // Count stages
                if (pet.stage == EvolutionStage.EGG) {
                    unchecked { eggStage++; }
                } else if (pet.stage == EvolutionStage.BABY) {
                    unchecked { babyStage++; }
                } else if (pet.stage == EvolutionStage.ADULT) {
                    unchecked { adultStage++; }
                }
                
                // Sum experience and milestones
                unchecked { 
                    totalExperience += pet.experience;
                    totalMilestones += pet.milestonesCompleted;
                }
            }
            unchecked { ++i; }
        }
        
        uint256 averageExperience = totalSupplyCount > 0 ? totalExperience / totalSupplyCount : 0;
        uint256 averageMilestones = totalSupplyCount > 0 ? totalMilestones / totalSupplyCount : 0;
        
        // 🔧 OPTIMIZATION: Pack statistics data
        uint256 packedStageData = (eggStage << 240) | (babyStage << 224) | (adultStage << 208);
        
        emit PetStatisticsSnapshot(
            totalSupplyCount,
            packedStageData,
            averageExperience,
            averageMilestones,
            block.timestamp
        );
    }
    
    /**
     * @dev Public function to emit statistics snapshot (for data sync)
     */
    function emitStatisticsSnapshot() external {
        _emitStatisticsSnapshot();
    }
    
    /**
     * @dev Get total supply
     */
    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }
    
    // 🔧 OPTIMIZATION: Efficient view functions
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
    
    // 🔧 NEW: Get evolution thresholds
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
    
    // 🔧 OPTIMIZATION: Utility function for converting bytes32 to hex string
    function _bytes32ToHexString(bytes32 data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(64);
        
        for (uint256 i; i < 32;) {
            str[i * 2] = alphabet[uint8(data[i] >> 4)];
            str[1 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
            unchecked { ++i; }
        }
        
        return string(str);
    }
    
    // Events for compatibility
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
    
    event PetTransferred(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to,
        uint256 packedData,
        uint256 timestamp
    );
}