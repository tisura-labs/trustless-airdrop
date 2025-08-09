// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IVerifier} from "../interfaces/IVerifier.sol";
import {IAirdrop} from "../interfaces/IAirdrop.sol";

import {IERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract Airdrop is IAirdrop {
    bytes32 public immutable i_repoNameHash;
    bytes32 public immutable i_repoOwnerHash;

    IVerifier immutable ownershipVerifier;
    IVerifier immutable contributionsVerifier;

    uint256 immutable rewardsPerContribution;
    uint256 immutable revealTimestamp;
    IERC20 immutable token;
    address immutable treasury;

    // Storage.
    mapping(address prover => bytes32 commitmentHash) public commitments;
    mapping(bytes32 nodeIdHash => bool) public wasUsed;

    using SafeERC20 for IERC20;

    constructor(
        bytes32 _repoNameHash,
        bytes32 _repoOwnerHash,
        IVerifier _ownershipVerifier,
        IVerifier _contributionsVerifier,
        uint256 _rewardsPerContribution,
        uint256 _revealTimestamp,
        address _token,
        address _treasury
    ) {
        i_repoNameHash = _repoNameHash;
        i_repoOwnerHash = _repoOwnerHash;
        ownershipVerifier = _ownershipVerifier;
        contributionsVerifier = _contributionsVerifier;
        rewardsPerContribution = _rewardsPerContribution;
        if (_revealTimestamp <= block.timestamp) {
            revert Airdrop__InvalidRevealTimestamp();
        }
        revealTimestamp = _revealTimestamp;
        token = IERC20(_token);
        treasury = _treasury;
    }

    function initClaim(bytes32 _commitmentHash) external {
        if (block.timestamp >= revealTimestamp) {
            revert Airdrop__TooLateToCommit();
        }
        commitments[msg.sender] = _commitmentHash;
        emit Committed(msg.sender, _commitmentHash);
    }

    function finalizeClaim(
        bytes calldata _ownershipProof,
        bytes32[] calldata _ownershipPublicInputs,
        bytes calldata _contributionsProof,
        bytes32[] calldata _contributionsPublicInputs,
        bytes32 _commitmentHash
    ) external {
        _verifyProofs(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs
        );

        (
            ,
            bytes32 repoNameHash,
            bytes32 repoOwnerHash,

        ) = getContributionsPublicInputs(_contributionsPublicInputs);
        if (i_repoNameHash != repoNameHash) {
            revert Airdrop__NotRepoName();
        }
        if (i_repoOwnerHash != repoOwnerHash) {
            revert Airdrop__NotRepoOwner();
        }

        if (block.timestamp < revealTimestamp) {
            revert Airdrop__TooEarlyToClaim();
        }

        if (commitments[msg.sender] != _commitmentHash) {
            revert Airdrop__NotCommitter();
        }

        bytes32 expectedCommitmentHash = getCommitmentHash(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs,
            msg.sender
        );
        if (_commitmentHash != expectedCommitmentHash) {
            revert Airdrop__NotExpectedCommitmentHash();
        }

        bytes32 nodeIdHash = getNodeIdHash(_ownershipPublicInputs);

        // DEV: Is Noir proof always the same for the same inputs?
        if (wasUsed[nodeIdHash]) {
            revert Airdrop__ProofAlreadyUsed();
        }
        wasUsed[nodeIdHash] = true;

        uint256 amount = _calculateReward(_contributionsPublicInputs);

        ///@dev At this point, `treasury` is assumed to approve at least `amount` of tokens to the `Airdrop` instance.
        token.safeTransferFrom(treasury, msg.sender, amount);

        emit Claimed(address(this), msg.sender, amount);
    }

    function _verifyProofs(
        bytes calldata _ownershipProof,
        bytes32[] calldata _ownershipPublicInputs,
        bytes calldata _contributionsProof,
        bytes32[] calldata _contributionsPublicInputs
    ) internal view {
        try
            ownershipVerifier.verify(_ownershipProof, _ownershipPublicInputs)
        {} catch {
            revert Airdrop__NotIdOwner();
        }

        try
            contributionsVerifier.verify(
                _contributionsProof,
                _contributionsPublicInputs
            )
        {} catch {
            revert Airdrop__NotEnoughContributions();
        }
    }

    function _calculateReward(
        bytes32[] calldata _contributionsPublicInputs
    ) internal view returns (uint256) {
        // NOTE: Must be validated, currently we directly trust the user input. Double check it's not already done at `verifier.verify()` level.
        (, , , uint256 contributionsCount) = getContributionsPublicInputs(
            _contributionsPublicInputs
        );
        return contributionsCount * rewardsPerContribution;
    }

    /*
     Getters.
    */

    function getCommitmentHash(
        bytes calldata _ownershipProof,
        bytes32[] calldata _ownershipPublicInputs,
        bytes calldata _contributionsProof,
        bytes32[] calldata _contributionsPublicInputs,
        address _prover
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _ownershipProof,
                    _ownershipPublicInputs,
                    _contributionsProof,
                    _contributionsPublicInputs,
                    _prover
                )
            );
    }

    function getContributionsPublicInputs(
        bytes32[] calldata _contributionsPublicInputs
    )
        public
        pure
        returns (
            bytes32 ciphertextHash,
            bytes32 repoNameHash,
            bytes32 repoOwnerHash,
            uint256 count
        )
    {
        // _contributionsPublicInputs layout:
        //
        // +---------------------------------+-------------------------------------------+-------------+
        // | Name                            | Value                                     | Length      |
        // +---------------------------------+-------------------------------------------+-------------+
        // | ciphertext                      | [byte0, byte1, ..., byteMAX]              | MAX         |
        // | ciphertext_len                  | MAX                                       | 1           |
        // | expected_repository_name        | [byte0, byte1, ..., byteX, 0,  ..., 0]    | MAX_REPO    |
        // | expected_repository_name_len    | x                                         | 1           |
        // | expected_repository_owner       | [byte0, byte1, ..., byteY, 0,  ..., 0]    | MAX_REPO    |
        // | expected_repository_owner_len   | y                                         | 1           |
        // | count                           | z                                         | 1           |
        // +---------------------------------+-------------------------------------------+-------------+
        // Where MAX is ciphertext/plaintext max length in circuits (200), and MAX_REPO is max repo name
        // and repo owner in circuits (20).

        // Position calculations:
        // [positions 0 to 199, length 200]     : Ciphertext
        // [position 200, length 1]             : Length of Ciphertext
        // [positions 201 to 220, length 20]    : Repository Name
        // [position 221, length 1]             : Repository Name Length
        // [positions 222 to 241, length 20]    : Repository Owner
        // [position 242, length 1]             : Repository Owner Length
        // [position 243, length 1]             : Count of contributions

        // Repository Name
        uint256 repoNameStartIndex = 201;
        uint256 repoNameLength = uint256(_contributionsPublicInputs[221]);
        bytes32[]
            memory repoName = _contributionsPublicInputs[repoNameStartIndex:repoNameStartIndex +
                repoNameLength];

        // Repository Owner
        uint256 repoOwnerStartIndex = 222;
        uint256 repoOwnerLength = uint256(_contributionsPublicInputs[242]);
        bytes32[]
            memory repoOwner = _contributionsPublicInputs[repoOwnerStartIndex:repoOwnerStartIndex +
                repoOwnerLength];

        // Count
        count = uint256(_contributionsPublicInputs[243]);

        return (
            bytes32(0), // Not needed for now.
            keccak256(abi.encode(repoName)),
            keccak256(abi.encode(repoOwner)),
            count
        );
    }

    function getNodeIdHash(
        bytes32[] calldata _ownershipPublicInputs
    ) public pure returns (bytes32) {
        uint256 length = _ownershipPublicInputs.length;
        ///@dev nodeId is of length 12.
        return
            keccak256(
                abi.encode(_ownershipPublicInputs[length - 14:length - 1])
            );
    }

    function areProofsValid(
        bytes calldata _ownershipProof,
        bytes32[] calldata _ownershipPublicInputs,
        bytes calldata _contributionsProof,
        bytes32[] calldata _contributionsPublicInputs
    ) external view returns (bool) {
        _verifyProofs(
            _ownershipProof,
            _ownershipPublicInputs,
            _contributionsProof,
            _contributionsPublicInputs
        );

        return true;
    }

    function getReward(
        bytes32[] calldata _contributionsPublicInputs
    ) external view returns (uint256) {
        return _calculateReward(_contributionsPublicInputs);
    }

    function getOwnershipVerifier() external view returns (address) {
        return address(ownershipVerifier);
    }

    function getContributionsVerifier() external view returns (address) {
        return address(contributionsVerifier);
    }
}
