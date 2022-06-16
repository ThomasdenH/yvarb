// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/YieldStEthLever.sol";
import "contracts/interfaces/IStableSwap.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/vault-v2/FYToken.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "./Protocol.sol";
import "@yield-protocol/vault-v2/utils/Giver.sol";
import "@yield-protocol/vault-v2/FlashJoin.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";

contract YieldStEthLeverTest is Test {
    address timeLock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    address fyTokenWhale = 0x1c15b746360BB8E792C6ED8cB83f272Ce1D170E0;
    YieldStEthLever lever;
    Protocol protocol;
    Giver giver;

    IPool pool = IPool(0xc3348D8449d13C364479B1F114bcf5B73DFc0dc6);
    FlashJoin flashJoin;
    bytes6 seriesId = 0x303030370000;
    ICauldron cauldron;

    
    IERC20 constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    WstEth constant wsteth = WstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 constant steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    FYToken immutable fyToken;

    IStableSwap constant stableSwap =
        IStableSwap(0x828b154032950C8ff7CF8085D841723Db2696056);

    constructor() {
        protocol = new Protocol();
        fyToken = FYToken(0x53358d088d835399F1E97D2a01d79fC925c7D999);
        flashJoin = FlashJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0); // weth
        cauldron = ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);

        // Set the flash fee factor
        vm.prank(timeLock);
        fyToken.setFlashFeeFactor(1);

        vm.prank(timeLock);
        flashJoin.setFlashFeeFactor(1);

        giver = new Giver(cauldron);
        // Orchestrate Giver
        AccessControl cauldronAccessControl = AccessControl(
            0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867
        );
        vm.prank(timeLock);
        cauldronAccessControl.grantRole(0x798a828b, address(giver));
    }

    function setUp() public {
        lever = new YieldStEthLever(
            FYToken(0x53358d088d835399F1E97D2a01d79fC925c7D999),
            giver
        );

        //Label
        vm.label(address(lever), "YieldLever");

        vm.prank(fyTokenWhale);
        fyToken.transfer(address(this), 2e18);
        // vm.prank(fyTokenWhale);
        // fyToken.transfer(address(lever), 3e18);
        AccessControl giverAccessControl = AccessControl(address(giver));
        giverAccessControl.grantRole(0xe4fd9dc5, timeLock);
        giverAccessControl.grantRole(0x35775afb, address(lever));
    }

    function leverUp(uint128 baseAmount, uint128 borrowAmount)
        public
        returns (bytes12 vaultId)
    {
        fyToken.approve(address(lever), baseAmount);
        // Expect at least 80% of the value to end up as collateral
        uint256 wethAmount = pool.sellFYTokenPreview(baseAmount + borrowAmount);
        uint128 minCollateral = uint128(stableSwap.get_dy(0, 1, wethAmount) * 80 / 100);
        vaultId = lever.invest(baseAmount, borrowAmount, minCollateral, seriesId);
    }

    function unwind(bytes12 vaultId) public returns (bytes12) {
        DataTypes.Balances memory balances = cauldron.balances(vaultId);

        // Rough calculation of the minimal amount of weth that we want back.
        // In reality, the debt is not in weth but in fyWeth.
        uint256 collateralValueWeth = stableSwap.get_dy(1, 0, balances.ink);
        uint256 minweth = (collateralValueWeth - balances.art) * 80 / 100;

        lever.unwind(
            balances.ink,
            balances.art,
            minweth,
            vaultId,
            seriesId
        );
        return vaultId;
    }

    function testVault() public {
        bytes12 vaultId = leverUp(2e18, 6e18);
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        assertEq(vault.owner, address(this));

        // No tokens should be left in the contract
        assertEq(weth.balanceOf(address(lever)), 0);
        assertEq(wsteth.balanceOf(address(lever)), 0);
        assertEq(steth.balanceOf(address(lever)), 0);
        assertEq(fyToken.balanceOf(address(lever)), 0);
    }

    function testLever() public {
        bytes12 vaultId = leverUp(2e18, 5e18);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        assertEq(balances.art, 5e18);

        // No tokens should be left in the contract
        assertEq(weth.balanceOf(address(lever)), 0);
        assertEq(wsteth.balanceOf(address(lever)), 0);
        assertEq(steth.balanceOf(address(lever)), 0);
        assertEq(fyToken.balanceOf(address(lever)), 0);
    }

    function testLoanAndRepay() public {
        bytes12 vaultId = leverUp(2e18, 4e18);
        unwind(vaultId);

        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        assertEq(balances.art, 0);
        assertEq(balances.ink, 0);

        // A very weak condition, but we should have at least some weth back.
        assertGt(weth.balanceOf(address(this)), 0);

        // No tokens should be left in the contract
        assertEq(weth.balanceOf(address(lever)), 0);
        assertEq(wsteth.balanceOf(address(lever)), 0);
        assertEq(steth.balanceOf(address(lever)), 0);
        assertEq(fyToken.balanceOf(address(lever)), 0);
    }

    function testLoanAndClose() public {
        bytes12 vaultId = leverUp(2e18, 4e18);

        DataTypes.Series memory series_ = cauldron.series(seriesId);

        vm.warp(series_.maturity);

        unwind(vaultId);

        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        assertEq(balances.art, 0);
        assertEq(balances.ink, 0);

        // A very weak condition, but we should have at least some weth back.
        assertGt(weth.balanceOf(address(this)), 0);

        // No tokens should be left in the contract
        assertEq(weth.balanceOf(address(lever)), 0);
        assertEq(wsteth.balanceOf(address(lever)), 0);
        assertEq(steth.balanceOf(address(lever)), 0);
        assertEq(fyToken.balanceOf(address(lever)), 0);
    }
}
