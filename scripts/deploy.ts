import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Starting Pet Pat robust deployment...");
  
  const [deployer] = await ethers.getSigners();
  console.log("🔑 Deploying with account:", deployer.address);
  
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("💰 Account balance:", ethers.formatEther(balance), "ETH");

  // Dynamic gas price discovery
  async function getGasConfig() {
    try {
      const feeData = await ethers.provider.getFeeData();
      console.log("🔍 Fetching current gas prices...");
      
      if (feeData.maxFeePerGas && feeData.maxPriorityFeePerGas) {
        // EIP-1559 network
        const maxFeePerGas = feeData.maxFeePerGas * 200n / 100n; // 100% buffer
        const maxPriorityFeePerGas = feeData.maxPriorityFeePerGas * 150n / 100n; // 50% buffer
        
        console.log("⛽ Using EIP-1559 gas pricing:");
        console.log("   Max fee per gas:", ethers.formatUnits(maxFeePerGas, "gwei"), "gwei");
        console.log("   Max priority fee:", ethers.formatUnits(maxPriorityFeePerGas, "gwei"), "gwei");
        
        return {
          maxFeePerGas,
          maxPriorityFeePerGas,
          gasLimit: 8000000,
        };
      } else if (feeData.gasPrice) {
        // Legacy network
        const gasPrice = feeData.gasPrice * 150n / 100n; // 50% buffer
        
        console.log("⛽ Using legacy gas pricing:");
        console.log("   Gas price:", ethers.formatUnits(gasPrice, "gwei"), "gwei");
        
        return {
          gasPrice,
          gasLimit: 8000000,
        };
      } else {
        // Fallback
        console.log("⛽ Using fallback gas pricing (5 gwei)");
        return {
          gasPrice: ethers.parseUnits("5", "gwei"),
          gasLimit: 8000000,
        };
      }
    } catch (error) {
      console.log("⚠️ Gas price discovery failed, using fallback");
      return {
        gasPrice: ethers.parseUnits("5", "gwei"),
        gasLimit: 8000000,
      };
    }
  }

  // Helper function for deployment with retries
  async function deployWithRetry(contractName: string, factory: any, args: any[] = [], maxRetries = 3) {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        console.log(`📝 Deploying ${contractName} (attempt ${attempt}/${maxRetries})...`);
        
        const gasConfig = await getGasConfig();
        const contract = await factory.deploy(...args, gasConfig);
        await contract.waitForDeployment();
        
        const address = await contract.getAddress();
        console.log(`✅ ${contractName} deployed to:`, address);
        return contract;
      } catch (error: any) {
        console.log(`❌ Attempt ${attempt} failed:`, error.reason || error.message);
        
        if (attempt === maxRetries) {
          throw error;
        }
        
        // Wait longer between retries
        console.log(`⏳ Waiting 10 seconds before retry...`);
        await new Promise(resolve => setTimeout(resolve, 10000));
      }
    }
  }

  // Helper function for transaction with retries
  async function executeWithRetry(description: string, txFunction: () => Promise<any>, maxRetries = 3) {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        console.log(`🔧 ${description} (attempt ${attempt}/${maxRetries})...`);
        
        const gasConfig = await getGasConfig();
        const tx = await txFunction();
        await tx.wait();
        
        console.log(`✅ ${description} completed`);
        return tx;
      } catch (error: any) {
        console.log(`❌ Attempt ${attempt} failed:`, error.reason || error.message);
        
        if (attempt === maxRetries) {
          throw error;
        }
        
        console.log(`⏳ Waiting 5 seconds before retry...`);
        await new Promise(resolve => setTimeout(resolve, 5000));
      }
    }
  }

  try {
    // =============================================================================
    // STEP 1: DEPLOY PAT TOKEN
    // =============================================================================
    const PATToken = await ethers.getContractFactory("PATToken");
    const patToken = await deployWithRetry("PATToken", PATToken);
    
    await new Promise(resolve => setTimeout(resolve, 5000));

    // =============================================================================
    // STEP 2: DEPLOY TREASURY MANAGER
    // =============================================================================
    const PatTreasuryManager = await ethers.getContractFactory("PatTreasuryManager");
    const treasuryManager = await deployWithRetry(
      "PatTreasuryManager", 
      PatTreasuryManager, 
      [await patToken.getAddress()]
    );
    
    await new Promise(resolve => setTimeout(resolve, 5000));

    // =============================================================================
    // STEP 3: DEPLOY VALIDATION SYSTEM
    // =============================================================================
    const PatValidationSystem = await ethers.getContractFactory("PatValidationSystem");
    const validationSystem = await deployWithRetry(
      "PatValidationSystem",
      PatValidationSystem,
      [await patToken.getAddress(), await treasuryManager.getAddress()]
    );
    
    await new Promise(resolve => setTimeout(resolve, 5000));

    // =============================================================================
    // STEP 4: DEPLOY PET NFT
    // =============================================================================
    const PatNFT = await ethers.getContractFactory("PatNFT");
    const petNFT = await deployWithRetry("PatNFT", PatNFT);
    
    await new Promise(resolve => setTimeout(resolve, 5000));

    // =============================================================================
    // STEP 5: DEPLOY GOAL MANAGER
    // =============================================================================
    const PatGoalManager = await ethers.getContractFactory("PatGoalManager");
    const goalManager = await deployWithRetry(
      "PatGoalManager",
      PatGoalManager,
      [
        await patToken.getAddress(),
        await treasuryManager.getAddress(),
        await validationSystem.getAddress(),
        await petNFT.getAddress(),
      ]
    );
    
    await new Promise(resolve => setTimeout(resolve, 10000));

    // =============================================================================
    // STEP 6: CONFIGURE AUTHORIZATIONS
    // =============================================================================
    console.log("\n🔐 Step 6: Setting up authorizations...");
    
    await executeWithRetry(
      "Adding treasury as authorized minter",
      async () => {
        const gasConfig = await getGasConfig();
        return patToken.addAuthorizedMinter(await treasuryManager.getAddress(), gasConfig);
      }
    );
    
    await executeWithRetry(
      "Adding treasury as authorized burner",
      async () => {
        const gasConfig = await getGasConfig();
        return patToken.addAuthorizedBurner(await treasuryManager.getAddress(), gasConfig);
      }
    );
    
    await executeWithRetry(
      "Adding goal manager to treasury",
      async () => {
        const gasConfig = await getGasConfig();
        return treasuryManager.addAuthorizedContract(await goalManager.getAddress(), gasConfig);
      }
    );
    
    await executeWithRetry(
      "Adding goal manager to validation",
      async () => {
        const gasConfig = await getGasConfig();
        return validationSystem.addAuthorizedContract(await goalManager.getAddress(), gasConfig);
      }
    );
    
    await executeWithRetry(
      "Adding goal manager to NFT",
      async () => {
        const gasConfig = await getGasConfig();
        return petNFT.setAuthorizedContract(await goalManager.getAddress(), true, gasConfig);
      }
    );

    // =============================================================================
    // DEPLOYMENT SUMMARY
    // =============================================================================
    console.log("\n🎉 DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉");
    console.log("=====================================");
    console.log("📋 Contract Addresses:");
    console.log("   PATToken:", await patToken.getAddress());
    console.log("   PatTreasuryManager:", await treasuryManager.getAddress());
    console.log("   PatValidationSystem:", await validationSystem.getAddress());
    console.log("   PatNFT:", await petNFT.getAddress());
    console.log("   PatGoalManager:", await goalManager.getAddress());
    console.log("=====================================");
    
    // Save addresses to file
    const addresses = {
      PATToken: await patToken.getAddress(),
      PatTreasuryManager: await treasuryManager.getAddress(),
      PatValidationSystem: await validationSystem.getAddress(),
      PatNFT: await petNFT.getAddress(),
      PatGoalManager: await goalManager.getAddress(),
      network: "monadTestnet",
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
    };
    
    const fs = require('fs');
    fs.writeFileSync(
      'deployed-addresses.json',
      JSON.stringify(addresses, null, 2)
    );
    console.log("📄 Addresses saved to deployed-addresses.json");

  } catch (error) {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });