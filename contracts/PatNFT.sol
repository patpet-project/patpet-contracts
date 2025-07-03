// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PetNFT - Ponder Optimized
 * @dev Dynamic NFT with comprehensive event logging for Ponder indexing
 */
contract PatNFT is ERC721, Ownable {
    
    uint256 private _nextTokenId;
    
    enum PetType { DRAGON, CAT, PLANT }
    enum EvolutionStage { EGG, BABY, ADULT }
    
    struct Pet {
        string name;
        PetType petType;
        EvolutionStage stage;
        uint256 experience;
        uint256 level;
        uint256 goalId;
        uint256 birthTime;
        bool isHappy;
        uint256 totalMilestonesCompleted;
        string metadataIPFS;
    }
    
    // Storage
    mapping(uint256 => Pet) public pets;
    mapping(address => uint256[]) public ownerPets;
    mapping(address => bool) public authorizedContracts;
    
    // Constants
    uint256 public constant EGG_TO_BABY_XP = 100;
    uint256 public constant BABY_TO_ADULT_XP = 500;
    
    string public baseTokenURI = "https://gateway.pinata.cloud/ipfs/";
    
    // 🎯 PONDER EVENTS - Comprehensive pet tracking
    event PetSystemInitialized(
        address indexed owner,
        string name,
        string symbol,
        uint256 eggToBabyXP,
        uint256 babyToAdultXP,
        string baseTokenURI,
        uint256 timestamp
    );
    
    event PetMinted(
        uint256 indexed tokenId,
        address indexed owner,
        address indexed minter,
        string name,
        PetType petType,
        uint256 goalId,
        string metadataIPFS,
        uint256 timestamp
    );
    
    event ExperienceGained(
        uint256 indexed tokenId,
        uint256 indexed goalId,
        address indexed owner,
        uint256 experienceAmount,
        uint256 newTotalExperience,
        uint256 oldLevel,
        uint256 newLevel,
        string reason,
        string newMetadataIPFS,
        uint256 timestamp
    );
    
    event PetEvolved(
        uint256 indexed tokenId,
        uint256 indexed goalId,
        address indexed owner,
        EvolutionStage fromStage,
        EvolutionStage toStage,
        uint256 currentExperience,
        uint256 evolutionTime,
        string newMetadataIPFS,
        uint256 timestamp
    );
    
    event PetMoodChanged(
        uint256 indexed tokenId,
        uint256 indexed goalId,
        address indexed owner,
        bool oldMood,
        bool newMood,
        string reason,
        string newMetadataIPFS,
        uint256 timestamp
    );
    
    event MilestoneCompleted(
        uint256 indexed tokenId,
        uint256 indexed goalId,
        address indexed owner,
        uint256 newMilestoneCount,
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
    
    event PetTransferred(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to,
        uint256 goalId,
        PetType petType,
        EvolutionStage stage,
        uint256 experience,
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
    
    event PetStatisticsSnapshot(
        uint256 totalSupply,
        uint256 totalEggStage,
        uint256 totalBabyStage,
        uint256 totalAdultStage,
        uint256 totalHappyPets,
        uint256 totalSadPets,
        uint256 averageExperience,
        uint256 timestamp
    );
    
    modifier onlyAuthorized() {
        require(authorizedContracts[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }
    
    constructor() ERC721("Pat Pet", "PPET") Ownable(msg.sender) {
        // 🎯 PONDER EVENT: System initialization
        emit PetSystemInitialized(
            msg.sender,
            "Pat Pet",
            "PPET",
            EGG_TO_BABY_XP,
            BABY_TO_ADULT_XP,
            baseTokenURI,
            block.timestamp
        );
        
        _emitStatisticsSnapshot();
    }
    
    function mintPet(
        address to,
        string memory name,
        uint256 goalId,
        PetType petType,
        string memory metadataIPFS
    ) external onlyAuthorized returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        
        pets[tokenId] = Pet({
            name: name,
            petType: petType,
            stage: EvolutionStage.EGG,
            experience: 0,
            level: 1,
            goalId: goalId,
            birthTime: block.timestamp,
            isHappy: true,
            totalMilestonesCompleted: 0,
            metadataIPFS: metadataIPFS
        });
        
        ownerPets[to].push(tokenId);
        _safeMint(to, tokenId);
        
        // 🎯 PONDER EVENT: Pet minting
        emit PetMinted(
            tokenId,
            to,
            msg.sender,
            name,
            petType,
            goalId,
            metadataIPFS,
            block.timestamp
        );
        
        _emitStatisticsSnapshot();
        return tokenId;
    }
    
    function addExperienceWithMetadata(
        uint256 tokenId, 
        uint256 amount, 
        string memory newMetadataIPFS
    ) external onlyAuthorized {
        require(_ownerOf(tokenId) != address(0), "Pet does not exist");
        
        Pet storage pet = pets[tokenId];
        uint256 oldExperience = pet.experience;
        uint256 oldLevel = pet.level;
        EvolutionStage oldStage = pet.stage;
        
        pet.experience += amount;
        pet.level = (pet.experience / 50) + 1;
        pet.metadataIPFS = newMetadataIPFS;
        
        // 🎯 PONDER EVENT: Experience gained
        emit ExperienceGained(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            amount,
            pet.experience,
            oldLevel,
            pet.level,
            "Experience reward",
            newMetadataIPFS,
            block.timestamp
        );
        
        // 🎯 PONDER EVENT: Metadata update
        emit MetadataUpdated(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            pet.metadataIPFS, // This will be the old one before we update it
            newMetadataIPFS,
            "Experience gained",
            block.timestamp
        );
        
        // Check for evolution
        EvolutionStage newStage = _calculateEvolutionStage(pet.experience, pet.stage);
        if (newStage != pet.stage) {
            pet.stage = newStage;
            
            // 🎯 PONDER EVENT: Pet evolution
            emit PetEvolved(
                tokenId,
                pet.goalId,
                _ownerOf(tokenId),
                oldStage,
                newStage,
                pet.experience,
                block.timestamp - pet.birthTime,
                newMetadataIPFS,
                block.timestamp
            );
        }
        
        _emitStatisticsSnapshot();
    }
    
    function setPetMoodWithMetadata(
        uint256 tokenId, 
        bool isHappy, 
        string memory newMetadataIPFS
    ) external onlyAuthorized {
        require(_ownerOf(tokenId) != address(0), "Pet does not exist");
        
        Pet storage pet = pets[tokenId];
        bool oldMood = pet.isHappy;
        string memory oldMetadataIPFS = pet.metadataIPFS;
        
        pet.isHappy = isHappy;
        pet.metadataIPFS = newMetadataIPFS;
        
        // 🎯 PONDER EVENT: Mood change
        emit PetMoodChanged(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            oldMood,
            isHappy,
            isHappy ? "Achievement success" : "Milestone rejected",
            newMetadataIPFS,
            block.timestamp
        );
        
        // 🎯 PONDER EVENT: Metadata update
        emit MetadataUpdated(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            oldMetadataIPFS,
            newMetadataIPFS,
            "Mood change",
            block.timestamp
        );
        
        _emitStatisticsSnapshot();
    }
    
    function recordMilestoneCompleted(uint256 tokenId) external onlyAuthorized {
        require(_ownerOf(tokenId) != address(0), "Pet does not exist");
        
        Pet storage pet = pets[tokenId];
        pet.totalMilestonesCompleted++;
        
        // 🎯 PONDER EVENT: Milestone completion
        emit MilestoneCompleted(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            pet.totalMilestonesCompleted,
            block.timestamp
        );
    }
    
    function updateMetadata(uint256 tokenId, string memory newMetadataIPFS) 
        external onlyOwner {
        require(_ownerOf(tokenId) != address(0), "Pet does not exist");
        
        Pet storage pet = pets[tokenId];
        string memory oldMetadataIPFS = pet.metadataIPFS;
        pet.metadataIPFS = newMetadataIPFS;
        
        // 🎯 PONDER EVENT: Emergency metadata update
        emit MetadataUpdated(
            tokenId,
            pet.goalId,
            _ownerOf(tokenId),
            oldMetadataIPFS,
            newMetadataIPFS,
            "Emergency update",
            block.timestamp
        );
    }
    
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Pet does not exist");
        
        Pet memory pet = pets[tokenId];
        return string(abi.encodePacked(baseTokenURI, pet.metadataIPFS));
    }
    
    function _calculateEvolutionStage(uint256 experience, EvolutionStage currentStage) 
        internal pure returns (EvolutionStage) {
        if (experience >= BABY_TO_ADULT_XP && currentStage == EvolutionStage.BABY) {
            return EvolutionStage.ADULT;
        } else if (experience >= EGG_TO_BABY_XP && currentStage == EvolutionStage.EGG) {
            return EvolutionStage.BABY;
        }
        return currentStage;
    }
    
    function setBaseTokenURI(string memory newBaseURI) external onlyOwner {
        string memory oldBaseURI = baseTokenURI;
        baseTokenURI = newBaseURI;
        
        // 🎯 PONDER EVENT: Base URI update
        emit BaseURIUpdated(oldBaseURI, newBaseURI, msg.sender, block.timestamp);
    }
    
    function setAuthorizedContract(address contractAddress, bool authorized) external onlyOwner {
        authorizedContracts[contractAddress] = authorized;
        
        // 🎯 PONDER EVENT: Authorization change
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
            
            // 🎯 PONDER EVENT: Pet transfer
            emit PetTransferred(
                tokenId,
                from,
                to,
                pet.goalId,
                pet.petType,
                pet.stage,
                pet.experience,
                block.timestamp
            );
            
            // Update owner pets mapping
            _updateOwnerPetsMapping(from, to, tokenId);
        }
        
        return previousOwner;
    }
    
    function _updateOwnerPetsMapping(address from, address to, uint256 tokenId) internal {
        // Remove from old owner
        uint256[] storage fromPets = ownerPets[from];
        for (uint256 i = 0; i < fromPets.length; i++) {
            if (fromPets[i] == tokenId) {
                fromPets[i] = fromPets[fromPets.length - 1];
                fromPets.pop();
                break;
            }
        }
        
        // Add to new owner
        ownerPets[to].push(tokenId);
    }
    
    /**
     * @dev Emit current system statistics snapshot
     */
    function _emitStatisticsSnapshot() internal {
        uint256 totalSupply = _nextTokenId;
        uint256 totalEggStage = 0;
        uint256 totalBabyStage = 0;
        uint256 totalAdultStage = 0;
        uint256 totalHappyPets = 0;
        uint256 totalSadPets = 0;
        uint256 totalExperience = 0;
        
        // Calculate statistics
        for (uint256 i = 0; i < totalSupply; i++) {
            if (_ownerOf(i) != address(0)) {
                Pet memory pet = pets[i];
                
                // Count stages
                if (pet.stage == EvolutionStage.EGG) totalEggStage++;
                else if (pet.stage == EvolutionStage.BABY) totalBabyStage++;
                else if (pet.stage == EvolutionStage.ADULT) totalAdultStage++;
                
                // Count moods
                if (pet.isHappy) totalHappyPets++;
                else totalSadPets++;
                
                // Sum experience
                totalExperience += pet.experience;
            }
        }
        
        uint256 averageExperience = totalSupply > 0 ? totalExperience / totalSupply : 0;
        
        // 🎯 PONDER EVENT: System statistics
        emit PetStatisticsSnapshot(
            totalSupply,
            totalEggStage,
            totalBabyStage,
            totalAdultStage,
            totalHappyPets,
            totalSadPets,
            averageExperience,
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
    
    // 🚫 REMOVED: All complex view functions (getPetDetails, getPetsByOwner, etc.)
    // Use Ponder indexer to query this data instead!
    
    // Keep only essential view functions for basic contract interaction
    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}