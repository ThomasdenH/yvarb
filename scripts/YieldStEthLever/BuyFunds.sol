// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
pragma abicoder v2;

import "@yield-protocol/vault-v2/FYToken.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "contracts/YieldStEthLever.sol";
import "forge-std/Test.sol";

interface Weth is IERC20 {
    function deposit() external payable;
    function withdraw(uint wad) external;
}

contract BuyFunds is Test {
    Weth constant weth = Weth(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IPool constant pool = IPool(0xc3348D8449d13C364479B1F114bcf5B73DFc0dc6);

    address constant sender = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function run() public {
        vm.startBroadcast(sender);
        // Get Weth
        weth.deposit{ value: 200e18 }();
        // Get FYWeth
        weth.transfer(address(pool), 100e18);
        pool.buyFYToken(sender, 1e16, 2e16);
        console.log(pool.fyToken().balanceOf(sender));
        vm.stopBroadcast();
    }
}
