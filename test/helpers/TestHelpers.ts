import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { 
  PATToken, 
  PatTreasuryManager, 
  PatValidationSystem, 
  PatNFT, 
  PatGoalManager 
} from "../../typechain-types";
import { Signer } from "ethers";

export interface TestContracts {
  patToken: PATToken;
  treasuryManager: PatTreasuryManager;
  validationSystem: PatValidationSystem;
  petNFT: PatNFT;
  goalManager: PatGoalManager;
}

export interface TestUsers {
  owner: Signer;
  user1: Signer;
  user2: Signer;
  validator1: Signer;
  validator2: Signer;
  validator3: Signer;
}

export class TestHelpers {
  static async deployContracts(): Promise<TestContracts> {
    // Deploy PAT Token
    const PATTokenFactory = await ethers.getContractFactory("PATToken");
    const patToken = await PATTokenFactory.deploy();
    await patToken.waitForDeployment();

    // Deploy Treasury Manager
    const TreasuryManagerFactory = await ethers.getContractFactory("PatTreasuryManager");
    const treasuryManager = await TreasuryManagerFactory.deploy(await patToken.getAddress());
    await treasuryManager.waitForDeployment();

    // Deploy Validation System
    const ValidationSystemFactory = await ethers.getContractFactory("PatValidationSystem");
    const validationSystem = await ValidationSystemFactory.deploy(
      await patToken.getAddress(),
      await treasuryManager.getAddress()
    );
    await validationSystem.waitForDeployment();

    // Deploy Pet NFT
    const PetNFTFactory = await ethers.getContractFactory("PetNFT");
    const petNFT = await PetNFTFactory.deploy();
    await petNFT.waitForDeployment();

    // Deploy Goal Manager
    const GoalManagerFactory = await ethers.getContractFactory("PatGoalManager");
    const goalManager = await GoalManagerFactory.deploy(
      await patToken.getAddress(),
      await treasuryManager.getAddress(),
      await validationSystem.getAddress(),
      await petNFT.getAddress()
    );
    await goalManager.waitForDeployment();

    // Setup authorizations
    await patToken.addAuthorizedMinter(await treasuryManager.getAddress());
    await patToken.addAuthorizedBurner(await treasuryManager.getAddress());
    await treasuryManager.addAuthorizedContract(await goalManager.getAddress());
    await validationSystem.addAuthorizedContract(await goalManager.getAddress());
    await petNFT.setAuthorizedContract(await goalManager.getAddress(), true);

    return {
      patToken,
      treasuryManager,
      validationSystem,
      petNFT,
      goalManager,
    };
  }

  static async getTestUsers(): Promise<TestUsers> {
    const [owner, user1, user2, validator1, validator2, validator3] = await ethers.getSigners();
    return {
      owner,
      user1,
      user2,
      validator1,
      validator2,
      validator3,
    };
  }

  static async setupTestEnvironment(): Promise<{ contracts: TestContracts; users: TestUsers }> {
    const contracts = await this.deployContracts();
    const users = await this.getTestUsers();

    // Distribute PAT tokens to test users
    const transferAmount = ethers.parseEther("10000");
    await contracts.patToken.transfer(await users.user1.getAddress(), transferAmount);
    await contracts.patToken.transfer(await users.user2.getAddress(), transferAmount);
    await contracts.patToken.transfer(await users.validator1.getAddress(), transferAmount);
    await contracts.patToken.transfer(await users.validator2.getAddress(), transferAmount);
    await contracts.patToken.transfer(await users.validator3.getAddress(), transferAmount);

    return { contracts, users };
  }

  static async createTestGoal(
    contracts: TestContracts,
    user: Signer,
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
    await contracts.patToken.connect(user).approve(
      await contracts.treasuryManager.getAddress(),
      stakeAmount
    );

    // Create goal
    const tx = await contracts.goalManager.connect(user).createGoal(
      title,
      stakeAmount,
      durationDays,
      petName,
      petType,
      "QmTestMetadata", // Mock IPFS hash
      totalMilestones
    );

    const receipt = await tx.wait();
    const event = receipt?.logs.find(
      (log: any) => log.fragment?.name === "GoalCreated"
    );

    if (!event) {
      throw new Error("GoalCreated event not found");
    }

    const goalId = event.args[0];
    const petTokenId = event.args[2];

    return { goalId, petTokenId };
  }

  static async createTestMilestone(
    contracts: TestContracts,
    user: Signer,
    goalId: bigint,
    description: string = "Test Milestone"
  ): Promise<bigint> {
    const tx = await contracts.goalManager.connect(user).createMilestone(goalId, description);
    const receipt = await tx.wait();
    
    const event = receipt?.logs.find(
      (log: any) => log.fragment?.name === "MilestoneCreated"
    );

    if (!event) {
      throw new Error("MilestoneCreated event not found");
    }

    return event.args[0]; // milestoneId
  }

  static async registerValidator(
    contracts: TestContracts,
    validator: Signer,
    stakeAmount: bigint = ethers.parseEther("100")
  ): Promise<void> {
    await contracts.patToken.connect(validator).approve(
      await contracts.validationSystem.getAddress(),
      stakeAmount
    );

    await contracts.validationSystem.connect(validator).registerValidator(stakeAmount);
  }

  static async advanceTimeAndMine(seconds: number): Promise<void> {
    await time.increase(seconds);
  }

  static async expectEvent(
    tx: any,
    eventName: string,
    eventArgs?: any[]
  ): Promise<void> {
    const receipt = await tx.wait();
    const event = receipt?.logs.find(
      (log: any) => log.fragment?.name === eventName
    );

    expect(event).to.exist;
    
    if (eventArgs) {
      eventArgs.forEach((arg, index) => {
        expect(event.args[index]).to.equal(arg);
      });
    }
  }

  static async expectRevert(
    promise: Promise<any>,
    expectedError: string
  ): Promise<void> {
    try {
      await promise;
      expect.fail("Expected transaction to revert");
    } catch (error: any) {
      expect(error.message).to.include(expectedError);
    }
  }

  static formatPATAmount(amount: bigint): string {
    return ethers.formatEther(amount);
  }

  static parsePATAmount(amount: string): bigint {
    return ethers.parseEther(amount);
  }

  static async getBlockTimestamp(): Promise<number> {
    const block = await ethers.provider.getBlock("latest");
    return block!.timestamp;
  }

  static calculateExperienceForLevel(level: number): number {
    return (level - 1) * 50;
  }

  static calculateEvolutionStage(experience: number): string {
    if (experience >= 500) return "ADULT";
    if (experience >= 100) return "BABY";
    return "EGG";
  }

  static async waitForTransaction(tx: any): Promise<any> {
    return await tx.wait();
  }

  static mockIPFSHash(suffix: string = ""): string {
    return `QmMockIPFSHash${suffix}${Math.random().toString(36).substring(7)}`;
  }
}