// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IAirdropFactory {
    event CreatedAirdrop(
        address airdropCreator,
        address token,
        address treasury,
        address indexed airdropAddress,
        address indexed ownershipVerifier,
        address indexed contributionsVerifier
    );
}
