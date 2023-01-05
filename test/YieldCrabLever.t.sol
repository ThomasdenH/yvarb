// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./YieldCrabLeverTestBase.sol";

contract USDCZeroStateTest is ZeroStateTest {
    function setUp() public override {
        base = 25;
        borrow = 10;
        seriesId = usdcSeriesId;
        ilkId = usdcIlkId;
        super.setUp();
    }
}

contract USDCVaultCreatedStateTest is VaultCreatedStateTest {
    function setUp() public override {
        base = 25;
        borrow = 10;
        seriesId = usdcSeriesId;
        ilkId = usdcIlkId;
        super.setUp();
    }
}

contract DAIZeroStateTest is ZeroStateTest {
    function setUp() public override {
        base = 25;
        borrow = 10;
        seriesId = daiSeriesId;
        ilkId = daiIlkId;
        super.setUp();
    }
}

contract DAIVaultCreatedStateTest is VaultCreatedStateTest {
    function setUp() public override {
        base = 25;
        borrow = 10;
        seriesId = daiSeriesId;
        ilkId = daiIlkId;
        super.setUp();
    }
}

contract WETHZeroStateTest is ZeroStateTest {
    function setUp() public override {
        base = 25;
        borrow = 1;
        seriesId = ethSeriesId;
        ilkId = ethIlkId;
        super.setUp();
    }
}

contract WETHVaultCreatedStateTest is VaultCreatedStateTest {
    function setUp() public override {
        base = 25;
        borrow = 1;
        seriesId = ethSeriesId;
        ilkId = ethIlkId;
        super.setUp();
    }
}

contract ETHVaultTest is ZeroState {
    function setUp() public override {
        base = 25;
        borrow = 1;
        seriesId = ethSeriesId;
        ilkId = ethIlkId;
        isEth = true;
        super.setUp();
    }

    function testVault() public {
        bytes12 vaultId = investETH();
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        assertEq(vault.owner, address(this));
        _noTokenLeftBehind();
    }
}
