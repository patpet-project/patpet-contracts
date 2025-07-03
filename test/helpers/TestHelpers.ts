import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { 
  PATToken, 
  PatTreasuryManager, 
  PatValidationSystem, 
  PatNFT, 
  PatGoalManager 
} from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

export interface TestContracts {
  patToken: PATToken;
  treasuryManager: PatTreasuryManager;
  validationSystem: PatValidationSystem;
  petNFT: PatNFT;
  goalManager: PatGoalManager;
}

export interface TestUsers {
  owner: HardhatEthersSigner;
  user1: HardhatEthersSigner;
  user2: HardhatEthersSigner;
  validator1: HardhatEthersSigner;
  validator2: HardhatEthersSigner;
  validator3: HardhatEthersSigner;
}

export class TestHelpers {
  static async deployContractsFixture(): Promise<TestContracts & TestUsers> {
    // Get signers
    const [owner, user1, user2, validator1, validator2, validator3] = await ethers.getSigners();

    // Deploy PAT Token
    const patToken = await ethers.deployContract("PATToken");
    await patToken.waitForDeployment();

    // Deploy Treasury Manager
    const treasuryManager = await ethers.deployContract("PatTreasuryManager", [await patToken.getAddress()]);
    await treasuryManager.waitForDeployment();

    // Deploy Validation System
    const validationSystem = await ethers.deployContract("PatValidationSystem", [
      await patToken.getAddress(),
      await treasuryManager.getAddress()
    ]);
    await validationSystem.waitForDeployment();

    // Deploy Pet NFT
    const petNFT = await ethers.deployContract("PatNFT");
    await petNFT.waitForDeployment();

    // Deploy Goal Manager
    const goalManager = await ethers.deployContract("PatGoalManager", [
      await patToken.getAddress(),
      await treasuryManager.getAddress(),
      await validationSystem.getAddress(),
      await petNFT.getAddress()
    ]);
    await goalManager.waitForDeployment();

    // Setup authorizations
    await patToken.addAuthorizedMinter(await treasuryManager.getAddress());
    await patToken.addAuthorizedBurner(await treasuryManager.getAddress());
    await treasuryManager.addAuthorizedContract(await goalManager.getAddress());
    await validationSystem.addAuthorizedContract(await goalManager.getAddress());
    await petNFT.setAuthorizedContract(await goalManager.getAddress(), true);

    // Distribute PAT tokens to test users
    const transferAmount = ethers.parseEther("10000");
    await patToken.transfer(user1.address, transferAmount);
    await patToken.transfer(user2.address, transferAmount);
    await patToken.transfer(validator1.address, transferAmount);
    await patToken.transfer(validator2.address, transferAmount);
    await patToken.transfer(validator3.address, transferAmount);

    return {
      patToken,
      treasuryManager,
      validationSystem,
      petNFT,
      goalManager,
      owner,
      user1,
      user2,
      validator1,
      validator2,
      validator3,
    };
  }

  static async createTestGoal(
    goalManager: PatGoalManager,
    patToken: PATToken,
    treasuryManager: PatTreasuryManager,
    user: HardhatEthersSigner,
    options: {
      title?: string;
      stakeAmount?: bigint;
      durationDays?: number;
      petName?: string;
      petType?: number;
      totalMilestones?: number;
    } = {}
  ): Promise<{ goalId: bigint; petTokenId: bigint }> {
    const {
      title = "Test Goal",
      stakeAmount = ethers.parseEther("100"),
      durationDays = 30,
      petName = "Test Pet",
      petType = 1, // CAT
      totalMilestones = 5,
    } = options;

    // Approve tokens
    await patToken.connect(user).approve(await treasuryManager.getAddress(), stakeAmount);

    // Create goal and wait for transaction
    const tx = await goalManager.connect(user).createGoal(
      title,
      stakeAmount,
      durationDays,
      petName,
      petType,
      "QmTestMetadata",
      totalMilestones
    );

    const receipt = await tx.wait();
    if (!receipt) throw new Error("Transaction failed");

    // Parse events using modern approach
    const goalCreatedEvent = receipt.logs.find((log) => {
      try {
        const parsed = goalManager.interface.parseLog({
          topics: log.topics as string[],
          data: log.data,
        });
        return parsed?.name === "GoalCreated";
      } catch {
        return false;
      }
    });

    if (!goalCreatedEvent) {
      throw new Error("GoalCreated event not found");
    }

    const parsedEvent = goalManager.interface.parseLog({
      topics: goalCreatedEvent.topics as string[],
      data: goalCreatedEvent.data,
    });

    if (!parsedEvent) {
      throw new Error("Failed to parse GoalCreated event");
    }

    return {
      goalId: parsedEvent.args[0],
      petTokenId: parsedEvent.args[6]
    };
  }

  static async createTestMilestone(
    goalManager: PatGoalManager,
    user: HardhatEthersSigner,
    goalId: bigint,
    description: string = "Test Milestone"
  ): Promise<bigint> {
    const tx = await goalManager.connect(user).createMilestone(goalId, description);
    const receipt = await tx.wait();
    if (!receipt) throw new Error("Transaction failed");
    
    const milestoneCreatedEvent = receipt.logs.find((log) => {
      try {
        const parsed = goalManager.interface.parseLog({
          topics: log.topics as string[],
          data: log.data,
        });
        return parsed?.name === "MilestoneCreated";
      } catch {
        return false;
      }
    });

    if (!milestoneCreatedEvent) {
      throw new Error("MilestoneCreated event not found");
    }

    const parsedEvent = goalManager.interface.parseLog({
      topics: milestoneCreatedEvent.topics as string[],
      data: milestoneCreatedEvent.data,
    });

    if (!parsedEvent) {
      throw new Error("Failed to parse MilestoneCreated event");
    }

    return parsedEvent.args[0];
  }

  static async registerValidator(
    validationSystem: PatValidationSystem,
    patToken: PATToken,
    validator: HardhatEthersSigner,
    stakeAmount: bigint = ethers.parseEther("100")
  ): Promise<void> {
    await patToken.connect(validator).approve(await validationSystem.getAddress(), stakeAmount);
    await validationSystem.connect(validator).registerValidator(stakeAmount);
  }

  static mockIPFSHash(suffix: string = ""): string {
    return `QmMockIPFSHash${suffix}${Math.random().toString(36).substring(7)}`;
  }

  static async expectEvent(
    tx: any,
    contract: any,
    eventName: string
  ): Promise<void> {
    const receipt = await tx.wait();
    
    const eventFound = receipt?.logs.some((log: any) => {
      try {
        const parsed = contract.interface.parseLog({
          topics: log.topics as string[],
          data: log.data,
        });
        return parsed?.name === eventName;
      } catch {
        return false;
      }
    });

    expect(eventFound).to.be.true;
  }

  static async expectRevert(
    promise: Promise<any>,
    expectedError: string
  ): Promise<void> {
    await expect(promise).to.be.revertedWith(expectedError);
  }
}