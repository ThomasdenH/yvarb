// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;
import "./YieldLeverBase.sol";
import "./interfaces/IStableSwap.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";

interface WstEth is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256);

    function unwrap(uint256 _wstETHAmount) external returns (uint256);
}

/// @notice This contracts allows a user to 'lever up' via StEth. The concept
///     is as follows: Using Yield, it is possible to borrow Weth, which in
///     turn can be used as collateral, which in turn can be used to borrow and
///     so on.
///
///     The way to do this in practice is by first borrowing the desired debt
///     through a flash loan and using this in additon to your own collateral.
///     The flash loan is repayed using funds borrowed using your collateral.
contract YieldStEthLever is YieldLeverBase {
    using TransferHelper for IFYToken;
    using TransferHelper for IWETH9;
    using TransferHelper for WstEth;

    /// @notice StEth, represents Ether stakes on Lido.
    IERC20 public constant steth =
        IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    /// @notice WStEth, wrapped StEth, useful because StEth rebalances.
    WstEth public constant wsteth =
        WstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    /// @notice Curve.fi token swapping contract between Ether and StETH.
    IStableSwap public constant stableSwap =
        IStableSwap(0x828b154032950C8ff7CF8085D841723Db2696056);
    /// @notice The Yield Protocol Join containing WstEth.
    FlashJoin public constant wstethJoin =
        FlashJoin(0x5364d336c2d2391717bD366b29B6F351842D7F82);
    /// @notice The Yield Protocol Join containing Weth.
    FlashJoin public constant wethJoin =
        FlashJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0);

    /// @notice Deploy this contract.
    /// @param giver_ The `Giver` contract to use.
    /// @dev The contract should never own anything in between transactions;
    ///     no tokens, no vaults. To save gas we give these tokens full
    ///     approval.
    constructor(Giver giver_) YieldLeverBase(giver_) {
        weth.approve(address(stableSwap), type(uint256).max);
        steth.approve(address(stableSwap), type(uint256).max);
        weth.approve(address(wethJoin), type(uint256).max);
        steth.approve(address(wsteth), type(uint256).max);
    }

    /// @notice This function is called from within the flash loan. The high
    ///     level functionality is as follows:
    ///         - We have supplied and borrowed FYWeth.
    ///         - We convert it to StEth and put it in the vault.
    ///         - Against it, we borrow enough FYWeth to repay the flash loan.
    /// @param seriesId The pool (and thereby series) to borrow from.
    /// @param vaultId The vault id to put collateral into and borrow from.
    /// @param baseAmount The amount of own collateral to supply.
    /// @param borrowAmount The amount of FYWeth borrowed in the flash loan.
    /// @param fee The fee that will be issued by the flash loan.
    function borrow(
        bytes6, // ilkId
        bytes6 seriesId,
        bytes12 vaultId,
        uint128 baseAmount,
        uint256 borrowAmount,
        uint256 fee
    ) internal override {
        // We need to sell fyTokens
        IPool pool = IPool(ladle.pools(seriesId));
        pool.fyToken().safeTransfer(address(pool), borrowAmount);
        uint256 wethReceived = pool.sellFYToken(address(this), 0);

        // Buy StEth from the base and the borrowed Weth
        uint256 boughtStEth = stableSwap.exchange(
            0,
            1,
            wethReceived + baseAmount,
            0,
            address(this)
        );

        // Wrap StEth to WStEth.
        uint128 wrappedStEth = uint128(wsteth.wrap(boughtStEth));

        // Deposit WStEth in the vault & borrow `borrowAmount` fyToken to
        // pay back.
        wsteth.safeTransfer(address(wstethJoin), wrappedStEth);
        ladle.pour(
            vaultId,
            address(this),
            int128(uint128(wrappedStEth)),
            int128(uint128(borrowAmount + fee))
        );

        // At the end, the flash loan will take exactly `borrowedAmount + fee`,
        // so the final balance should be exactly 0.
    }

    /// @dev    - We have borrowed liquidity tokens, for which we have a debt.
    ///         - Remove `ink` collateral and repay `art` debt.
    ///         - Sell obtained `ink` StEth for WEth.
    ///         - Repay loan by buying liquidity tokens
    ///         - Send remaining WEth to user
    /// @param vaultId The vault to repay.
    /// @param seriesId The seriesId corresponding to the vault.
    /// @param borrowAmountPlusFee The amount of fyWeth that we have borrowed,
    ///     plus the fee. This should be our final balance.
    function repay(
        bytes6, // ilkId
        bytes12 vaultId,
        bytes6 seriesId,
        uint128 borrowAmountPlusFee, // Amount of FYToken received
        uint128 ink,
        uint128 art
    ) internal override {
        // Repay the vault, get collateral back.
        ladle.pour(vaultId, address(this), -int128(ink), -int128(art));

        // Unwrap WStEth to obtain StEth.
        uint256 stEthUnwrapped = wsteth.unwrap(ink);

        // Exchange StEth for WEth.
        // 0: WETH
        // 1: STETH
        stableSwap.exchange(
            1,
            0,
            stEthUnwrapped,
            1,
            // We can't send directly to the pool because the remainder is our
            // profit!
            address(this)
        );

        // Convert weth to FY to repay loan. We want `borrowAmountPlusFee`.
        IPool pool = IPool(ladle.pools(seriesId));
        uint128 wethSpent = pool.buyFYTokenPreview(borrowAmountPlusFee);
        weth.safeTransfer(address(pool), wethSpent);
        pool.buyFYToken(address(this), borrowAmountPlusFee, wethSpent);

        // We should have exactly `borrowAmountPlusFee` fyWeth as that is what
        // we have bought. This pays back the flash loan exactly.
    }

    /// @notice Close a vault after maturity.
    ///         - We have borrowed WEth
    ///         - Use it to repay the debt and take the collateral.
    ///         - Sell it all for WEth and close position.
    /// @param vaultId The ID of the vault to close.
    /// @param ink The collateral to take from the vault.
    /// @param art The debt to repay. This is denominated in fyTokens, even
    ///     though the payment is done in terms of WEth.
    function close(
        bytes6, // ilkId
        bytes12 vaultId,
        uint128 ink,
        uint128 art
    ) internal override {
        // We have obtained Weth, exactly enough to repay the vault. This will
        // give us our WStEth collateral back.
        // data[1:13]: vaultId
        // data[29:45]: art
        ladle.close(vaultId, address(this), -int128(ink), -int128(art));

        // Convert wsteth to steth
        uint256 stEthUnwrapped = wsteth.unwrap(ink);

        // convert steth - weth
        // 1: STETH
        // 0: WETH
        // No minimal amount is necessary: The flashloan will try to take the
        // borrowed amount and fee, and we will check for slippage afterwards.
        stableSwap.exchange(1, 0, stEthUnwrapped, 0, address(this));

        // At the end of the flash loan, we repay in terms of WEth and have
        // used the inital balance entirely for the vault, so we have better
        // obtained it!
    }
}
