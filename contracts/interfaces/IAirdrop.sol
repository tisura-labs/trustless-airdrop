// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IAirdrop {
    event Committed(address from, bytes32 commitementHash);
    event Claimed(address from, address to, uint256 amount);

    error Airdrop__TooEarlyToClaim();
    error Airdrop__InvalidRevealTimestamp();
    error Airdrop__NotCommitter();
    error Airdrop__NotExpectedCommitmentHash();
    error Airdrop__TooLateToCommit();
    error Airdrop__NotIdOwner();
    error Airdrop__NotEnoughContributions();
    error Airdrop__ProofAlreadyUsed();
    error Airdrop__NotEnoughAllowance();
    error Airdrop__NotRepoName();
    error Airdrop__NotRepoOwner();
}
