import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "ethers";

const PetPatDeploymentModule = buildModule("PetPatDeployment", (m) => {
  // Step 1: Deploy PAT Token
  console.log("🪙 Deploying PAT Token...");
  const patToken = m.contract("PATToken", []);

  // Step 2: Deploy Treasury Manager
  console.log("🏦 Deploying Treasury Manager...");
  const treasuryManager = m.contract("TreasuryManager", [patToken]);

  // Step 3: Deploy Validation System
  console.log("✅ Deploying Validation System...");
  const validationSystem = m.contract("ValidationSystem", [patToken, treasuryManager]);

  // Step 4: Deploy Pet NFT
  console.log("🐱 Deploying Pet NFT...");
  const petNFT = m.contract("PetNFT", []);

  // Step 5: Deploy Simple Goal Manager
  console.log("🎯 Deploying Goal Manager...");
  const goalManager = m.contract("SimpleGoalManager", [
    patToken,
    treasuryManager,
    validationSystem,
    petNFT,
  ]);

  // Step 6: Setup authorizations
  console.log("🔐 Setting up contract authorizations...");

  // Authorize Treasury Manager to mint/burn PAT tokens
  m.call(patToken, "addAuthorizedMinter", [treasuryManager]);
  m.call(patToken, "addAuthorizedBurner", [treasuryManager]);

  // Authorize Goal Manager to interact with Treasury
  m.call(treasuryManager, "addAuthorizedContract", [goalManager]);

  // Authorize Goal Manager to interact with Validation System
  m.call(validationSystem, "addAuthorizedContract", [goalManager]);

  // Authorize Goal Manager to interact with Pet NFT
  m.call(petNFT, "setAuthorizedContract", [goalManager, true]);

  console.log("🎉 Pet Pat deployment complete!");

  return {
    patToken,
    treasuryManager,
    validationSystem,
    petNFT,
    goalManager,
  };
});

export default PetPatDeploymentModule;