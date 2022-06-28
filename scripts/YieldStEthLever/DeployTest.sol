// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@yield-protocol/vault-v2/FYToken.sol";
import "contracts/YieldStEthLever.sol";
import "forge-std/Test.sol";

contract DeployTest is Test {
    address constant timeLock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    FYToken constant fyToken =
        FYToken(0x53358d088d835399F1E97D2a01d79fC925c7D999);
    ICauldron constant cauldron =
        ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    AccessControl constant cauldronAccessControl = AccessControl(address(cauldron));
    FlashJoin constant flashJoin = FlashJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0);
    bytes6 seriesId = 0x303030370000;

    Giver giver;
    YieldStEthLever lever;

    function run() public {
        // Deploy the giver contract
        vm.broadcast();
        giver = new Giver(cauldron);

        // Deploy the contract
        vm.broadcast();
        lever = new YieldStEthLever(giver);
        lever.approveFyToken(seriesId);
    }
}
