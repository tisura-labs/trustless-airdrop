// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";

import {IVerifier} from "../interfaces/IVerifier.sol";
import {IAirdrop} from "../interfaces/IAirdrop.sol";

import {Airdrop} from "../src/Airdrop.sol";
import {HonkVerifier as OwnershipVerifier} from "../src/Ownership.sol";
import {HonkVerifier as ContributionsVerifier} from "../src/Contributions.sol";

import {MockERC20} from "./mock/MockERC20.sol";

contract AirdropTest is Test, IAirdrop {
    Airdrop airdrop;

    // `Airdrop` contract immutables.
    OwnershipVerifier ownershipVerifier;
    ContributionsVerifier contributionsVerifier;

    uint256 rewardsPerContribution = 1e18;
    uint256 revealTimestamp = block.timestamp + 7 days;
    MockERC20 tisuraERC20;
    address treasury = makeAddr("treasury");

    // `Treasury` contract state.
    uint256 TREASURY_BALANCE = 100e18;
    uint256 TOTAL_AIRDROP_AMOUNT = 50e18;

    // Test roles.
    address claimer = makeAddr("claimer");
    address attacker = makeAddr("attacker");

    function setUp() public {
        bytes32 repoNameHash = keccak256(
            abi.encode(stringToBytes32Array("mono"))
        );
        bytes32 repoOwnerHash = keccak256(
            abi.encode(stringToBytes32Array("tisura-labs"))
        );

        ownershipVerifier = new OwnershipVerifier();
        contributionsVerifier = new ContributionsVerifier();

        tisuraERC20 = new MockERC20(
            "TISURA",
            "TSRA",
            TREASURY_BALANCE,
            treasury
        );

        airdrop = new Airdrop(
            repoNameHash,
            repoOwnerHash,
            IVerifier(address(ownershipVerifier)),
            IVerifier(address(contributionsVerifier)),
            rewardsPerContribution,
            revealTimestamp,
            address(tisuraERC20),
            treasury
        );
    }

    function test__Claim() public {
        (
            bytes memory _ownershipProof,
            bytes32[] memory _ownershipPublicInputs,
            bytes memory _contributionsProof,
            bytes32[] memory _contributionsPublicInputs
        ) = _getValidProof();

        vm.prank(treasury);
        tisuraERC20.approve(address(airdrop), TOTAL_AIRDROP_AMOUNT);

        assert(tisuraERC20.balanceOf(claimer) == 0);

        vm.startPrank(claimer);
        bytes32 commitmentHash = airdrop.getCommitmentHash(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            claimer
        );
        vm.expectEmit();
        emit Committed(claimer, commitmentHash);

        (, bytes32 repoNameHash, bytes32 repoOwnerHash, ) = airdrop
            .getContributionsPublicInputs(_contributionsPublicInputs);

        assert(repoNameHash == airdrop.i_repoNameHash());
        assert(repoOwnerHash == airdrop.i_repoOwnerHash());

        bytes32 nodeIdHash = airdrop.getNodeIdHash(_ownershipPublicInputs);
        assert(!airdrop.wasUsed(nodeIdHash));
        airdrop.initClaim(commitmentHash);

        assert(block.timestamp < revealTimestamp);
        vm.warp(revealTimestamp + 1);

        uint256 amount = airdrop.getReward(_contributionsPublicInputs);
        vm.expectEmit();
        emit Claimed(address(airdrop), claimer, amount);
        assert(!airdrop.wasUsed(nodeIdHash));
        airdrop.finalizeClaim(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            commitmentHash
        );

        vm.stopPrank();
        assert(block.timestamp >= revealTimestamp);
        assert(airdrop.commitments(claimer) == commitmentHash);
        assert(airdrop.wasUsed(nodeIdHash));

        assert(tisuraERC20.balanceOf(claimer) == amount);
    }

    function test__NotEligible_InvalidOwnershipProof() public {
        (
            ,
            bytes32[] memory _ownershipPublicInputs,
            bytes memory _contributionsProof,
            bytes32[] memory _contributionsPublicInputs
        ) = _getValidProof();

        bytes memory ownershipProof_;

        vm.expectRevert(Airdrop__NotIdOwner.selector);
        airdrop.areProofsValid(
            ownershipProof_,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs
        );
    }

    function test__NotEligible_InvalidOwnershipPublicInputs() public {
        (
            bytes memory _ownershipProof,
            ,
            bytes memory _contributionsProof,
            bytes32[] memory _contributionsPublicInputs
        ) = _getValidProof();

        bytes32[] memory ownershipPublicInputs_;

        vm.expectRevert(Airdrop__NotIdOwner.selector);
        airdrop.areProofsValid(
            _ownershipProof,
            ownershipPublicInputs_,
            _contributionsProof,
            _contributionsPublicInputs
        );
    }

    function test__NotEligible_InvalidContributionsProof() public {
        (
            bytes memory _ownershipProof,
            bytes32[] memory _ownershipPublicInputs,
            ,
            bytes32[] memory _contributionsPublicInputs
        ) = _getValidProof();

        bytes memory contributionsProof_;

        vm.expectRevert(Airdrop__NotEnoughContributions.selector);
        airdrop.areProofsValid(
            _ownershipProof,
            _ownershipPublicInputs,
            contributionsProof_,
            _contributionsPublicInputs
        );
    }

    function test__NotEligible_InvalidContributionsPublicInputs() public {
        (
            bytes memory _ownershipProof,
            bytes32[] memory _ownershipPublicInputs,
            bytes memory _contributionsProof,

        ) = _getValidProof();

        bytes32[] memory contributionsPublicInputs_;

        vm.expectRevert(Airdrop__NotEnoughContributions.selector);
        airdrop.areProofsValid(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            contributionsPublicInputs_
        );
    }

    function test__NotEligible_ProofAlreadyUsed() public {
        (
            bytes memory _ownershipProof,
            bytes32[] memory _ownershipPublicInputs,
            bytes memory _contributionsProof,
            bytes32[] memory _contributionsPublicInputs
        ) = _getValidProof();

        bytes32 nodeIdHash = airdrop.getNodeIdHash(_ownershipPublicInputs);
        assert(!airdrop.wasUsed(nodeIdHash));

        vm.prank(treasury);
        tisuraERC20.approve(address(airdrop), TOTAL_AIRDROP_AMOUNT);

        ///@dev We want to prevent proof proofs reuse by using `proofsHash` instead of `commitmentHash`. While commitmentHash includes the msg.sender (which could theoretically prevent reuse), the same honest claimer could call finalizeClaim() multiple times with identical proofs - allowing them to receive multiple rewards. proofsHash only depends on the proofs themselves, ensuring they can only be used once regardless of who submits them.
        bytes32 commitmentHash = airdrop.getCommitmentHash(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            claimer
        );
        vm.startPrank(claimer);
        airdrop.initClaim(commitmentHash);

        vm.warp(revealTimestamp + 1);

        airdrop.finalizeClaim(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            commitmentHash
        );

        assert(airdrop.wasUsed(nodeIdHash));

        // Try to finalize claim with same commitment hash.
        vm.expectRevert(Airdrop__ProofAlreadyUsed.selector);
        airdrop.finalizeClaim(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            commitmentHash
        );
        vm.stopPrank();
    }

    function test__tooEarlyToClaim() external {
        (
            bytes memory _ownershipProof,
            bytes32[] memory _ownershipPublicInputs,
            bytes memory _contributionsProof,
            bytes32[] memory _contributionsPublicInputs
        ) = _getValidProof();

        vm.prank(treasury);
        tisuraERC20.approve(address(airdrop), TOTAL_AIRDROP_AMOUNT);

        assert(tisuraERC20.balanceOf(claimer) == 0);

        vm.startPrank(claimer);
        bytes32 commitmentHash = airdrop.getCommitmentHash(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            claimer
        );
        airdrop.initClaim(commitmentHash);
        assert(block.timestamp < revealTimestamp);

        vm.expectRevert(Airdrop__TooEarlyToClaim.selector);
        airdrop.finalizeClaim(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            commitmentHash
        );

        vm.warp(revealTimestamp - 1);

        vm.expectRevert(Airdrop__TooEarlyToClaim.selector);
        airdrop.finalizeClaim(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            commitmentHash
        );
        vm.stopPrank();
    }

    function test__AttackerFrontrunInitClaim() external {
        // 1. Claimer inits a claim with a valid proof. Attacker frontruns the claimer's `initClaim` call.
        (
            bytes memory _ownershipProof,
            bytes32[] memory _ownershipPublicInputs,
            bytes memory _contributionsProof,
            bytes32[] memory _contributionsPublicInputs
        ) = _getValidProof();

        vm.prank(treasury);
        tisuraERC20.approve(address(airdrop), TOTAL_AIRDROP_AMOUNT);

        assert(tisuraERC20.balanceOf(claimer) == 0);
        assert(tisuraERC20.balanceOf(attacker) == 0);

        bytes32 commitmentHash = airdrop.getCommitmentHash(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            claimer
        );

        vm.prank(attacker);
        airdrop.initClaim(commitmentHash);

        vm.prank(claimer);
        airdrop.initClaim(commitmentHash);

        vm.warp(revealTimestamp + 1);

        // 2. Attacker finalizes claim, this should revert.
        vm.prank(attacker);
        vm.expectRevert(Airdrop__NotExpectedCommitmentHash.selector);
        airdrop.finalizeClaim(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            commitmentHash
        );

        assert(tisuraERC20.balanceOf(attacker) == 0);

        // 3. Claimer finalizes claim.
        vm.prank(claimer);
        airdrop.finalizeClaim(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            commitmentHash
        );

        assert(tisuraERC20.balanceOf(claimer) > 0);
    }

    function test__AttackerFrontrunEveryInitClaim() external {
        ///@dev Implicitly tested in test__AttackerFrontrunEveryInitClaim, this is a placeholder to serve as a reminder.
        /// 1. Attacker frontruns every initClaim
        /// 2. During reveal phase, attacker tries to finalize every claim to claim an honest claimer tokens
        /// But for their commitment hash to pass the `require(_commitementHash == expectedCommitementHash, Airdrop__NotExpectedCommitmentHash())` check, they will have to recompute the commitment hash with their msg.sender, which is not possible because commit phase is over.
    }

    function test__AttackerFrontrunFinalizeClaimWithInitClaimAndFinalizeClaim()
        external
    {
        // 1. Claimer init a claim.
        (
            bytes memory _ownershipProof,
            bytes32[] memory _ownershipPublicInputs,
            bytes memory _contributionsProof,
            bytes32[] memory _contributionsPublicInputs
        ) = _getValidProof();

        vm.prank(treasury);
        tisuraERC20.approve(address(airdrop), TOTAL_AIRDROP_AMOUNT);

        bytes32 commitmentHash = airdrop.getCommitmentHash(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            claimer
        );

        vm.prank(claimer);
        airdrop.initClaim(commitmentHash);

        vm.warp(revealTimestamp + 1);

        // 2. At this point, the claimer calls `finalizeClaim`, and proof arguments are public in the mempool.
        // Attacker attempt to call `initClaim` with those arguments and `finalizeClaim` in the same tx before claimer can finalize their claim.

        vm.prank(attacker);
        vm.expectRevert(Airdrop__TooLateToCommit.selector);
        airdrop.initClaim(commitmentHash);

        // finalizeClaim will not even be reached by attacker.

        // 3. Claimer finalizes claim.
        vm.prank(claimer);
        airdrop.finalizeClaim(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            commitmentHash
        );

        assert(tisuraERC20.balanceOf(claimer) > 0);
    }

    function test__NotEligible_MaliciousPublicInputs() external {
        ///@dev Are public inputs strongly tied to the proof, let's say I make a proof of 10 contributions with public inputs of 11, would that work ?
    }

    // TODO: Fuzz claim for proofs and public inputs that allow you to:
    // - Claim with the same proof and diff public inputs

    /*
        Helpers.
    */

    function _getValidProof()
        internal
        view
        returns (
            bytes memory ownershipProof,
            bytes32[] memory ownershipPublicInputs,
            bytes memory contributionsProof,
            bytes32[] memory contributionsPublicInputs
        )
    {
        ownershipProof = vm.readFileBinary(
            "../circuits/ownership/target/proof-clean"
        );
        contributionsProof = vm.readFileBinary(
            "../circuits/contributions/target/proof-clean"
        );

        string memory ownershipPublicInputs_ = vm.readFile(
            "../circuits/ownership/target/public-inputs"
        );
        string memory contributionsPublicInputs_ = vm.readFile(
            "../circuits/contributions/target/public-inputs"
        );
        ownershipPublicInputs = _parsePublicInputs(ownershipPublicInputs_);
        contributionsPublicInputs = _parsePublicInputs(
            contributionsPublicInputs_
        );

        assert(
            airdrop.areProofsValid(
                ownershipProof,
                ownershipPublicInputs,
                contributionsProof,
                contributionsPublicInputs
            )
        );
    }

    /// @notice When generating proofs, a `public-inputs` file is generated as well which is needed to verify proofs. This helper function parses `public-inputs` file into `bytes32[]`, which is the format public inputs are supposed to be in.
    function _parsePublicInputs(
        string memory _publicInputs
    ) internal pure returns (bytes32[] memory) {
        bytes memory raw = vm.parseJson(_publicInputs);
        return abi.decode(raw, (bytes32[]));
    }

    function stringToBytes32Array(
        string memory input
    ) public pure returns (bytes32[] memory) {
        bytes memory inputBytes = bytes(input);
        bytes32[] memory result = new bytes32[](inputBytes.length);

        for (uint i = 0; i < inputBytes.length; i++) {
            result[i] = bytes32(uint256(uint8(inputBytes[i])));
        }

        return result;
    }
}
