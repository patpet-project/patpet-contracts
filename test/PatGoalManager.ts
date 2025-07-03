import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { TestHelpers, TestContracts, TestUsers } from "./helpers/TestHelpers";

describe("SimpleGoalManager", function () {
  let contracts: TestContracts;
  let users: TestUsers;

  beforeEach(async function () {
    const setup = await TestHelpers.setupTestEnvironment();
    contracts = setup.contracts;
    users = setup.users;
  });

  describe("Deployment", function () {
    it("Should deploy with correct initial values", async function () {
      expect(await contracts.goalManager.nextGoalId()).to.equal(0);
      expect(await contracts.goalManager.nextMilestoneId()).to.equal(0);
      expect(await contracts.goalManager.MILESTONE_XP()).to.equal(25);
      expect(await contracts.goalManager.COMPLETION_BONUS_XP()).to.equal(100);
    });

    it("Should emit GoalSystemInitialized event", async function () {
      // Deploy new contract to test initialization event
      const GoalManagerFactory = await ethers.getContractFactory("SimpleGoalManager");
      const tx = await GoalManagerFactory.deploy(
        await contracts.patToken.getAddress(),
        await contracts.treasuryManager.getAddress(),
        await contracts.validationSystem.getAddress(),
        await contracts.petNFT.getAddress()
      );
      
      await TestHelpers.expectEvent(tx.deploymentTransaction(), "GoalSystemInitialized");
    });
  });

  describe("Goal Creation", function () {
    it("Should create goal with pet successfully", async function () {
      const { goalId, petTokenId } = await TestHelpers.createTestGoal(contracts, users.user1);

      expect(goalId).to.equal(0); // First goal
      expect(petTokenId).to.equal(0); // First pet

      // Check goal is active
      expect(await contracts.goalManager.isGoalActive(goalId)).to.be.true;
      expect(await contracts.goalManager.isGoalExpired(goalId)).to.be.false;
    });

    it("Should emit GoalCreated event with correct data", async function () {
      const stakeAmount = ethers.parseEther("200");
      
      await contracts.patToken.connect(users.user1).approve(
        await contracts.treasuryManager.getAddress(),
        stakeAmount
      );

      const tx = await contracts.goalManager.connect(users.user1).createGoal(
        "Fitness Challenge",
        stakeAmount,
        30, // 30 days
        "Gym Buddy",
        2, // PLANT
        TestHelpers.mockIPFSHash("fitness"),
        10 // milestones
      );

      await TestHelpers.expectEvent(tx, "GoalCreated");
    });

    it("Should fail without sufficient token approval", async function () {
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user1).createGoal(
          "Test Goal",
          ethers.parseEther("100"),
          30,
          "Test Pet",
          1,
          TestHelpers.mockIPFSHash(),
          5
        ),
        "Transfer failed"
      );
    });

    it("Should fail with invalid parameters", async function () {
      await contracts.patToken.connect(users.user1).approve(
        await contracts.treasuryManager.getAddress(),
        ethers.parseEther("100")
      );

      // Zero stake amount
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user1).createGoal(
          "Test Goal",
          0,
          30,
          "Test Pet",
          1,
          TestHelpers.mockIPFSHash(),
          5
        ),
        "Invalid stake"
      );

      // Zero duration
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user1).createGoal(
          "Test Goal",
          ethers.parseEther("100"),
          0,
          "Test Pet",
          1,
          TestHelpers.mockIPFSHash(),
          5
        ),
        "Invalid duration"
      );

      // Zero milestones
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user1).createGoal(
          "Test Goal",
          ethers.parseEther("100"),
          30,
          "Test Pet",
          1,
          TestHelpers.mockIPFSHash(),
          0
        ),
        "Need milestones"
      );
    });
  });

  describe("Milestone Management", function () {
    let goalId: bigint;

    beforeEach(async function () {
      const result = await TestHelpers.createTestGoal(contracts, users.user1);
      goalId = result.goalId;
    });

    it("Should create milestone successfully", async function () {
      const tx = await contracts.goalManager.connect(users.user1).createMilestone(
        goalId,
        "Complete daily workout"
      );

      await TestHelpers.expectEvent(tx, "MilestoneCreated");
    });

    it("Should create multiple milestones", async function () {
      // Create first milestone
      await contracts.goalManager.connect(users.user1).createMilestone(
        goalId,
        "Milestone 1"
      );

      // Create second milestone
      const tx = await contracts.goalManager.connect(users.user1).createMilestone(
        goalId,
        "Milestone 2"
      );

      await TestHelpers.expectEvent(tx, "MilestoneCreated");
    });

    it("Should only allow goal owner to create milestones", async function () {
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user2).createMilestone(
          goalId,
          "Unauthorized milestone"
        ),
        "Not goal owner"
      );
    });

    it("Should not allow milestone creation for inactive goals", async function () {
      // Fail the goal first
      await TestHelpers.advanceTimeAndMine(31 * 24 * 60 * 60); // 31 days
      await contracts.goalManager.failGoal(goalId, TestHelpers.mockIPFSHash("failed"));

      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user1).createMilestone(
          goalId,
          "Late milestone"
        ),
        "Goal not active"
      );
    });
  });

  describe("Milestone Submission", function () {
    let goalId: bigint;
    let milestoneId: bigint;

    beforeEach(async function () {
      const result = await TestHelpers.createTestGoal(contracts, users.user1);
      goalId = result.goalId;
      
      milestoneId = await TestHelpers.createTestMilestone(
        contracts,
        users.user1,
        goalId,
        "Daily Exercise"
      );

      // Register validators for validation system
      await TestHelpers.registerValidator(contracts, users.validator1);
      await TestHelpers.registerValidator(contracts, users.validator2);
      await TestHelpers.registerValidator(contracts, users.validator3);
    });

    it("Should submit milestone evidence successfully", async function () {
      const evidenceHash = TestHelpers.mockIPFSHash("evidence");

      const tx = await contracts.goalManager.connect(users.user1).submitMilestone(
        milestoneId,
        evidenceHash
      );

      await TestHelpers.expectEvent(tx, "MilestoneSubmitted");
    });

    it("Should only allow goal owner to submit evidence", async function () {
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user2).submitMilestone(
          milestoneId,
          TestHelpers.mockIPFSHash("unauthorized")
        ),
        "Not authorized"
      );
    });

    it("Should not allow submission for completed milestones", async function () {
      // Complete the milestone first
      await contracts.goalManager.completeMilestone(
        milestoneId,
        TestHelpers.mockIPFSHash("completed")
      );

      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user1).submitMilestone(
          milestoneId,
          TestHelpers.mockIPFSHash("late-evidence")
        ),
        "Already completed"
      );
    });
  });

  describe("Milestone Completion", function () {
    let goalId: bigint;
    let petTokenId: bigint;
    let milestoneId: bigint;

    beforeEach(async function () {
      const result = await TestHelpers.createTestGoal(contracts, users.user1);
      goalId = result.goalId;
      petTokenId = result.petTokenId;
      
      milestoneId = await TestHelpers.createTestMilestone(
        contracts,
        users.user1,
        goalId,
        "Exercise milestone"
      );
    });

    it("Should complete milestone and award XP", async function () {
      const petMetadata = TestHelpers.mockIPFSHash("xp-gained");

      const tx = await contracts.goalManager.completeMilestone(milestoneId, petMetadata);

      await TestHelpers.expectEvent(tx, "MilestoneCompleted");
      // Should also trigger pet XP events through the pet contract
    });

    it("Should only allow authorized contracts to complete milestones", async function () {
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user1).completeMilestone(
          milestoneId,
          TestHelpers.mockIPFSHash("unauthorized")
        ),
        "Not authorized"
      );
    });

    it("Should complete goal when all milestones are done", async function () {
      // Create a goal with only 1 milestone for easy completion
      const { goalId: singleGoalId } = await TestHelpers.createTestGoal(
        contracts,
        users.user2,
        { totalMilestones: 1 }
      );

      const singleMilestoneId = await TestHelpers.createTestMilestone(
        contracts,
        users.user2,
        singleGoalId,
        "Only milestone"
      );

      // Complete the milestone
      const tx = await contracts.goalManager.completeMilestone(
        singleMilestoneId,
        TestHelpers.mockIPFSHash("goal-complete")
      );

      // Should emit both MilestoneCompleted and GoalCompleted events
      await TestHelpers.expectEvent(tx, "MilestoneCompleted");
      await TestHelpers.expectEvent(tx, "GoalCompleted");
    });

    it("Should not complete already completed milestone", async function () {
      // Complete milestone first
      await contracts.goalManager.completeMilestone(
        milestoneId,
        TestHelpers.mockIPFSHash("first-completion")
      );

      // Try to complete again
      await TestHelpers.expectRevert(
        contracts.goalManager.completeMilestone(
          milestoneId,
          TestHelpers.mockIPFSHash("second-completion")
        ),
        "Already completed"
      );
    });
  });

  describe("Goal Failure", function () {
    let goalId: bigint;
    let petTokenId: bigint;

    beforeEach(async function () {
      const result = await TestHelpers.createTestGoal(contracts, users.user1, {
        durationDays: 1 // Short duration for testing expiration
      });
      goalId = result.goalId;
      petTokenId = result.petTokenId;
    });

    it("Should allow goal owner to fail their own goal", async function () {
      const sadMetadata = TestHelpers.mockIPFSHash("owner-failed");

      const tx = await contracts.goalManager.connect(users.user1).failGoal(goalId, sadMetadata);

      await TestHelpers.expectEvent(tx, "GoalFailed");
      expect(await contracts.goalManager.isGoalActive(goalId)).to.be.false;
    });

    it("Should allow admin to fail any goal", async function () {
      const sadMetadata = TestHelpers.mockIPFSHash("admin-failed");

      const tx = await contracts.goalManager.connect(users.owner).failGoal(goalId, sadMetadata);

      await TestHelpers.expectEvent(tx, "GoalFailed");
    });

    it("Should automatically fail expired goals", async function () {
      // Advance time past goal deadline
      await TestHelpers.advanceTimeAndMine(2 * 24 * 60 * 60); // 2 days

      expect(await contracts.goalManager.isGoalExpired(goalId)).to.be.true;

      // Anyone can fail an expired goal
      const tx = await contracts.goalManager.connect(users.user2).failGoal(
        goalId,
        TestHelpers.mockIPFSHash("expired")
      );

      await TestHelpers.expectEvent(tx, "GoalFailed");
    });

    it("Should not allow unauthorized users to fail active goals", async function () {
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user2).failGoal(
          goalId,
          TestHelpers.mockIPFSHash("unauthorized")
        ),
        "Not authorized"
      );
    });

    it("Should not fail already completed goals", async function () {
      // Create and complete a simple goal
      const { goalId: completedGoalId } = await TestHelpers.createTestGoal(
        contracts,
        users.user2,
        { totalMilestones: 1 }
      );

      const milestoneId = await TestHelpers.createTestMilestone(
        contracts,
        users.user2,
        completedGoalId
      );

      await contracts.goalManager.completeMilestone(
        milestoneId,
        TestHelpers.mockIPFSHash("completed")
      );

      // Try to fail completed goal
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user2).failGoal(
          completedGoalId,
          TestHelpers.mockIPFSHash("try-to-fail")
        ),
        "Goal not active"
      );
    });
  });

  describe("Milestone Rejection", function () {
    let goalId: bigint;
    let milestoneId: bigint;

    beforeEach(async function () {
      const result = await TestHelpers.createTestGoal(contracts, users.user1);
      goalId = result.goalId;
      
      milestoneId = await TestHelpers.createTestMilestone(
        contracts,
        users.user1,
        goalId
      );
    });

    it("Should reject milestone and make pet sad", async function () {
      const sadMetadata = TestHelpers.mockIPFSHash("rejected");

      const tx = await contracts.goalManager.rejectMilestone(milestoneId, sadMetadata);

      await TestHelpers.expectEvent(tx, "MilestoneRejected");
    });

    it("Should only allow authorized contracts to reject milestones", async function () {
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user1).rejectMilestone(
          milestoneId,
          TestHelpers.mockIPFSHash("unauthorized")
        ),
        "Not authorized"
      );
    });
  });

  describe("Bonus XP System", function () {
    let goalId: bigint;
    let petTokenId: bigint;

    beforeEach(async function () {
      const result = await TestHelpers.createTestGoal(contracts, users.user1);
      goalId = result.goalId;
      petTokenId = result.petTokenId;
    });

    it("Should allow owner to award bonus XP", async function () {
      const bonusXP = 50;
      const reason = "Special achievement";
      const metadata = TestHelpers.mockIPFSHash("bonus");

      const tx = await contracts.goalManager.addBonusXP(goalId, bonusXP, reason, metadata);

      await TestHelpers.expectEvent(tx, "BonusXPAwarded");
    });

    it("Should not allow non-owner to award bonus XP", async function () {
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user1).addBonusXP(
          goalId,
          50,
          "Unauthorized bonus",
          TestHelpers.mockIPFSHash("bonus")
        ),
        "OwnableUnauthorizedAccount"
      );
    });

    it("Should not award bonus XP to inactive goals", async function () {
      // Fail the goal first
      await contracts.goalManager.connect(users.user1).failGoal(
        goalId,
        TestHelpers.mockIPFSHash("failed")
      );

      await TestHelpers.expectRevert(
        contracts.goalManager.addBonusXP(
          goalId,
          50,
          "Bonus for failed goal",
          TestHelpers.mockIPFSHash("bonus")
        ),
        "Goal not active"
      );
    });
  });

  describe("Statistics and Events", function () {
    beforeEach(async function () {
      // Create a few goals for statistics
      for (let i = 0; i < 3; i++) {
        await TestHelpers.createTestGoal(contracts, users.user1, {
          title: `Goal ${i}`,
          stakeAmount: ethers.parseEther((100 + i * 50).toString())
        });
      }
    });

    it("Should emit system statistics", async function () {
      const tx = await contracts.goalManager.emitSystemStatistics();
      await TestHelpers.expectEvent(tx, "GoalSystemStatistics");
    });

    it("Should track goal creation statistics", async function () {
      expect(await contracts.goalManager.nextGoalId()).to.equal(3); // 3 goals created
    });
  });

  describe("Integration with Other Contracts", function () {
    let goalId: bigint;
    let petTokenId: bigint;
    let milestoneId: bigint;

    beforeEach(async function () {
      const result = await TestHelpers.createTestGoal(contracts, users.user1);
      goalId = result.goalId;
      petTokenId = result.petTokenId;
      
      milestoneId = await TestHelpers.createTestMilestone(contracts, users.user1, goalId);
    });

    it("Should integrate with PetNFT for XP rewards", async function () {
      const petMetadata = TestHelpers.mockIPFSHash("xp-integration");

      // Complete milestone should trigger pet XP gain
      await contracts.goalManager.completeMilestone(milestoneId, petMetadata);

      // Verify pet exists and has expected properties
      expect(await contracts.petNFT.exists(petTokenId)).to.be.true;
    });

    it("Should integrate with Treasury for stake management", async function () {
      // Goal creation should transfer tokens to treasury
      const initialTreasuryBalance = await contracts.patToken.balanceOf(
        await contracts.treasuryManager.getAddress()
      );

      const { goalId: newGoalId } = await TestHelpers.createTestGoal(
        contracts,
        users.user2,
        { stakeAmount: ethers.parseEther("200") }
      );

      const finalTreasuryBalance = await contracts.patToken.balanceOf(
        await contracts.treasuryManager.getAddress()
      );

      expect(finalTreasuryBalance).to.be.greaterThan(initialTreasuryBalance);
    });

    it("Should integrate with ValidationSystem for milestone validation", async function () {
      // Register validators
      await TestHelpers.registerValidator(contracts, users.validator1);
      await TestHelpers.registerValidator(contracts, users.validator2);
      await TestHelpers.registerValidator(contracts, users.validator3);

      // Submit milestone should trigger validation request
      const evidenceHash = TestHelpers.mockIPFSHash("evidence");
      
      const tx = await contracts.goalManager.connect(users.user1).submitMilestone(
        milestoneId,
        evidenceHash
      );

      // Should emit milestone submitted event
      await TestHelpers.expectEvent(tx, "MilestoneSubmitted");
    });
  });

  describe("Edge Cases and Error Handling", function () {
    it("Should handle non-existent goal operations", async function () {
      const nonExistentGoalId = 999n;

      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user1).createMilestone(
          nonExistentGoalId,
          "Milestone for non-existent goal"
        ),
        "Not goal owner"
      );
    });

    it("Should handle non-existent milestone operations", async function () {
      const nonExistentMilestoneId = 999n;

      await TestHelpers.expectRevert(
        contracts.goalManager.completeMilestone(
          nonExistentMilestoneId,
          TestHelpers.mockIPFSHash("non-existent")
        ),
        "Goal not active"
      );
    });

    it("Should handle zero amounts gracefully", async function () {
      const { goalId } = await TestHelpers.createTestGoal(contracts, users.user1);

      // Should not revert but may not do much
      await contracts.goalManager.addBonusXP(
        goalId,
        0,
        "Zero bonus",
        TestHelpers.mockIPFSHash("zero")
      );
    });
  });

  describe("Access Control", function () {
    it("Should properly check goal ownership", async function () {
      const { goalId } = await TestHelpers.createTestGoal(contracts, users.user1);

      // Owner should be able to create milestones
      await contracts.goalManager.connect(users.user1).createMilestone(
        goalId,
        "Owner milestone"
      );

      // Non-owner should not be able to create milestones
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user2).createMilestone(
          goalId,
          "Non-owner milestone"
        ),
        "Not goal owner"
      );
    });

    it("Should properly enforce authorization for privileged operations", async function () {
      const { goalId } = await TestHelpers.createTestGoal(contracts, users.user1);

      // Only owner should be able to add bonus XP
      await TestHelpers.expectRevert(
        contracts.goalManager.connect(users.user1).addBonusXP(
          goalId,
          50,
          "Unauthorized bonus",
          TestHelpers.mockIPFSHash("bonus")
        ),
        "OwnableUnauthorizedAccount"
      );
    });
  });

  describe("Gas Optimization", function () {
    it("Should have reasonable gas costs for goal creation", async function () {
      await contracts.patToken.connect(users.user1).approve(
        await contracts.treasuryManager.getAddress(),
        ethers.parseEther("100")
      );

      const tx = await contracts.goalManager.connect(users.user1).createGoal(
        "Gas Test Goal",
        ethers.parseEther("100"),
        30,
        "Gas Pet",
        1,
        TestHelpers.mockIPFSHash("gas"),
        5
      );

      const receipt = await tx.wait();
      
      // Goal creation should be under 500k gas (reasonable for complex operation)
      expect(receipt!.gasUsed).to.be.lessThan(500000);
    });

    it("Should have reasonable gas costs for milestone operations", async function () {
      const { goalId } = await TestHelpers.createTestGoal(contracts, users.user1);

      const tx = await contracts.goalManager.connect(users.user1).createMilestone(
        goalId,
        "Gas Test Milestone"
      );

      const receipt = await tx.wait();
      
      // Milestone creation should be under 100k gas
      expect(receipt!.gasUsed).to.be.lessThan(100000);
    });
  });
});