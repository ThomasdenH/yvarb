// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/YieldNotionalLever.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/vault-v2/FYToken.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "./Protocol.sol";
import "@yield-protocol/vault-v2/utils/Giver.sol";
import "@yield-protocol/vault-v2/FlashJoin.sol";
import "@yield-protocol/vault-v2/interfaces/ICauldron.sol";
import "@yield-protocol/vault-v2/interfaces/IFYToken.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";

struct ilk_info {
    address join;
    uint40 maturity;
    uint16 currencyId;
}

abstract contract ZeroState is Test {
    address constant timeLock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    address constant usdcWhale = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
    address constant daiWhale = 0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8;
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ICauldron constant cauldron =
        ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    FlashJoin constant daiJoin =
        FlashJoin(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc); // dai
    FlashJoin constant usdcJoin =
        FlashJoin(0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4); // usdc
    ILadle constant ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);

    Protocol immutable protocol;
    Giver immutable giver;
    YieldNotionalLever lever;

    bytes6 constant fyusdcSeriesId = 0x303230380000;
    bytes6 constant fydaiSeriesId = 0x303130380000;

    bytes6 constant fusdcIlkId = 0x323400000000;
    bytes6 constant fdaiIlkId = 0x323300000000;

    bytes6 constant usdcIlkId = 0x303200000000;
    bytes6 constant daiIlkId = 0x303100000000;
    bytes12 public vaultId;
    bytes6 public fIlkId;
    bytes6 public fSeriesId;
    bytes6 public ilkId;
    uint256 public baseAmount;
    uint256 public borrowAmount;

    uint256 public initialUserBalance;
    uint256 public finalUserBalance;

    constructor() {
        protocol = new Protocol();
        giver = new Giver(cauldron);
        vm.prank(timeLock);
        AccessControl(address(cauldron)).grantRole(0x798a828b, address(giver));

        vm.prank(usdcWhale);
        IERC20(USDC).transfer(address(this), 2000e6);
        vm.prank(daiWhale);
        IERC20(DAI).transfer(address(this), 2000e18);

        vm.startPrank(timeLock);
        usdcJoin.setFlashFeeFactor(0);
        daiJoin.setFlashFeeFactor(0);
        FYToken(address(IPool(ladle.pools(fyusdcSeriesId)).fyToken()))
            .setFlashFeeFactor(0);
        FYToken(address(IPool(ladle.pools(fydaiSeriesId)).fyToken()))
            .setFlashFeeFactor(0);
        vm.stopPrank();
    }

    function setUp() public virtual {
        lever = new YieldNotionalLever(giver);

        fIlkId = fusdcIlkId;
        fSeriesId = fyusdcSeriesId;
        ilkId = usdcIlkId;
        baseAmount = 2000e6;
        borrowAmount = 5000e6;
        USDC.approve(address(lever), type(uint256).max);
        DAI.approve(address(lever), type(uint256).max);

        // USDC
        lever.setIlkInfo(
            fusdcIlkId,
            YieldNotionalLever.IlkInfo({
                join: usdcJoin,
                maturity: 1671840000,
                currencyId: 3
            })
        );

        // DAI
        lever.setIlkInfo(
            fdaiIlkId,
            YieldNotionalLever.IlkInfo({
                join: daiJoin,
                maturity: 1671840000,
                currencyId: 2
            })
        );

        giver.grantRole(0xe4fd9dc5, timeLock);
        giver.grantRole(0x35775afb, address(lever));
        if (ilkId == usdcIlkId)
            initialUserBalance = USDC.balanceOf(address(this));
        else initialUserBalance = DAI.balanceOf(address(this));
    }

    /// @notice Create a vault.
    function leverUp(
        uint256 baseAmount,
        uint256 borrowAmount,
        bytes6 ilkId,
        bytes6 seriesId
    ) public returns (bytes12) {
        // Expect at least 80% of the value to end up as collateral
        // uint256 eulerAmount = pool.sellFYTokenPreview(baseAmount + borrowAmount);

        vaultId = lever.invest(
            seriesId,
            ilkId, // ilkId
            baseAmount,
            borrowAmount
        );
        return vaultId;
    }

    /// Return the available balance in the join.
    function availableBalance(bytes6 ilkIdToCheck)
        public
        view
        returns (uint256 available)
    {
        (FlashJoin join, , ) = lever.ilkInfo(ilkIdToCheck);
        IERC20 token = IERC20(join.asset());
        available = token.balanceOf(address(join)) - join.storedBalance();
    }
}

contract VaultTest is ZeroState {
    function testVault() public {
        uint256 availableAtStart = availableBalance(fIlkId);
        vaultId = leverUp(baseAmount, borrowAmount, fIlkId, fSeriesId);
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        assertEq(vault.owner, address(this));
        assertGt(cauldron.balances(vaultId).art, borrowAmount);
        assertGt(cauldron.balances(vaultId).ink, baseAmount + borrowAmount);
        // Test that we left the join as we encountered it
        assertEq(availableBalance(fIlkId), availableAtStart);

        // Assert that the balances are empty
        assertEq(IERC20(USDC).balanceOf(address(lever)), 0);
        assertEq(IERC20(DAI).balanceOf(address(lever)), 0);
        assertEq(
            IPool(ladle.pools(fSeriesId)).fyToken().balanceOf(address(lever)),
            0
        );
    }
}

contract DivestTest is ZeroState {
    function setUp() public override {
        super.setUp();
        vaultId = leverUp(baseAmount, borrowAmount, fIlkId, fSeriesId);
    }

    function testRepay() public {
        uint256 availableAtStart = availableBalance(fIlkId);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);

        lever.divest(vaultId, fSeriesId, fIlkId, balances.ink, balances.art, 0);

        // Test that we left the join as we encountered it
        assertEq(availableBalance(fIlkId), availableAtStart);

        // Assert that the balances are empty
        assertEq(USDC.balanceOf(address(lever)), 0);
        assertEq(DAI.balanceOf(address(lever)), 0);
        assertEq(
            IPool(ladle.pools(fSeriesId)).fyToken().balanceOf(address(lever)),
            0
        );

        if (ilkId == usdcIlkId)
            finalUserBalance = USDC.balanceOf(address(this));
        else finalUserBalance = DAI.balanceOf(address(this));
        assertGt(finalUserBalance, initialUserBalance);
    }

    function testDoClose() public {
        uint256 availableAtStart = availableBalance(fIlkId);
        DataTypes.Series memory series_ = cauldron.series(fSeriesId);
        vm.warp(series_.maturity);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        lever.divest(vaultId, fSeriesId, fIlkId, balances.ink, balances.art, 0);

        // Test that we left the join as we encountered it
        // assertEq(availableBalance(fIlkId), availableAtStart);

        // Assert that the balances are empty
        assertEq(USDC.balanceOf(address(lever)), 0);
        assertEq(DAI.balanceOf(address(lever)), 0);
        assertEq(
            IPool(ladle.pools(fSeriesId)).fyToken().balanceOf(address(lever)),
            0
        );
        if (ilkId == usdcIlkId)
            finalUserBalance = USDC.balanceOf(address(this));
        else finalUserBalance = DAI.balanceOf(address(this));
        assertGt(finalUserBalance, initialUserBalance);
    }
}
