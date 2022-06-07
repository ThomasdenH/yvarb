// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// fyeth 0x53358d088d835399F1E97D2a01d79fC925c7D999
contract Protocol is Test {
    constructor() {
        // Labels
        vm.label(
            address(0x828b154032950C8ff7CF8085D841723Db2696056),
            "StableSwap"
        );
        vm.label(address(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A), "Ladle");
        vm.label(
            address(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867),
            "Cauldron"
        );
        vm.label(address(0x5364d336c2d2391717bD366b29B6F351842D7F82), "Join");
        vm.label(
            address(0xA81414a544D0bd8a28257F4038D3D24B08Dd9Bb4),
            "Composite Oracle"
        );
        vm.label(address(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0), "WSTETH");
        vm.label(address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84), "STETH");
        vm.label(
            address(0x93D232213cCA6e5e7105199ABD8590293C3eb106),
            "StETHCONVERTER"
        );
    }
}
