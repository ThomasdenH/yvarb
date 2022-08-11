// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "./interfaces/IEulerMarkets.sol";
import "./interfaces/IEulerEToken.sol";
import "./YieldLeverBase.sol";

// Get flash loan of USDC/DAI/WETH
// Deposit to get eulerToken
// Deposit & borrow against it
// Sell the fyToken to get USDC/DAI
// Close the flash loan
contract YieldEulerLever is YieldLeverBase {
    using TransferHelper for IERC20;
    using TransferHelper for IFYToken;

    // address constant EULER_MAINNET;
    address public constant EULER = 0x27182842E098f60e3D576794A5bFFb0777E025d3;

    // Use the markets module:
    IEulerMarkets public constant markets =
        IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);

    mapping(bytes6 => FlashJoin) public flashJoins;
    mapping(bytes6 => address) public ilkToAsset;

    constructor(Giver giver_) YieldLeverBase(giver_) {

    }

    /// @notice Add an euler asset configuration.
    /// @param assetId The yield asset ID for this eToken.
    /// @param join The Yield join.
    // TODO: Make auth
    // TODO: We can probably derive the join via the assetId through LadleStorage.joins
    function addEulerAsset(bytes6 assetId, FlashJoin join) external {
        IERC20 token = IERC20(join.asset());
        token.approve(EULER, type(uint256).max);
        token.approve(address(join), type(uint256).max);
        flashJoins[assetId] = join;
        ilkToAsset[assetId] = address(token);
    }

    /// @notice This function is called from within the flash loan. The high
    ///     level functionality is as follows:
    ///         - We have supplied and borrowed FYWeth.
    ///         - We convert it to StEth and put it in the vault.
    ///         - Against it, we borrow enough FYWeth to repay the flash loan.
    /// @param ilkId The id of the ilk being borrowed.
    /// @param seriesId The pool (and thereby series) to borrow from.
    /// @param vaultId The vault id to put collateral into and borrow from.
    /// @param borrowAmount The amount of FYWeth borrowed in the flash loan.
    /// @param fee The fee that will be issued by the flash loan.
    /// @param baseAmount The amount of own collateral to supply.
    function borrow(
        bytes6 ilkId,
        bytes6 seriesId,
        bytes12 vaultId,
        uint128 baseAmount,
        uint256 borrowAmount,
        uint256 fee
    ) internal override {
        // We have borrowed FyTokens, so sell those
        IPool pool = IPool(ladle.pools(seriesId));
        pool.fyToken().safeTransfer(address(pool), borrowAmount);
        uint128 totalToInvest = baseAmount + uint128(pool.sellFYToken(address(this), 0));

        // Deposit to get Euler token in return which would be used to payback flashloan
        // Get the eToken address using the markets module:

        IEulerEToken eToken = IEulerEToken(
            markets.underlyingToEToken(ilkToAsset[ilkId])
        );

        eToken.deposit(0, totalToInvest);

        uint256 eBalance = eToken.balanceOf(address(this));

        eToken.transfer(address(ladle.joins(ilkId)), eBalance);

        // Add collateral and borrow exactly enough to pay back the flash loan
        ladle.pour(
            vaultId,
            address(pool),
            int128(uint128(eBalance)),
            int128(uint128(borrowAmount + fee))
        );
    }

    /// @param ilkId The id of the ilk being invested.
    /// @param seriesId The seriesId corresponding to the vault.
    /// @param vaultId The vault to repay.
    /// @param borrowAmountPlusFee The amount of fyDai/fyUsdc that we have borrowed,
    ///     plus the fee. This should be our final balance.
    /// @param ink The amount of collateral to retake.
    /// @param art The debt to repay.
    ///     slippage.
    function repay(
        bytes6 ilkId,
        bytes12 vaultId,
        bytes6 seriesId,
        uint128 borrowAmountPlusFee,
        uint128 ink,
        uint128 art
    ) internal override {
        // Repay the vault, get collateral back.
        ladle.pour(vaultId, address(this), -int128(ink), -int128(art));

        address asset = ilkToAsset[ilkId];
        IEulerEToken eToken = IEulerEToken(
            markets.underlyingToEToken(asset)
        );

        eToken.withdraw(0, type(uint256).max);

        // buyFyToken
        IPool pool = IPool(ladle.pools(seriesId));
        uint128 tokenToTran = pool.buyFYTokenPreview(borrowAmountPlusFee);

        IERC20(asset).safeTransfer(address(pool), tokenToTran);

        pool.buyFYToken(address(this), borrowAmountPlusFee, tokenToTran);
    }

    /// @notice Close a vault after maturity.
    /// @param ilkId The id of the ilk.
    /// @param vaultId The ID of the vault to close.
    /// @param ink The collateral to take from the vault.
    /// @param art The debt to repay. This is denominated in fyTokens, even
    ///     though the payment is done in terms of WEth.
    function close(
        bytes6 ilkId,
        bytes12 vaultId,
        uint128 ink,
        uint128 art
    ) internal override {
        ladle.close(vaultId, address(this), -int128(ink), -int128(art));

        IEulerEToken eToken = IEulerEToken(
            markets.underlyingToEToken(ilkToAsset[ilkId])
        );

        eToken.withdraw(0, type(uint256).max);
    }
}
