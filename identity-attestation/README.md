# Sybil Resistance Smart Contract

A robust Clarity smart contract for implementing Sybil resistance mechanisms on the Stacks blockchain.

## Overview

This smart contract provides a comprehensive solution for preventing Sybil attacks in decentralized applications on the Stacks blockchain. A Sybil attack occurs when a malicious actor creates multiple identities to gain disproportionate influence or benefits within a system.

The contract implements multiple defense layers:
- Stake-based verification
- Social proof mechanisms
- Reputation scoring
- Time-based constraints
- Administrative controls

## Features

### Stake-Based Verification
- Users lock STX tokens to establish credibility
- Configurable minimum stake requirement
- Time-locked stakes preventing quick entry/exit attacks
- Stake withdrawal functionality after lock period expires

### Social Verification System
- Users can verify other users' identities
- Verification weight based on verifier's reputation
- Configurable minimum verification threshold
- Cooldown period between verifications to prevent spam
- Protection against self-verification

### Reputation Scoring
- Dynamic reputation calculation combining:
  - Stake amount
  - Number and quality of verifications
  - Account activity and age
- Time-based reputation decay to ensure continued participation
- Maximum score capped at 1000
- Score affects user's influence in the ecosystem

### Blacklisting System
- Administrative blacklisting of known Sybil addresses
- Challenge mechanism for users to report suspected Sybil attacks
- Removal from blacklist functionality

### Administrative Controls
- Configurable verification threshold
- Adjustable minimum stake requirements
- Admin role transfer capability
- System parameter adjustments

## Contract Functions

### Core User Functions

#### `add-stake`
```clarity
(define-public (add-stake (amount uint) (lock-period uint)))
```
Add STX tokens as stake to increase reputation.
- `amount`: Amount of microSTX to stake
- `lock-period`: Number of blocks to lock the stake for

#### `withdraw-stake`
```clarity
(define-public (withdraw-stake (amount uint)))
```
Withdraw staked STX tokens after the lock period expires.
- `amount`: Amount of microSTX to withdraw

#### `verify-user`
```clarity
(define-public (verify-user (user principal)))
```
Verify another user to increase their verification count.
- `user`: Principal of the user to verify

#### `challenge-verification`
```clarity
(define-public (challenge-verification (suspected-sybil principal) (evidence (string-utf8 500))))
```
Challenge a user's verification if a Sybil attack is suspected.
- `suspected-sybil`: Principal of the suspected Sybil attacker
- `evidence`: Description of evidence for the challenge

#### `transfer-stake`
```clarity
(define-public (transfer-stake (to principal) (amount uint)))
```
Transfer stake between users.
- `to`: Principal of the recipient
- `amount`: Amount of microSTX to transfer

### Read-Only Functions

#### `calculate-reputation`
```clarity
(define-read-only (calculate-reputation (user principal)))
```
Calculate a user's reputation score based on stake, verifications, and account activity.
- `user`: Principal of the user

#### `get-reputation`
```clarity
(define-read-only (get-reputation (user principal)))
```
Get a user's current reputation score.
- `user`: Principal of the user

#### `is-sybil-resistant`
```clarity
(define-read-only (is-sybil-resistant (user principal)))
```
Check if a user meets the criteria to be considered Sybil-resistant.
- `user`: Principal of the user

#### `is-blacklisted`
```clarity
(define-read-only (is-blacklisted (address principal)))
```
Check if an address is blacklisted.
- `address`: Principal to check

### Administrative Functions

#### `set-verification-threshold`
```clarity
(define-public (set-verification-threshold (new-threshold uint)))
```
Set the minimum number of verifications required for Sybil resistance.
- `new-threshold`: New verification threshold value

#### `set-min-stake`
```clarity
(define-public (set-min-stake (new-min-stake uint)))
```
Set the minimum stake required for Sybil resistance.
- `new-min-stake`: New minimum stake in microSTX

#### `blacklist-address`
```clarity
(define-public (blacklist-address (address principal) (reason (string-utf8 100))))
```
Blacklist an address suspected of Sybil attack.
- `address`: Principal to blacklist
- `reason`: Reason for blacklisting

#### `remove-from-blacklist`
```clarity
(define-public (remove-from-blacklist (address principal)))
```
Remove an address from the blacklist.
- `address`: Principal to remove from blacklist

#### `set-admin`
```clarity
(define-public (set-admin (new-admin principal)))
```
Transfer admin privileges to a new address.
- `new-admin`: Principal of the new admin

#### `initialize`
```clarity
(define-public (initialize (new-admin principal)))
```
Initialize the contract, can only be called once during deployment.
- `new-admin`: Principal of the initial admin

## Configuration Parameters

The contract has several configurable parameters:

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `min-stake` | Minimum stake required in microSTX | 1,000,000 microSTX |
| `verification-threshold` | Minimum verifications needed | 3 verifications |
| `cooldown-period` | Blocks between verifications | 144 blocks (~24 hours) |
| `reputation-decay-rate` | Rate at which reputation decays | 10% per day |
| `verification-expiry` | Blocks until verification expires | 4320 blocks (~30 days) |

## Data Structures

### Maps

| Map | Key | Value | Description |
|-----|-----|-------|-------------|
| `user-stakes` | `{ user: principal }` | `{ amount: uint, locked-until: uint }` | Tracks user stake amounts and lock periods |
| `user-verifications` | `{ user: principal }` | `{ count: uint, last-verified: uint }` | Tracks verification counts and timestamps |
| `user-reputation` | `{ user: principal }` | `{ score: uint, last-updated: uint }` | Stores reputation scores and update timestamps |
| `verifications` | `{ verifier: principal, verified: principal }` | `{ timestamp: uint, weight: uint }` | Records individual verifications |
| `blacklisted-addresses` | `{ address: principal }` | `{ blacklisted: bool, reason: (string-utf8 100) }` | Tracks blacklisted addresses |

## Error Codes

| Error Code | Value | Description |
|------------|-------|-------------|
| `ERR-NOT-AUTHORIZED` | u1 | Caller is not authorized to perform this action |
| `ERR-ALREADY-VERIFIED` | u2 | User has already been verified by this verifier |
| `ERR-INSUFFICIENT-STAKE` | u3 | User does not have sufficient stake |
| `ERR-COOLDOWN-ACTIVE` | u4 | Action cannot be performed during cooldown period |
| `ERR-SELF-VERIFICATION` | u5 | User cannot verify themselves |
| `ERR-BLACKLISTED` | u6 | Address is blacklisted |
| `ERR-INVALID-REPUTATION` | u7 | User does not have sufficient reputation |
| `ERR-THRESHOLD-NOT-MET` | u8 | Required threshold not met |

## Implementation Details

### Block Time Access

Since Clarity's `get-block-info?` function doesn't directly expose a `height` property in all versions, this contract uses the `time` property as a timestamp reference for temporal operations:

```
(define-private (get-current-block)
  (unwrap-panic (get-block-info? time u0)))
```

This function provides a consistent way to access the current block information throughout the contract.

### Reputation Calculation

Reputation is calculated using the formula:

```
reputation = get-min(1000, (stake_factor * 30 + verification_factor * 20) * time_factor / 100)
```

Where:
- `stake_factor` = user's stake / minimum stake
- `verification_factor` = verification count * 10
- `time_factor` = 100 - get-min(100, decay_rate * (blocks_since_update / 144))

This ensures that reputation:
1. Scales with stake amount
2. Increases with more verifications
3. Decays over time without activity
4. Has an upper limit of 1000

### Verification Process

When a user verifies another user:
1. Verifier must have minimum stake
2. Verifier cannot be blacklisted
3. User being verified cannot be blacklisted
4. Verifier must wait for cooldown period between verifications
5. Verification weight is based on verifier's reputation
6. User's verification count increases

### Sybil Resistance Criteria

A user is considered Sybil-resistant when:
1. They have at least the minimum required stake
2. They have received the minimum number of verifications
3. At least one verification is recent (within expiry period)
4. They are not blacklisted

## Integration Guide

### Contract Deployment

1. Deploy the contract to the Stacks blockchain
2. Call the `initialize` function to set the admin address
3. Configure parameters as needed for your application

### Frontend Integration

To integrate with a frontend application:

```javascript
// Example of checking if user is Sybil-resistant
async function checkSybilResistance(userAddress) {
  const contractAddress = 'SP...'; // Contract address
  const contractName = 'sybil-resistance';
  
  const result = await callReadOnlyFunction({
    contractAddress,
    contractName,
    functionName: 'is-sybil-resistant',
    functionArgs: [standardPrincipalCV(userAddress)],
    network: 'mainnet', // or 'testnet'
  });
  
  return cvToValue(result);
}

// Example of adding stake
async function addStake(amount, lockPeriod) {
  const contractAddress = 'SP...'; // Contract address
  const contractName = 'sybil-resistance';
  
  const functionArgs = [
    uintCV(amount),
    uintCV(lockPeriod)
  ];
  
  const transaction = await makeContractCall({
    contractAddress,
    contractName,
    functionName: 'add-stake',
    functionArgs,
    senderKey: userPrivateKey,
    network: 'mainnet', // or 'testnet'
  });
  
  return broadcastTransaction(transaction, network);
}
```

## Security Considerations

- **Stake Draining**: The contract prevents users from withdrawing stake before the lock period expires
- **Self-Verification**: Users cannot verify themselves to artificially boost their scores
- **Reputation Decay**: Inactive accounts lose reputation over time
- **Verification Weight**: Verifications from higher reputation users count more
- **Blacklisting**: Malicious users can be blacklisted by admins
- **Minimum Requirements**: Both stake and verification requirements prevent easy Sybil attacks

## Limitations

- Depends on honest majority of verifiers
- Admin privileges could be centralization point (consider implementing DAO governance)
- STX price volatility affects the economic security model