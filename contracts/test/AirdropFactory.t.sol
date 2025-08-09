// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";

import {AirdropFactory} from "../src/AirdropFactory.sol";
import {Airdrop} from "../src/Airdrop.sol";

import {IAirdropFactory} from "../interfaces/IAirdropFactory.sol";
import {IVerifier} from "../interfaces/IVerifier.sol";

import {HonkVerifier as OwnershipVerifier} from "../src/Ownership.sol";
import {HonkVerifier as ContributionsVerifier} from "../src/Contributions.sol";

import {MockERC20} from "./mock/MockERC20.sol";

contract AirdropFactoryTest is Test {
    // `Treasury` contract state.
    uint256 TREASURY_BALANCE = 100e18;
    uint256 TOTAL_AIRDROP_AMOUNT = 50e18;

    AirdropFactory factory;
    bytes32 repoNameHash = keccak256(abi.encode(bytes("nhpc")));
    bytes32 repoOwnerHash = keccak256(abi.encode(bytes("achab")));
    OwnershipVerifier ownershipVerifier;
    ContributionsVerifier contributionsVerifier;

    uint256 rewardsPerContribution = 1e18;
    uint256 revealTimestamp = block.timestamp + 7 days;

    address alice = makeAddr("alice"); // Should impersonate Airdrop creator #1
    address bob = makeAddr("bob"); // Should impersonate Airdrop creator #2
    address charlie = makeAddr("charlie"); // Should impersonate Airdrop creator #3

    address treasuryWalletAlice = makeAddr("treasuryWalletAlice");
    address treasuryWalletBob = makeAddr("treasuryWalletBob");
    address treasuryWalletCharlie = makeAddr("treasuryWalletCharlie");

    MockERC20 mockAirdropTokenAlice;
    MockERC20 mockAirdropTokenBob;
    MockERC20 mockAirdropTokenCharlie;

    function setUp() public {
        // Deploy verifiers
        ownershipVerifier = new OwnershipVerifier();
        contributionsVerifier = new ContributionsVerifier();

        // Deploy factory
        factory = new AirdropFactory();

        // Deploy mock tokens
        mockAirdropTokenAlice = new MockERC20(
            "MockAirdropTokenAlice",
            "MTA",
            TREASURY_BALANCE,
            treasuryWalletAlice
        );

        mockAirdropTokenBob = new MockERC20(
            "MockAirdropTokenBob",
            "MTB",
            TREASURY_BALANCE,
            treasuryWalletBob
        );

        mockAirdropTokenCharlie = new MockERC20(
            "MockAirdropTokenCharlie",
            "MTC",
            TREASURY_BALANCE,
            treasuryWalletCharlie
        );
    }

    function test_FullAirdropCreationFlow() public {
        // 1. Alice creates an airdrop
        vm.prank(alice);
        address aliceAirdrop = factory.createAirdrop(
            repoNameHash,
            repoOwnerHash,
            address(ownershipVerifier),
            address(contributionsVerifier),
            rewardsPerContribution,
            revealTimestamp,
            address(mockAirdropTokenAlice),
            treasuryWalletAlice
        );

        // 2. Bob creates an airdrop
        vm.prank(bob);
        address bobAirdrop = factory.createAirdrop(
            repoNameHash,
            repoOwnerHash,
            address(ownershipVerifier),
            address(contributionsVerifier),
            rewardsPerContribution,
            revealTimestamp,
            address(mockAirdropTokenBob),
            treasuryWalletBob
        );

        // 3. Charlie creates an airdrop
        vm.prank(charlie);
        address charlieAirdrop = factory.createAirdrop(
            repoNameHash,
            repoOwnerHash,
            address(ownershipVerifier),
            address(contributionsVerifier),
            rewardsPerContribution,
            revealTimestamp,
            address(mockAirdropTokenCharlie),
            treasuryWalletCharlie
        );

        // 4. Verify that the airdrop instances are created correctly
        assertEq(factory.isAirdropInstance(aliceAirdrop), true);
        assertEq(factory.isAirdropInstance(bobAirdrop), true);
        assertEq(factory.isAirdropInstance(charlieAirdrop), true);

        // 5. Verify that airdrop instances are initialized correctly
        assert(
            Airdrop(aliceAirdrop).getOwnershipVerifier() ==
                address(ownershipVerifier)
        );
        assert(
            Airdrop(aliceAirdrop).getContributionsVerifier() ==
                address(contributionsVerifier)
        );

        assert(
            Airdrop(bobAirdrop).getOwnershipVerifier() ==
                address(ownershipVerifier)
        );
        assert(
            Airdrop(bobAirdrop).getContributionsVerifier() ==
                address(contributionsVerifier)
        );

        assert(
            Airdrop(charlieAirdrop).getOwnershipVerifier() ==
                address(ownershipVerifier)
        );
        assert(
            Airdrop(charlieAirdrop).getContributionsVerifier() ==
                address(contributionsVerifier)
        );
    }
}
