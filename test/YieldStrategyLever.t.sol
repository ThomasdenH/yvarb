// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {InvestedState, InvestedMatureState} from "./YieldStrategyLeverTestBase.sol";

contract DAILeverInvestedStateTest is InvestedState {
    function setUp() public override {
        seriesId = seriesIdDAI;
        strategyIlkId = strategyIlkIdDAI;
        baseAmount = 10000e18;
        borrowAmount = 1000e18;
        fyTokenToBuy = baseAmount / 2;
        super.setUp();
    }
}

contract USDCLeverInvestedStateTest is InvestedState {
    function setUp() public override {
        seriesId = seriesIdUSDC;
        strategyIlkId = strategyIlkIdUSDC;
        baseAmount = 2000e6;
        borrowAmount = 1000e6;
        fyTokenToBuy = baseAmount / 3;
        super.setUp();
    }
}

contract ETHLeverInvestedStateTest is InvestedState {
    function setUp() public override {
        seriesId = seriesIdETH;
        strategyIlkId = strategyIlkIdETH;
        baseAmount = 8e18;
        borrowAmount = 1e18;
        fyTokenToBuy = 1e18;
        super.setUp();
    }
}

contract DAILeverInvestedMatureStateTest is InvestedMatureState {
    function setUp() public override {
        seriesId = seriesIdDAI;
        strategyIlkId = strategyIlkIdDAI;
        baseAmount = 10000e18;
        borrowAmount = 1000e18;
        fyTokenToBuy = baseAmount / 2;
        super.setUp();
    }
}

contract USDCLeverInvestedMatureStateTest is InvestedMatureState {
    function setUp() public override {
        seriesId = seriesIdUSDC;
        strategyIlkId = strategyIlkIdUSDC;
        baseAmount = 2000e6;
        borrowAmount = 1000e6;
        fyTokenToBuy = baseAmount / 3;
        super.setUp();
    }
}

contract ETHLeverInvestedMatureStateTest is InvestedMatureState {
    function setUp() public override {
        seriesId = seriesIdETH;
        strategyIlkId = strategyIlkIdETH;
        baseAmount = 8e18;
        borrowAmount = 1e18;
        fyTokenToBuy = 1e18;
        super.setUp();
    }
}
