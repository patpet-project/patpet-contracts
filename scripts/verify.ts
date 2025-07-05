import { run } from "hardhat";
import fs from "fs";

async function main() {
  console.log("🔍 Starting Sourcify contract verification...");

  // Read deployed addresses from file
  let deployedAddresses: any;
  try {
    const addressData = fs.readFileSync('deployed-addresses.json', 'utf8');
    deployedAddresses = JSON.parse(addressData);
    console.log("📋 Loaded deployed addresses from deployed-addresses.json");
  } catch (error) {
    console.error("❌ Could not load deployed-addresses.json. Please deploy contracts first.");
    process.exit(1);
  }

  // Sourcify verification helper function
  async function verifySourcify(
    contractAddress: string,
    contractName: string
  ) {
    console.log(`\n🔍 Verifying ${contractName} with Sourcify at ${contractAddress}...`);
    
    try {
      await run("sourcify", {
        address: contractAddress,
      });
      console.log(`✅ ${contractName} verified successfully with Sourcify!`);
      return true;
    } catch (error: any) {
      if (error.message.toLowerCase().includes("already verified") || 
          error.message.toLowerCase().includes("perfect match")) {
        console.log(`ℹ️ ${contractName} is already verified on Sourcify`);
        return true;
      } else {
        console.log(`❌ ${contractName} Sourcify verification failed:`, error.message);
        // Try alternative verification method
        return await tryAlternativeVerification(contractAddress, contractName);
      }
    }
  }

  // Alternative verification using different task
  async function tryAlternativeVerification(
    contractAddress: string,
    contractName: string
  ) {
    console.log(`🔄 Trying alternative verification for ${contractName}...`);
    
    try {
      // Try using the verify:sourcify task if available
      await run("verify:sourcify", {
        address: contractAddress,
      });
      console.log(`✅ ${contractName} verified with alternative method!`);
      return true;
    } catch (error: any) {
      console.log(`❌ Alternative verification also failed for ${contractName}:`, error.message);
      
      // Try manual verification approach
      return await tryManualVerification(contractAddress, contractName);
    }
  }

  // Manual verification approach
  async function tryManualVerification(
    contractAddress: string,
    contractName: string
  ) {
    console.log(`🔧 Trying manual verification approach for ${contractName}...`);
    
    try {
      // This will use the sourcify configuration from hardhat.config.ts
      await run("verify", {
        address: contractAddress,
        contract: `contracts/${contractName}.sol:${contractName}`,
      });
      console.log(`✅ ${contractName} verified with manual approach!`);
      return true;
    } catch (error: any) {
      console.log(`❌ Manual verification also failed for ${contractName}:`, error.message);
      return false;
    }
  }

  // Define contracts to verify
  const contractsToVerify = [
    {
      name: "PATToken",
      address: deployedAddresses.PATToken,
    },
    {
      name: "PatTreasuryManager",
      address: deployedAddresses.PatTreasuryManager,
    },
    {
      name: "PatValidationSystem",
      address: deployedAddresses.PatValidationSystem,
    },
    {
      name: "PatNFT",
      address: deployedAddresses.PatNFT,
    },
    {
      name: "PatGoalManager",
      address: deployedAddresses.PatGoalManager,
    },
  ];

  console.log("⏳ Waiting 10 seconds for contracts to propagate...");
  await new Promise(resolve => setTimeout(resolve, 10000));

  const verificationResults: Array<{
    name: string;
    address: string;
    verified: boolean;
  }> = [];

  // Verify each contract
  for (const contract of contractsToVerify) {
    const verified = await verifySourcify(contract.address, contract.name);
    
    verificationResults.push({
      name: contract.name,
      address: contract.address,
      verified,
    });

    // Wait between verifications to avoid rate limiting
    await new Promise(resolve => setTimeout(resolve, 5000));
  }

  // =============================================================================
  // VERIFICATION SUMMARY
  // =============================================================================
  console.log("\n📋 SOURCIFY VERIFICATION SUMMARY");
  console.log("=====================================");
  
  verificationResults.forEach(result => {
    const status = result.verified ? "✅ VERIFIED" : "❌ FAILED";
    console.log(`${status} ${result.name}: ${result.address}`);
  });
  
  console.log("=====================================");

  const successfulVerifications = verificationResults.filter(r => r.verified).length;
  const totalContracts = verificationResults.length;
  
  if (successfulVerifications === totalContracts) {
    console.log("🎉 All contracts verified successfully with Sourcify!");
  } else {
    console.log(`⚠️ ${successfulVerifications}/${totalContracts} contracts verified with Sourcify`);
  }

  // Update deployed addresses file with verification status
  const updatedAddresses = {
    ...deployedAddresses,
    verified: successfulVerifications === totalContracts,
    verificationType: "sourcify",
    verificationResults,
    lastVerificationAttempt: new Date().toISOString(),
  };

  fs.writeFileSync(
    'deployed-addresses.json',
    JSON.stringify(updatedAddresses, null, 2)
  );

  // Save Sourcify verification summary
  const verificationSummary = {
    network: deployedAddresses.network || "monadTestnet",
    timestamp: new Date().toISOString(),
    verificationType: "sourcify",
    sourcifyUrl: "https://testnet.monadexplorer.com",
    contracts: contractsToVerify.map((contract, index) => ({
      name: contract.name,
      address: contract.address,
      verified: verificationResults[index].verified,
      explorerUrl: `https://testnet.monadexplorer.com/address/${contract.address}`,
      sourcifyUrl: `https://testnet.monadexplorer.com/address/${contract.address}#code`,
    })),
    summary: {
      totalContracts,
      successfulVerifications,
      allVerified: successfulVerifications === totalContracts,
    },
  };

  fs.writeFileSync(
    'sourcify-verification-summary.json',
    JSON.stringify(verificationSummary, null, 2)
  );
  console.log("📄 Sourcify verification summary saved to sourcify-verification-summary.json");

  console.log("\n🌐 Monad Explorer Links:");
  contractsToVerify.forEach((contract, index) => {
    console.log(`   ${contract.name}: https://testnet.monadexplorer.com/address/${contract.address}`);
    if (verificationResults[index].verified) {
      console.log(`     📋 Source Code: https://testnet.monadexplorer.com/address/${contract.address}#code`);
    }
  });

  console.log("\n📚 Additional Resources:");
  console.log("   Sourcify API: https://sourcify-api-monad.blockvision.org");
  console.log("   Monad Explorer: https://testnet.monadexplorer.com");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });