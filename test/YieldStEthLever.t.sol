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
import "@yield-protocol/vault-v2/interfaces/ICauldron.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";

abstract contract ZeroState is Test {
    address timeLock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    address fyTokenWhale = 0x1c15b746360BB8E792C6ED8cB83f272Ce1D170E0;
    address ethWhale = 0xDA9dfA130Df4dE4673b89022EE50ff26f6EA73Cf;
    YieldStEthLever lever;
    Protocol protocol;
    Giver giver;

    IPool pool = IPool(0x9D34dF69958675450ab8E53c8Df5531203398Dc9);
    FlashJoin flashJoin = FlashJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0); // weth;
    bytes6 seriesId = 0x303030380000;
    ICauldron cauldron = ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);

    IERC20 constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    WstEth constant wsteth = WstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 constant steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    FYToken constant fyToken =
        FYToken(0x386a0A72FfEeB773381267D69B61aCd1572e074D);

    IStableSwap constant stableSwap =
        IStableSwap(0x828b154032950C8ff7CF8085D841723Db2696056);

    /// @notice The Yield Protocol Join containing WstEth.
    FlashJoin public constant wstethJoin =
        FlashJoin(0x5364d336c2d2391717bD366b29B6F351842D7F82);
    /// @notice The Yield Protocol Join containing Weth.
    FlashJoin public constant wethJoin =
        FlashJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0);

    constructor() {
        protocol = new Protocol();
        giver = Giver(0xa98F3211997FDB072B6a8E2C2A26C34BC447f873);
    }

    function setUp() public virtual {
        vm.createSelectFork("MAINNET", 16082976);

        lever = new YieldStEthLever(giver);
        lever.approveFyToken(seriesId);

        //Label
        vm.label(address(lever), "YieldLever");

        vm.prank(ethWhale);
        address(this).call{value: 1e18}("");
        vm.prank(timeLock);
        giver.grantRole(Giver.seize.selector, address(lever));
    }

    /// Return the available balance in the join.
    function availableBalance(FlashJoin join)
        public
        view
        returns (uint256 available)
    {
        IERC20 token = IERC20(join.asset());
        available = token.balanceOf(address(join)) - join.storedBalance();
    }

    /// @notice Create a vault.
    function invest(uint128 baseAmount, uint128 borrowAmount)
        public
        returns (bytes12 vaultId)
    {
        fyToken.approve(address(lever), baseAmount);
        // Expect at least 80% of the value to end up as collateral
        uint256 wethAmount = pool.sellFYTokenPreview(baseAmount + borrowAmount);
        uint128 minCollateral = uint128(
            (stableSwap.get_dy(0, 1, wethAmount) * 80) / 100
        );

        vaultId = lever.invest{value: baseAmount}(
            seriesId,
            borrowAmount,
            minCollateral
        );
    }
}

abstract contract VaultCreatedState is ZeroState {
    bytes12 vaultId;

    function setUp() public override {
        super.setUp();
        vaultId = invest(1e18, 3.5e18);
    }

    function unwind() internal returns (bytes12) {
        DataTypes.Balances memory balances = cauldron.balances(vaultId);

        // Rough calculation of the minimal amount of weth that we want back.
        // In reality, the debt is not in weth but in fyWeth.
        uint256 collateralValueWeth = stableSwap.get_dy(1, 0, balances.ink);
        uint256 minweth = ((collateralValueWeth - balances.art) * 80) / 100;

        lever.divest(vaultId, seriesId, balances.ink, balances.art, minweth);
        return vaultId;
    }
}

contract ZeroStateTest is ZeroState {
    function testVault() public {
        uint256 availableWStEthBalanceAtStart = availableBalance(wstethJoin);
        uint256 availableWEthBalanceAtStart = availableBalance(wethJoin);

        bytes12 vaultId = invest(1e18, 3.5e18);
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        assertEq(vault.owner, address(this));

        // No tokens should be left in the contract
        assertEq(weth.balanceOf(address(lever)), 0);
        assertEq(wsteth.balanceOf(address(lever)), 0);
        assertEq(steth.balanceOf(address(lever)), 0);
        assertEq(fyToken.balanceOf(address(lever)), 0);

        // Assert that the join state is the same as the start
        assertEq(availableBalance(wstethJoin), availableWStEthBalanceAtStart);
        assertEq(availableBalance(wethJoin), availableWEthBalanceAtStart);
    }

    function testLever() public {
        uint256 availableWStEthBalanceAtStart = availableBalance(wstethJoin);
        uint256 availableWEthBalanceAtStart = availableBalance(wethJoin);

        bytes12 vaultId = invest(1e18, 3.5e18);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        assertEq(balances.art, 3.5e18);

        // No tokens should be left in the contract
        assertEq(weth.balanceOf(address(lever)), 0);
        assertEq(wsteth.balanceOf(address(lever)), 0);
        assertEq(steth.balanceOf(address(lever)), 0);
        assertEq(fyToken.balanceOf(address(lever)), 0);

        // Assert that the join state is the same as the start
        assertEq(availableBalance(wstethJoin), availableWStEthBalanceAtStart);
        assertEq(availableBalance(wethJoin), availableWEthBalanceAtStart);
    }

    /// @notice This function should fail if called externally.
    function testOnFlashLoan() public {
        vm.expectRevert(FlashLoanFailure.selector);
        lever.onFlashLoan(
            address(lever), // Lie!
            address(fyToken),
            1e18,
            1e16,
            bytes.concat(
                bytes1(0x01),
                seriesId,
                bytes12(0),
                bytes16(0),
                bytes16(0)
            )
        );
    }

    function testInvestRevertOnMinEth() public {
        uint128 baseAmount = 4e17;
        uint128 borrowAmount = 8e17;
        fyToken.approve(address(lever), baseAmount);

        // Unreasonable expectation: twice the total value as collateral?
        uint256 wethAmount = pool.sellFYTokenPreview(baseAmount + borrowAmount);
        uint128 minCollateral = uint128(
            stableSwap.get_dy(0, 1, wethAmount) * 2
        );

        vm.expectRevert(SlippageFailure.selector);
        lever.invest{value: baseAmount}(seriesId, borrowAmount, minCollateral);
    }
}

contract VaultCreatedStateTest is VaultCreatedState {
    function testRepay() public {
        uint256 availableWStEthBalanceAtStart = availableBalance(wstethJoin);
        uint256 availableWEthBalanceAtStart = availableBalance(wethJoin);

        unwind();

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

        // Assert that the join state is the same as the start
        assertEq(availableBalance(wstethJoin), availableWStEthBalanceAtStart);
        assertEq(availableBalance(wethJoin), availableWEthBalanceAtStart);
    }

    function testClose() public {
        uint256 availableWStEthBalanceAtStart = availableBalance(wstethJoin);
        uint256 availableWEthBalanceAtStart = availableBalance(wethJoin);

        DataTypes.Series memory series_ = cauldron.series(seriesId);

        vm.warp(series_.maturity);

        unwind();

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

        // Assert that the join state is the same as the start
        assertEq(availableBalance(wstethJoin), availableWStEthBalanceAtStart);
        assertEq(availableBalance(wethJoin), availableWEthBalanceAtStart);
    }

    // function testRepayRevertOnSlippage() public {
    //     DataTypes.Balances memory balances = cauldron.balances(vaultId);

    //     // Rough calculation of the minimal amount of weth that we want back.
    //     // In reality, the debt is not in weth but in fyWeth.
    //     uint256 collateralValueWeth = stableSwap.get_dy(1, 0, balances.ink);
    //     uint256 minweth = (collateralValueWeth - balances.art) * 2;

    //     vm.expectRevert(SlippageFailure.selector);
    //     lever.divest(vaultId, seriesId, balances.ink, balances.art, minweth);
    // }

    function testCloseRevertOnSlippage() public {
        DataTypes.Series memory series_ = cauldron.series(seriesId);
        vm.warp(series_.maturity);

        DataTypes.Balances memory balances = cauldron.balances(vaultId);

        // Rough calculation of the minimal amount of weth that we want back.
        // In reality, the debt is not in weth but in fyWeth.
        uint256 collateralValueWeth = stableSwap.get_dy(1, 0, balances.ink);
        uint256 minweth = (collateralValueWeth - balances.art) * 2;

        vm.expectRevert(SlippageFailure.selector);
        lever.divest(vaultId, seriesId, balances.ink, balances.art, minweth);
    }
}
