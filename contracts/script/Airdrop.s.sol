// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IVerifier} from "../interfaces/IVerifier.sol";
import {Script, console} from "forge-std/Script.sol";
import {Airdrop} from "../src/Airdrop.sol";

contract AirdropScript is Script {
    Airdrop public airdrop;
    bytes32 repoNameHash = keccak256(abi.encode(bytes("mono")));
    bytes32 repoOwnerHash = keccak256(abi.encode(bytes("tisura-labs")));

    // On Sepolia Base.
    IVerifier ownershipVerifier =
        IVerifier(0x0273DA56EF0915dB5496D1Dc00AEBe0211D5cA36);
    IVerifier contributionsVerifier =
        IVerifier(0x4B8463D79bd8702F71b42a0ADa8048e32D01B443);
    uint256 rewardsPerContribution = 1e18;
    uint256 revealTimestamp = block.timestamp + 7 days;

    function setUp() public {}

    function run() public returns (Airdrop) {
        vm.createSelectFork("base-sepolia");
        vm.startBroadcast();
        new Airdrop(
            repoNameHash,
            repoOwnerHash,
            ownershipVerifier,
            contributionsVerifier,
            rewardsPerContribution,
            revealTimestamp,
            address(0),
            address(0)
        );
        vm.stopBroadcast();

        return airdrop;
    }
}
