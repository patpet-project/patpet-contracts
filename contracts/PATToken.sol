// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title PATToken - Ponder Optimized
 * @dev ERC20 token with comprehensive event logging for Ponder indexing
 * Removed view functions - use Ponder indexer instead!
 */
contract PATToken is ERC20, ERC20Burnable, Ownable, Pausable {
    
    uint256 public constant MAX_SUPPLY = 100_000_000 * 10**18;
    
    // Track totals (updated via events in Ponder)
    uint256 public totalRewardsDistributed;
    uint256 public totalStakesLost;
    
    // Authorization mappings
    mapping(address => bool) public authorizedMinters;
    mapping(address => bool) public authorizedBurners;
    
    // 🎯 PONDER EVENTS - Comprehensive event logging
    event TokensInitialized(
        address indexed owner,
        uint256 initialSupply,
        uint256 maxSupply,
        uint256 timestamp
    );
    
    event AuthorizationChanged(
        address indexed account,
        string role, // "minter" or "burner"
        bool authorized,
        address indexed changedBy,
        uint256 timestamp
    );
    
    event TokensMinted(
        address indexed to,
        uint256 amount,
        address indexed minter,
        uint256 newTotalSupply,
        uint256 remainingMintable,
        uint256 timestamp
    );
    
    event TokensBurned(
        address indexed from,
        uint256 amount,
        address indexed burner,
        uint256 newTotalSupply,
        uint256 timestamp
    );
    
    event RewardDistributed(
        address indexed recipient,
        uint256 amount,
        string reason,
        address indexed distributor,
        uint256 newTotalRewards,
        uint256 timestamp
    );
    
    event StakeLostRecorded(
        address indexed user,
        uint256 amount,
        string reason,
        address indexed recorder,
        uint256 newTotalStakesLost,
        uint256 timestamp
    );
    
    event ContractPaused(
        address indexed pauser,
        uint256 timestamp
    );
    
    event ContractUnpaused(
        address indexed unpauser,
        uint256 timestamp
    );
    
    event EcosystemSnapshot(
        uint256 totalSupply,
        uint256 maxSupply,
        uint256 totalRewardsDistributed,
        uint256 totalStakesLost,
        uint256 remainingMintable,
        uint256 timestamp
    );
    
    modifier onlyAuthorizedMinter() {
        require(authorizedMinters[msg.sender], "Not authorized to mint");
        _;
    }
    
    modifier onlyAuthorizedBurner() {
        require(authorizedBurners[msg.sender], "Not authorized to burn");
        _;
    }
    
    constructor() ERC20("PAT Pet Token", "PAT") Ownable(msg.sender) {
        uint256 initialSupply = 50_000_000 * 10**18;
        _mint(msg.sender, initialSupply);
        
        // 🎯 PONDER EVENT: Contract initialization
        emit TokensInitialized(msg.sender, initialSupply, MAX_SUPPLY, block.timestamp);
        
        // Initial ecosystem snapshot
        emit EcosystemSnapshot(
            initialSupply,
            MAX_SUPPLY,
            0, // totalRewardsDistributed
            0, // totalStakesLost  
            MAX_SUPPLY - initialSupply,
            block.timestamp
        );
    }
    
    function mint(address to, uint256 amount) external onlyAuthorizedMinter whenNotPaused {
        require(totalSupply() + amount <= MAX_SUPPLY, "Would exceed max supply");
        
        _mint(to, amount);
        
        // 🎯 PONDER EVENT: Detailed mint tracking
        emit TokensMinted(
            to,
            amount,
            msg.sender,
            totalSupply(),
            MAX_SUPPLY - totalSupply(),
            block.timestamp
        );
    }
    
    function burnFrom(address account, uint256 amount) public override onlyAuthorizedBurner whenNotPaused {
        super.burnFrom(account, amount);
        
        // 🎯 PONDER EVENT: Detailed burn tracking
        emit TokensBurned(
            account,
            amount,
            msg.sender,
            totalSupply(),
            block.timestamp
        );
    }
    
    function distributeReward(address recipient, uint256 amount, string memory reason) 
        external onlyAuthorizedMinter whenNotPaused {
        require(totalSupply() + amount <= MAX_SUPPLY, "Would exceed max supply");
        
        _mint(recipient, amount);
        totalRewardsDistributed += amount;
        
        // 🎯 PONDER EVENT: Detailed reward tracking
        emit RewardDistributed(
            recipient,
            amount,
            reason,
            msg.sender,
            totalRewardsDistributed,
            block.timestamp
        );
    }
    
    function recordStakeLoss(address user, uint256 amount, string memory reason) 
        external onlyAuthorizedBurner {
        totalStakesLost += amount;
        
        // 🎯 PONDER EVENT: Detailed stake loss tracking
        emit StakeLostRecorded(
            user,
            amount,
            reason,
            msg.sender,
            totalStakesLost,
            block.timestamp
        );
    }
    
    function addAuthorizedMinter(address minter) external onlyOwner {
        authorizedMinters[minter] = true;
        
        // 🎯 PONDER EVENT: Authorization changes
        emit AuthorizationChanged(minter, "minter", true, msg.sender, block.timestamp);
    }
    
    function removeAuthorizedMinter(address minter) external onlyOwner {
        authorizedMinters[minter] = false;
        
        // 🎯 PONDER EVENT: Authorization changes
        emit AuthorizationChanged(minter, "minter", false, msg.sender, block.timestamp);
    }
    
    function addAuthorizedBurner(address burner) external onlyOwner {
        authorizedBurners[burner] = true;
        
        // 🎯 PONDER EVENT: Authorization changes
        emit AuthorizationChanged(burner, "burner", true, msg.sender, block.timestamp);
    }
    
    function removeAuthorizedBurner(address burner) external onlyOwner {
        authorizedBurners[burner] = false;
        
        // 🎯 PONDER EVENT: Authorization changes
        emit AuthorizationChanged(burner, "burner", false, msg.sender, block.timestamp);
    }
    
    function pause() external onlyOwner {
        _pause();
        
        // 🎯 PONDER EVENT: Contract state changes
        emit ContractPaused(msg.sender, block.timestamp);
    }
    
    function unpause() external onlyOwner {
        _unpause();
        
        // 🎯 PONDER EVENT: Contract state changes
        emit ContractUnpaused(msg.sender, block.timestamp);
    }
    
    /**
     * @dev Emit ecosystem snapshot (can be called by anyone for data sync)
     */
    function emitEcosystemSnapshot() external {
        emit EcosystemSnapshot(
            totalSupply(),
            MAX_SUPPLY,
            totalRewardsDistributed,
            totalStakesLost,
            MAX_SUPPLY - totalSupply(),
            block.timestamp
        );
    }
    
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        super._update(from, to, value);
    }
    
    // 🚫 REMOVED: All view functions (getEcosystemStats, etc.)
    // Use Ponder indexer to query this data instead!
}