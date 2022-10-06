// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./YieldLeverBase.sol";

interface IStrategy {
    function mint(address to) external returns (uint256 minted);

    function burn(address to) external returns (uint256 withdrawal);

    function burnForBase(address to) external returns (uint256 withdrawal);

    function pool() external returns (IPool pool);
}

contract YieldStrategyLever is YieldLeverBase {
    using TransferHelper for IERC20;
    using TransferHelper for IFYToken;

    mapping(bytes6 => IStrategy) strategies;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    constructor(Giver giver_) YieldLeverBase(giver_) {
        IERC20(USDC).approve(
            address(LADLE.joins(0x303200000000)),
            type(uint256).max
        );
        IERC20(DAI).approve(
            address(LADLE.joins(0x303100000000)),
            type(uint256).max
        );
    }

    function setStrategy(bytes6 ilkId, IStrategy strategy) external {
        strategies[ilkId] = strategy;
        IERC20(CAULDRON.assets(ilkId)).approve(
            address(LADLE.joins(ilkId)),
            type(uint256).max
        );
    }

    /// @notice This function is called from within the flash loan.
    /// @param ilkId The id of the ilk being borrowed.
    /// @param seriesId The pool (and thereby series) to borrow from.
    /// @param vaultId The vault id to put collateral into and borrow from.
    /// @param borrowAmount The amount of FYTOKEN borrowed in the flash loan.
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
        IPool pool = IPool(LADLE.pools(seriesId));
        IFYToken tempFyToken = pool.fyToken();
        tempFyToken.safeTransfer(address(pool), borrowAmount - fee);
        uint256 baseReceived = pool.sellFYToken(address(pool), 0); // Sell fyToken to get USDC/DAI/ETH
        pool.base().transfer(
            address(pool),
            pool.base().balanceOf(address(this))
        );
        // Mint LP token & deposit to strategy
        pool.mintWithBase(
            address(strategies[ilkId]),
            msg.sender,
            uint256(
                pool.buyFYTokenPreview(uint128((baseReceived + baseAmount) / 3))
            ), // TODO: what should be the fyTokenToBuy
            0,
            type(uint256).max
        );

        // Mint strategy token
        uint256 tokensMinted = strategies[ilkId].mint(
            address(LADLE.joins(ilkId))
        );

        // Borrow fyToken to repay the flash loan
        LADLE.pour(
            vaultId,
            address(this),
            int128(uint128(tokensMinted)),
            int128(uint128(borrowAmount))
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
        IPool pool = IPool(LADLE.pools(seriesId));
        // Payback debt to get back the underlying
        LADLE.pour(
            vaultId,
            address(strategies[ilkId]),
            -int128(ink),
            -int128(art)
        );

        // Burn strat token to get LP
        strategies[ilkId].burn(address(pool));

        // Burn LP to get base & fyToken
        (, uint256 bases, uint256 fyTokens) = pool.burn(
            address(pool),
            address(this),
            0,
            type(uint256).max
        );
        // buyFyToken
        pool.buyFYToken(
            address(this),
            borrowAmountPlusFee - uint128(fyTokens),
            uint128(bases)
        );
    }

    /// @notice Close a vault after maturity.
    /// @param ilkId The id of the ilk.
    /// @param vaultId The ID of the vault to close.
    /// @param ink The collateral to take from the vault.
    /// @param art The debt to repay. This is denominated in fyTokens
    function close(
        bytes6 ilkId,
        bytes12 vaultId,
        uint128 ink,
        uint128 art
    ) internal override {
        IStrategy strategy = strategies[ilkId];
        IPool pool = strategy.pool();

        LADLE.close(vaultId, address(strategy), -int128(ink), -int128(art));
        // Burn Strategy Tokens and send LP token to the pool
        strategy.burn(address(pool));
        // Burn LP token to obtain base to repay the flash loan
        pool.burnForBase(address(this), 0, type(uint256).max);
    }
}
