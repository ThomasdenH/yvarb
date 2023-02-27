// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/YieldStrategyLever.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";
import "@yield-protocol/vault-v2/src/FYToken.sol";
import "@yield-protocol/vault-v2/src/utils/Giver.sol";
import "@yield-protocol/vault-v2/src/FlashJoin.sol";
import "@yield-protocol/vault-v2/src/interfaces/ICauldron.sol";
import "@yield-protocol/vault-v2/src/interfaces/ILadle.sol";
import "@yield-protocol/utils-v2/src/token/IERC20.sol";
import "@yield-protocol/utils-v2/src/access/AccessControl.sol";

abstract contract ZeroState is Test {
    address timeLock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    address daiWhale = 0x9A315BdF513367C0377FB36545857d12e85813Ef;
    address usdcWhale = 0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2;
    address wethWhale = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    address daiWhale2 = 0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8;
    address usdcWhale2 = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
    address wethWhale2 = 0x2F0b23f53734252Bda2277357e97e1517d6B042A;

    IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ICauldron constant cauldron =
        ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    ILadle constant ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    FlashJoin constant daiJoin =
        FlashJoin(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc); // dai
    FlashJoin constant usdcJoin =
        FlashJoin(0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4); // usdc
    FlashJoin constant wethJoin =
        FlashJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0); // weth

    bytes6 constant seriesIdDAI = 0x303130380000;
    bytes6 constant seriesIdUSDC = 0x303230380000;
    bytes6 constant seriesIdETH = 0x303030380000;
    bytes6 constant strategyIlkIdDAI = 0x333100000000;
    bytes6 constant strategyIlkIdUSDC = 0x333300000000;
    bytes6 constant strategyIlkIdETH = 0x333500000000;

    Giver giver;
    YieldStrategyLever lever;

    bytes6 seriesId;
    bytes6 strategyIlkId;
    bytes12 vaultId;
    address strategyTokenAddress;
    uint256 baseAmount;
    uint256 borrowAmount;
    uint256 fyTokenToBuy;
    uint256 initialBalance;
    uint256 initialUserBalance;
    uint256 finalUserBalance;
    uint128 buyFor;
    uint128 sellFor;

    mapping(bytes6 => address) whaleMapping;
    mapping(bytes6 => address) whaleMapping2;

    constructor() {
        giver = Giver(0xa98F3211997FDB072B6a8E2C2A26C34BC447f873);

        vm.label(address(wethJoin), "weth Join");
        vm.label(address(daiJoin), "dai Join");
        vm.label(address(usdcJoin), "usdc Join");

        whaleMapping[strategyIlkIdDAI] = daiWhale;
        whaleMapping[strategyIlkIdUSDC] = usdcWhale;
        whaleMapping[strategyIlkIdETH] = wethWhale;

        whaleMapping2[strategyIlkIdDAI] = daiWhale2;
        whaleMapping2[strategyIlkIdUSDC] = usdcWhale2;
        whaleMapping2[strategyIlkIdETH] = wethWhale2;
    }

    function setUp() public virtual {
        vm.createSelectFork("MAINNET", 16082976);
        vm.label(address(ladle.pools(seriesId)), "Pool");
        // Orchestrate Giver
        AccessControl cauldronAccessControl = AccessControl(
            0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867
        );
        vm.prank(timeLock);
        cauldronAccessControl.grantRole(0x798a828b, address(giver));
        vm.prank(daiWhale);
        DAI.transfer(address(this), 100000e18);
        vm.prank(usdcWhale);
        USDC.transfer(address(this), 100000e6);
        vm.prank(wethWhale);
        WETH.transfer(address(this), 100000e18);

        IPool pool = IPool(ladle.pools(seriesId));
        FYToken fyToken = FYToken(address(pool.fyToken()));
        vm.label(address(fyToken), fyToken.symbol());
        vm.label(address(pool.base()), pool.baseToken().symbol());
        vm.label(address(pool), "Pool");
        vm.prank(timeLock);
        fyToken.setFlashFeeFactor(0);

        lever = new YieldStrategyLever(giver);

        DAI.approve(address(lever), type(uint256).max);
        USDC.approve(address(lever), type(uint256).max);
        WETH.approve(address(lever), type(uint256).max);

        vm.prank(timeLock);
        giver.grantRole(Giver.seize.selector, address(lever));

        initialBalance = IPool(ladle.pools(seriesId)).base().balanceOf(
            address(ladle.pools(seriesId))
        );
        // console.log(initialBalance);
        initialUserBalance = IPool(ladle.pools(seriesId)).base().balanceOf(
            address(this)
        );

        vaultId = invest();
    }

    // --------------------------Utility Functions---------------------------- //
    /// @notice Create a vault.
    function invest() public returns (bytes12) {
        vaultId = lever.invest(
            YieldStrategyLever.Operation.BORROW,
            seriesId,
            strategyIlkId, // ilkId edai
            baseAmount,
            borrowAmount,
            fyTokenToBuy,
            0 //minCollateral,
        );
        return vaultId;
    }

    function sellBaseFor() public {
        vm.startPrank(whaleMapping2[strategyIlkId]);
        IPool pool = IPool(ladle.pools(seriesId));
        pool.base().transfer(address(pool), sellFor);
        pool.sellBase(whaleMapping2[strategyIlkId], 0);
        vm.stopPrank();
    }

    function sellFyTokenFor() public {
        vm.startPrank(whaleMapping2[strategyIlkId]);
        IPool pool = IPool(ladle.pools(seriesId));
        uint128 baseInAmount = uint128(
            pool.fyToken().balanceOf(whaleMapping2[strategyIlkId])
        );
        pool.base().transfer(address(pool), baseInAmount);
        pool.sellFYToken(whaleMapping2[strategyIlkId], 0);
        vm.stopPrank();
    }

    // --------------------------Tests---------------------------- //
    /// @notice Test if vault is created correctly
    function testBorrow() public {
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        address strategyAddress = cauldron.assets(strategyIlkId);
        assertEq(vault.owner, address(this));
        assertEq(cauldron.balances(vaultId).art, borrowAmount);
        assertGt(cauldron.balances(vaultId).ink, (baseAmount * 55) / 100);
        assertEq(IERC20(strategyAddress).balanceOf(vault.owner), 0);
        // Assert that the balances are empty
        assertEq(
            IPool(ladle.pools(seriesId)).base().balanceOf(address(lever)),
            0
        );
        assertEq(
            IPool(ladle.pools(seriesId)).fyToken().balanceOf(address(lever)),
            0
        );
    }
}

abstract contract InvestedState is ZeroState {
    bytes12 vaultId2;

    function setUp() public virtual override {
        super.setUp();
        sellBaseFor();
        sellFyTokenFor();
    }

    function testBorrowSecondUser() public {
        vm.startPrank(whaleMapping[strategyIlkId]);

        IPool pool = IPool(ladle.pools(seriesId));
        pool.base().approve(address(lever), type(uint256).max);
        bytes12 vaultId2 = lever.invest(
            YieldStrategyLever.Operation.BORROW,
            seriesId,
            strategyIlkId, // ilkId edai
            baseAmount,
            borrowAmount,
            fyTokenToBuy,
            0 //minCollateral,
        );

        vm.stopPrank();

        // Checking if the state of second user's vault remains the same
        DataTypes.Vault memory vault = cauldron.vaults(vaultId2);
        address strategyAddress = cauldron.assets(strategyIlkId);

        assertEq(vault.owner, whaleMapping[strategyIlkId]);
        assertEq(cauldron.balances(vaultId2).art, borrowAmount);
        assertEq(IERC20(strategyAddress).balanceOf(vault.owner), 0);

        // Checking if the state of first user's vault remains the same
        vault = cauldron.vaults(vaultId);
        assertEq(vault.owner, address(this));
        assertEq(cauldron.balances(vaultId).art, borrowAmount);
        assertEq(IERC20(strategyAddress).balanceOf(vault.owner), 0);
    }

    /// @notice Test if the user is able to repay
    function testRepay() public {
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        lever.divest(
            YieldStrategyLever.Operation.REPAY,
            vaultId,
            seriesId,
            strategyIlkId,
            balances.ink,
            balances.art,
            0
        );
        balances = cauldron.balances(vaultId);
        assertEq(balances.ink, 0);
        assertEq(balances.art, 0);
        assertEq(
            IPool(ladle.pools(seriesId)).base().balanceOf(address(lever)),
            0
        );
        assertEq(
            IPool(ladle.pools(seriesId)).fyToken().balanceOf(address(lever)),
            0
        );
        finalUserBalance = IPool(ladle.pools(seriesId)).base().balanceOf(
            address(this)
        );

        // Checking for profits
        assertGt(int256(finalUserBalance) - int256(initialUserBalance), 0);
    }

    /// @notice Test if the user is able to close
    function testDoClose() public {
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        lever.divest(
            YieldStrategyLever.Operation.CLOSE,
            vaultId,
            seriesId,
            strategyIlkId,
            balances.ink,
            balances.art,
            0
        );
        balances = cauldron.balances(vaultId);
        assertEq(balances.ink, 0);
        assertEq(balances.art, 0);
        assertEq(
            IPool(ladle.pools(seriesId)).base().balanceOf(address(lever)),
            0
        );
        assertEq(
            IPool(ladle.pools(seriesId)).fyToken().balanceOf(address(lever)),
            0
        );
        finalUserBalance = IPool(ladle.pools(seriesId)).base().balanceOf(
            address(this)
        );
        // Checking for profits
        assertGt(int256(finalUserBalance) - int256(initialUserBalance), 0);
    }

    /// @notice Test if revert happens if redeem is called before maturity
    function testRedeemBeforeMaturity() public {
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        vm.expectRevert();
        lever.divest(
            YieldStrategyLever.Operation.REDEEM,
            vaultId,
            seriesId,
            strategyIlkId,
            balances.ink,
            balances.art,
            0
        );
    }

    /// @notice Test if invest reverts if repay is added as an operation
    function testFailInvestWithRepay() public {
        vaultId = lever.invest(
            YieldStrategyLever.Operation.REPAY,
            seriesId,
            strategyIlkId, // ilkId edai
            10000e18,
            5000e18,
            fyTokenToBuy,
            0 //minCollateral,
        );
    }

    /// @notice Test if invest reverts if called with REDEEM operation
    function testFailInvestWithRedeem() public {
        vaultId = lever.invest(
            YieldStrategyLever.Operation.REDEEM,
            seriesId,
            strategyIlkId, // ilkId edai
            10000e18,
            5000e18,
            fyTokenToBuy,
            0 //minCollateral,
        );
    }

    /// @notice Test if invest reverts if called with CLOSE operation
    function testFailInvestWithClose() public {
        vaultId = lever.invest(
            YieldStrategyLever.Operation.CLOSE,
            seriesId,
            strategyIlkId, // ilkId edai
            10000e18,
            5000e18,
            fyTokenToBuy,
            0 //minCollateral,
        );
    }
}

abstract contract InvestedMatureState is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        DataTypes.Series memory series_ = cauldron.series(seriesId);
        vm.warp(series_.maturity + 1);
    }

    /// @notice Test if the user is able to redeem
    function testRedeem() public {
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        lever.divest(
            YieldStrategyLever.Operation.REDEEM,
            vaultId,
            seriesId,
            strategyIlkId,
            balances.ink,
            balances.art,
            0
        );
        balances = cauldron.balances(vaultId);
        assertEq(balances.ink, 0);
        assertEq(balances.art, 0);
        assertEq(
            IPool(ladle.pools(seriesId)).base().balanceOf(address(lever)),
            0
        );
        assertEq(
            IPool(ladle.pools(seriesId)).fyToken().balanceOf(address(lever)),
            0
        );

        finalUserBalance = IPool(ladle.pools(seriesId)).base().balanceOf(
            address(this)
        );
        // Checking for profits
        assertGt(int256(finalUserBalance) - int256(initialUserBalance), 0);
    }

    /// @notice Test if revert happens if close is called after maturity
    function testDoCloseAfterMaturity() public {
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        vm.expectRevert();
        lever.divest(
            YieldStrategyLever.Operation.CLOSE,
            vaultId,
            seriesId,
            strategyIlkId,
            balances.ink,
            balances.art,
            0
        );
    }

    /// @notice Test if revert happens if user tries to repay after maturity
    function testFailRepayAfterMaturity() public {
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        lever.divest(
            YieldStrategyLever.Operation.REPAY,
            vaultId,
            seriesId,
            strategyIlkId,
            balances.ink,
            balances.art,
            0
        );
    }
}
