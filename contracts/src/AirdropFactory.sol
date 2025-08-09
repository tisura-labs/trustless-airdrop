// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Airdrop} from "./Airdrop.sol";
import {IVerifier} from "../interfaces/IVerifier.sol";
import {IAirdropFactory} from "../interfaces/IAirdropFactory.sol";

contract AirdropFactory is IAirdropFactory {
    mapping(address airdropInstance => bool) public airdropInstances;

    // NOTE: Who can create an airdrop?
    function createAirdrop(
        bytes32 _repoNameHash,
        bytes32 _repoOwnerHash,
        address _ownershipVerifier,
        address _contributionsVerifier,
        uint256 _rewardsPerContribution,
        uint256 _revealTimestamp,
        address _token,
        address _treasury
    ) external returns (address) {
        // TODO: Improve salt randomness.
        bytes32 salt = keccak256(
            abi.encodePacked(msg.sender, _token, _treasury)
        );
        address airdropAddress = address(
            new Airdrop{salt: salt}(
                _repoNameHash,
                _repoOwnerHash,
                IVerifier(_ownershipVerifier),
                IVerifier(_contributionsVerifier),
                _rewardsPerContribution,
                _revealTimestamp,
                _token,
                _treasury
            )
        );
        airdropInstances[airdropAddress] = true;

        emit CreatedAirdrop(
            msg.sender,
            _token,
            _treasury,
            airdropAddress,
            _ownershipVerifier,
            _contributionsVerifier
        );

        return airdropAddress;
    }

    function isAirdropInstance(
        address airdropAddress
    ) external view returns (bool) {
        return airdropInstances[airdropAddress];
    }
}
