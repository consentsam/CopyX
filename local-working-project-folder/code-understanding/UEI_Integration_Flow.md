# Universal Encrypted Intent (UEI) Integration Flow

## Overview
The UEI system enables encrypted trading intents to be submitted from the frontend, processed by AVS operators, and executed on-chain while maintaining privacy through ZAMA FHEVM encryption.

## Complete Flow Architecture

### 1. Frontend Encryption & Submission

#### Step 1: User Initiates Trade on Frontend
- User selects trade parameters (tokens, amounts, strategy)
- Frontend prepares the Universal Execution Intent (UEI) with:
  - **Decoder Address**: Protocol-specific sanitizer/decoder contract
  - **Target Address**: The actual protocol to interact with (e.g., Aave, Uniswap)
  - **Function Selector**: The 4-byte function signature to call
  - **Arguments**: Function parameters (addresses, amounts, etc.)
  - **Argument Types**: Type information for each argument

#### Step 2: Batch Encryption using ZAMA FHEVM
The frontend (or `createEncryptedUEITasks.ts`) performs batch encryption:
```typescript
// All components encrypted in a single batch operation
const batchEncrypted = await batchEncryptUEIComponents(
    decoder,      // → eaddress (encrypted address)
    target,       // → eaddress (encrypted address)
    selector,     // → euint32 (encrypted 4-byte selector)
    args,         // → euint256[] (encrypted arguments)
    contractAddress,
    signerAddress
);
```

This returns:
- Encrypted handles (bytes32) for each component
- Input proof for FHE permission granting

#### Step 3: Create Encrypted Blob
The encrypted components are encoded into a blob:
```solidity
bytes ctBlob = abi.encode(
    encDecoder,    // bytes32 handle
    encTarget,     // bytes32 handle
    encSelector,   // bytes32 handle
    argTypes,      // uint8[] (unencrypted - not sensitive)
    encArgs        // bytes32[] handles
);
```

#### Step 4: Submit to MockPrivacyHook
```typescript
// Submit with input proof for FHE permissions
await mockHook.submitUEIBlobWithProof(
    ctBlob,
    inputProof,  // Required for FHE.fromExternal()
    deadline
);
```

### 2. On-Chain Processing (Contracts)

#### MockPrivacyHook.sol
- Receives encrypted blob from frontend
- Forwards to SwapManager AVS contract
- Acts as authorized hook for submission

#### SwapManager.sol (AVS Contract)
1. **Receives UEI**: `submitUEIWithProof(ctBlob, inputProof, deadline)`
2. **Selects Operators**: Deterministically chooses operators based on intent ID
3. **Grants FHE Permissions**:
   ```solidity
   // Convert external handles to internal FHE types
   eaddress decoder = FHE.fromExternal(encDecoder, inputProof);
   eaddress target = FHE.fromExternal(encTarget, inputProof);
   euint32 selector = FHE.fromExternal(encSelector, inputProof);

   // Grant permissions to selected operators
   for each operator:
       FHE.allow(decoder, operator);
       FHE.allow(target, operator);
       FHE.allow(selector, operator);
   ```
4. **Stores Task**: Creates UEITask with status "Pending"
5. **Emits Event**: `UEISubmittedWithProof` with selected operators

### 3. Operator Decryption & Processing

#### ueiProcessor.ts (Operator Side)
1. **Monitor Events**: Listen for `UEISubmittedWithProof` events
2. **Check Selection**: Verify if operator is selected for the UEI
3. **Read Encrypted Blob**: Get UEI task from contract
4. **Batch Decrypt Components**:
   ```typescript
   // Prepare all handles for batch decryption
   const handleContractPairs = [
       { handle: encDecoder, contractAddress },
       { handle: encTarget, contractAddress },
       { handle: encSelector, contractAddress },
       ...encArgs.map(handle => ({ handle, contractAddress }))
   ];

   // Decrypt with operator's FHE keypair
   const decrypted = await fhevm.userDecrypt(
       handleContractPairs,
       privateKey,
       publicKey,
       signature,
       contractAddresses,
       operatorAddress
   );
   ```

5. **Convert Decrypted Values**:
   - Decoder: `BigInt → Address`
   - Target: `BigInt → Address`
   - Selector: `Number → 0x{8-char-hex}`
   - Arguments: Based on ArgType enum

6. **Reconstruct Calldata**:
   ```typescript
   const calldata = selector + encodedArgs.slice(2);
   ```

### 4. Consensus & Execution

#### Operator Consensus
1. Multiple operators decrypt the same UEI independently
2. Each operator signs the decrypted values
3. Signatures are collected (MIN_ATTESTATIONS required)

#### On-Chain Execution
1. **Submit to SwapManager**: `processUEI(intentId, decoder, target, calldata, signatures)`
2. **Verify Consensus**: Check signatures from selected operators
3. **Execute via BoringVault**:
   ```solidity
   SimpleBoringVault(boringVault).execute(
       target,
       reconstructedData,
       0  // No ETH value
   );
   ```
4. **Update Status**: Mark UEI as Executed/Failed
5. **Emit Result**: `UEIProcessed` event with success status

## Key Components Summary

### Encryption Types
- **Decoder/Target**: `eaddress` (encrypted addresses)
- **Selector**: `euint32` (encrypted 4-byte selector)
- **Arguments**: `euint256[]` (widened for uniformity)
- **Arg Types**: `uint8[]` (unencrypted metadata)

### Security Features
1. **Batch Encryption**: All components encrypted together with shared proof
2. **FHE Permissions**: Explicit grants to selected operators only
3. **Operator Selection**: Deterministic but unpredictable selection
4. **Consensus Required**: Multiple operator attestations for execution
5. **Decoder Validation**: Protocol-specific sanitizers prevent malicious calls

### Integration Points
- **Frontend → MockPrivacyHook**: Submit encrypted intents
- **MockPrivacyHook → SwapManager**: Forward to AVS
- **SwapManager → Operators**: Event-based task distribution
- **Operators → SwapManager**: Submit decrypted consensus
- **SwapManager → BoringVault**: Execute validated trades

## CHANGELOG
- 28-September-2025-10:30PM IST: Initial documentation created with complete UEI flow