// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IVerifier} from "../interfaces/IVerifier.sol";
import {Script, console} from "forge-std/Script.sol";
import {AirdropFactory} from "../src/AirdropFactory.sol";

contract AirdropFactoryScript is Script {
    AirdropFactory public airdropFactory;

    function run() public returns (AirdropFactory) {
        vm.startBroadcast();
        airdropFactory = new AirdropFactory();
        vm.stopBroadcast();

        return airdropFactory;
    }
}
