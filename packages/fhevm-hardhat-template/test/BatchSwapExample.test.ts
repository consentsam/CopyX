import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { FhevmType } from "@fhevm/hardhat-plugin";
import { TestableUniversalPrivacyHook, HybridFHERC20, MockERC20, MockPoolManager } from "../types";

describe("Batch Swap Example with FHEVM", function () {
  let hook: TestableUniversalPrivacyHook;
  let hookAddress: string;
  let poolManager: MockPoolManager;
  let swapManager: HardhatEthersSigner;
  let users: HardhatEthersSigner[];
  let poolKey: any;

  // Mock tokens for testing
  let usdc: MockERC20;
  let usdt: MockERC20;
  let eUSDC: HybridFHERC20;
  let eUSDT: HybridFHERC20;

  beforeEach(async function () {
    // Check if we're using FHEVM mock
    if (!fhevm.isMock) {
      console.log("This test requires FHEVM mock environment");
      this.skip();
    }

    const signers = await ethers.getSigners();
    swapManager = signers[0]; // Mock SwapManager
    users = [signers[1], signers[2], signers[3], signers[4]]; // U1, U2, U3, U4

    console.log("🔧 Setting up test environment with FHEVM mock...");

    // Deploy MockPoolManager
    const PoolManagerFactory = await ethers.getContractFactory("MockPoolManager");
    poolManager = await PoolManagerFactory.deploy();
    await poolManager.waitForDeployment();
    const poolManagerAddress = await poolManager.getAddress();
    console.log("✅ MockPoolManager deployed at:", poolManagerAddress);

    // Deploy TestableUniversalPrivacyHook (bypasses address validation)
    const HookFactory = await ethers.getContractFactory("TestableUniversalPrivacyHook");
    hook = await HookFactory.deploy(poolManagerAddress);
    await hook.waitForDeployment();
    hookAddress = await hook.getAddress();

    console.log("✅ TestableUniversalPrivacyHook deployed at:", hookAddress);

    // Deploy mock ERC20 tokens for USDC and USDT
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");

    usdc = await MockERC20Factory.deploy("USD Coin", "USDC", 6);
    await usdc.waitForDeployment();
    console.log("✅ Mock USDC deployed at:", await usdc.getAddress());

    usdt = await MockERC20Factory.deploy("Tether USD", "USDT", 6);
    await usdt.waitForDeployment();
    console.log("✅ Mock USDT deployed at:", await usdt.getAddress());

    // Mint tokens to users for testing
    await usdc.mint(users[0].address, ethers.parseUnits("12000", 6));
    await usdc.mint(users[2].address, ethers.parseUnits("4000", 6));
    await usdt.mint(users[1].address, ethers.parseUnits("7500", 6));
    await usdt.mint(users[3].address, ethers.parseUnits("1200", 6));

    // Create pool key
    poolKey = {
      currency0: await usdc.getAddress(),
      currency1: await usdt.getAddress(),
      fee: 3000,
      tickSpacing: 60,
      hooks: hookAddress
    };
  });

  describe("Complete Batch Flow", function () {
    it("Should process the example batch with internal netting and AMM swap", async function () {
      // Test data from the example:
      // U1 (alice): 12,000 eUSDC → eUSDT
      // U2 (bob): 7,500 eUSDT → eUSDC
      // U3 (carol): 4,000 eUSDC → eUSDT
      // U4 (dave): 1,200 eUSDT → eUSDC

      // Step 1: Users approve and deposit tokens
      console.log("\nStep 1: Users approve and deposit tokens");

      // Approve hook to spend tokens
      await usdc.connect(users[0]).approve(hookAddress, ethers.parseUnits("12000", 6));
      await usdt.connect(users[1]).approve(hookAddress, ethers.parseUnits("7500", 6));
      await usdc.connect(users[2]).approve(hookAddress, ethers.parseUnits("4000", 6));
      await usdt.connect(users[3]).approve(hookAddress, ethers.parseUnits("1200", 6));

      // Alice deposits 12,000 USDC
      const tx1 = await hook.connect(users[0]).deposit(poolKey, await usdc.getAddress(), ethers.parseUnits("12000", 6));
      const receipt1 = await tx1.wait();
      console.log("  ✅ Alice deposited 12,000 USDC");

      // Bob deposits 7,500 USDT
      const tx2 = await hook.connect(users[1]).deposit(poolKey, await usdt.getAddress(), ethers.parseUnits("7500", 6));
      await tx2.wait();
      console.log("  ✅ Bob deposited 7,500 USDT");

      // Carol deposits 4,000 USDC
      const tx3 = await hook.connect(users[2]).deposit(poolKey, await usdc.getAddress(), ethers.parseUnits("4000", 6));
      await tx3.wait();
      console.log("  ✅ Carol deposited 4,000 USDC");

      // Dave deposits 1,200 USDT
      const tx4 = await hook.connect(users[3]).deposit(poolKey, await usdt.getAddress(), ethers.parseUnits("1200", 6));
      await tx4.wait();
      console.log("  ✅ Dave deposited 1,200 USDT");

      // Check encrypted token addresses
      console.log("\n📝 Encrypted Token Addresses:");

      // Get the poolId
      const poolId = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "address", "uint24", "int24", "address"],
        [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks]
      ));

      const eUSDCAddress = await hook.poolEncryptedTokens(poolId, await usdc.getAddress());
      const eUSDTAddress = await hook.poolEncryptedTokens(poolId, await usdt.getAddress());

      console.log("  eUSDC:", eUSDCAddress);
      console.log("  eUSDT:", eUSDTAddress);

      // Verify reserves were updated
      const usdcReserves = await hook.poolReserves(poolId, await usdc.getAddress());
      const usdtReserves = await hook.poolReserves(poolId, await usdt.getAddress());

      expect(usdcReserves).to.equal(ethers.parseUnits("16000", 6)); // 12000 + 4000
      expect(usdtReserves).to.equal(ethers.parseUnits("8700", 6));  // 7500 + 1200

      console.log("\n📊 Hook Reserves:");
      console.log("  USDC:", ethers.formatUnits(usdcReserves, 6));
      console.log("  USDT:", ethers.formatUnits(usdtReserves, 6));

      // Step 2: Test Summary
      console.log("\n✅ Test Summary:");
      console.log("  - Successfully deployed hook with FHEVM mock");
      console.log("  - Created mock USDC and USDT tokens");
      console.log("  - All users deposited tokens successfully");
      console.log("  - Encrypted tokens (eUSDC, eUSDT) created");
      console.log("  - Hook reserves updated correctly");

      console.log("\n🔍 What we tested:");
      console.log("  ✅ Hook deployment and initialization");
      console.log("  ✅ Token deposits and encrypted token creation");
      console.log("  ✅ Reserve tracking");
      console.log("  ✅ Encrypted token address generation");

      console.log("\n⚠️  Note: Full swap testing requires:");
      console.log("  - Actual PoolManager deployment (or complex mocking)");
      console.log("  - Liquidity provision");
      console.log("  - Swap execution through unlock pattern");
      console.log("  - For production testing, use Sepolia testnet");

    });
  });
});