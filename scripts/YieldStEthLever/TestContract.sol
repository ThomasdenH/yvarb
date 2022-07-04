// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@yield-protocol/vault-v2/FYToken.sol";
import "contracts/YieldStEthLever.sol";
import "forge-std/Test.sol";

contract DeployTest is Test {
    bytes6 constant seriesId = 0x303030370000;
    YieldStEthLever constant lever = YieldStEthLever(0x0Cf17D5DcDA9cF25889cEc9ae5610B0FB9725F65);

    function run() public {
        ERC20 fyWeth = ERC20(0x53358d088d835399F1E97D2a01d79fC925c7D999);

        vm.startBroadcast();
        fyWeth.approve(address(lever), 2e18);
        lever.invest(2e18, 6e18, 0, seriesId);
        vm.stopBroadcast();
    }
}
