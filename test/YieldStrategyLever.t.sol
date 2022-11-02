// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Tests} from "./YieldStrategyLeverTestBase.sol";

contract DAILeverTest is Tests {
    function setUp() public override {
        seriesId = seriesIdDAI;
        strategyIlkId = strategyIlkIdDAI;
        baseAmount = 2000e18;
        borrowAmount = 1000e18;
        fyTokenToBuy = 333333333333333333333;
        super.setUp();
    }
}

contract USDCLeverTest is Tests {
    function setUp() public override {
        seriesId = seriesIdUSDC;
        strategyIlkId = strategyIlkIdUSDC;
        baseAmount = 2000e6;
        borrowAmount = 1000e6;
        fyTokenToBuy = 333333333333333333333;
        super.setUp();
    }
}

// contract ETHLeverTest is Tests {
//     function setUp() public override {
//         seriesId = seriesIdETH;
//         strategyIlkId = strategyIlkIdETH;
//         baseAmount = 20000e18;
//         borrowAmount = 5000e18;
//         fyTokenToBuy = 333333333333333333333;
//         super.setUp();
//     }
// }
