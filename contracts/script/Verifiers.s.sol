// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {HonkVerifier as OwnershipVerifier} from "../src/Ownership.sol";
import {HonkVerifier as ContributionsVerifier} from "../src/Contributions.sol";

contract VerifiersScript is Script {
    function setUp() public {}

    function run() public {
        // Available forks: sepolia, base-sepolia
        vm.createSelectFork("base-sepolia");
        vm.startBroadcast();
        new OwnershipVerifier();
        new ContributionsVerifier();
        vm.stopBroadcast();
    }
}
