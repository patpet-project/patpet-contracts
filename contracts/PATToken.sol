// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title PATToken - Clean & Integration-Friendly Version
 * @dev ERC20 token with clean events for easy integration and data processing
 */
contract PATToken is ERC20, ERC20Burnable, Ownable, Pausable {
    
    uint256 public constant MAX_SUPPLY = 100_000_000 * 10**18;
    
    // Track totals
    uint256 public totalRewardsDistributed;
    uint256 public totalStakesLost;
    
    // Authorization mappings
    mapping(address => bool) public authorizedMinters;
    mapping(address => bool) public authorizedBurners;
    
    // Clean, readable events
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
        string reason,
        uint256 timestamp
    );
    
    event TokensBurned(
        address indexed from,
        uint256 amount,
        address indexed burner,
        uint256 newTotalSupply,
        string reason,
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
        string reason,
        uint256 timestamp
    );
    
    event ContractUnpaused(
        address indexed unpauser,
        string reason,
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
        
        emit TokensInitialized(
            msg.sender, 
            initialSupply, 
            MAX_SUPPLY, 
            block.timestamp
        );
    }
    
    function mint(address to, uint256 amount) external onlyAuthorizedMinter whenNotPaused {
        require(totalSupply() + amount <= MAX_SUPPLY, "Would exceed max supply");
        
        _mint(to, amount);
        
        emit TokensMinted(
            to,
            amount,
            msg.sender,
            totalSupply(),
            MAX_SUPPLY - totalSupply(),
            "Standard mint",
            block.timestamp
        );
    }
    
    function mintWithReason(address to, uint256 amount, string memory reason) 
        external onlyAuthorizedMinter whenNotPaused {
        require(totalSupply() + amount <= MAX_SUPPLY, "Would exceed max supply");
        
        _mint(to, amount);
        
        emit TokensMinted(
            to,
            amount,
            msg.sender,
            totalSupply(),
            MAX_SUPPLY - totalSupply(),
            reason,
            block.timestamp
        );
    }
    
    function burnFrom(address account, uint256 amount) public override onlyAuthorizedBurner whenNotPaused {
        super.burnFrom(account, amount);
        
        emit TokensBurned(
            account,
            amount,
            msg.sender,
            totalSupply(),
            "Standard burn",
            block.timestamp
        );
    }
    
    function burnFromWithReason(address account, uint256 amount, string memory reason) 
        external onlyAuthorizedBurner whenNotPaused {
        super.burnFrom(account, amount);
        
        emit TokensBurned(
            account,
            amount,
            msg.sender,
            totalSupply(),
            reason,
            block.timestamp
        );
    }
    
    function distributeReward(address recipient, uint256 amount, string memory reason) 
        external onlyAuthorizedMinter whenNotPaused {
        require(totalSupply() + amount <= MAX_SUPPLY, "Would exceed max supply");
        
        _mint(recipient, amount);
        totalRewardsDistributed += amount;
        
        emit RewardDistributed(
            recipient,
            amount,
            reason,
            msg.sender,
            totalRewardsDistributed,
            block.timestamp
        );
        
        emit TokensMinted(
            recipient,
            amount,
            msg.sender,
            totalSupply(),
            MAX_SUPPLY - totalSupply(),
            string(abi.encodePacked("Reward: ", reason)),
            block.timestamp
        );
    }
    
    function recordStakeLoss(address user, uint256 amount, string memory reason) 
        external onlyAuthorizedBurner {
        totalStakesLost += amount;
        
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
        
        emit AuthorizationChanged(
            minter, 
            "minter", 
            true, 
            msg.sender, 
            block.timestamp
        );
    }
    
    function removeAuthorizedMinter(address minter) external onlyOwner {
        authorizedMinters[minter] = false;
        
        emit AuthorizationChanged(
            minter, 
            "minter", 
            false, 
            msg.sender, 
            block.timestamp
        );
    }
    
    function addAuthorizedBurner(address burner) external onlyOwner {
        authorizedBurners[burner] = true;
        
        emit AuthorizationChanged(
            burner, 
            "burner", 
            true, 
            msg.sender, 
            block.timestamp
        );
    }
    
    function removeAuthorizedBurner(address burner) external onlyOwner {
        authorizedBurners[burner] = false;
        
        emit AuthorizationChanged(
            burner, 
            "burner", 
            false, 
            msg.sender, 
            block.timestamp
        );
    }
    
    function pause(string memory reason) external onlyOwner {
        _pause();
        
        emit ContractPaused(msg.sender, reason, block.timestamp);
    }
    
    function unpause(string memory reason) external onlyOwner {
        _unpause();
        
        emit ContractUnpaused(msg.sender, reason, block.timestamp);
    }
    
    // View functions
    function getEcosystemStats() external view returns (
        uint256 currentSupply,
        uint256 maxSupply,
        uint256 totalRewards,
        uint256 totalStakesLostAmount,
        uint256 remainingMintable,
        uint256 circulatingSupply
    ) {
        return (
            totalSupply(),
            MAX_SUPPLY,
            totalRewardsDistributed,
            totalStakesLost,
            MAX_SUPPLY - totalSupply(),
            totalSupply()
        );
    }
    
    function isAuthorizedMinter(address account) external view returns (bool) {
        return authorizedMinters[account];
    }
    
    function isAuthorizedBurner(address account) external view returns (bool) {
        return authorizedBurners[account];
    }
    
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        super._update(from, to, value);
    }
}