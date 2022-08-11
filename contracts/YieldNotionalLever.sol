// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./YieldLeverBase.sol";
import "./NotionalTypes.sol";
import "@yield-protocol/vault-v2/other/notional/ERC1155.sol";

contract YieldNotionalLever is YieldLeverBase, ERC1155TokenReceiver {
    using TransferHelper for IERC20;
    using TransferHelper for IFYToken;

    Notional constant notional =
        Notional(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);

    struct IlkInfo {
        uint40 maturity;
        uint16 currencyId;
    }

    mapping(bytes6 => IlkInfo) public ilkInfo;

    constructor(Giver giver_) YieldLeverBase(giver_) {
        notional.setApprovalForAll(address(LADLE), true);
        notional.setApprovalForAll(
            0x0Bfd3B8570A4247157c5468861d37dA55AAb9B4b,
            true
        ); // Approving the Join

        notional.setApprovalForAll(
            0x399bA81A1f1Ed0221c39179C50d4d4Bc85C3F3Ab,
            true
        ); // Approving the join
    }

    // TODO: Make it auth controlled when deploying
    function setIlkInfo(
        bytes6 ilkId,
        IlkInfo calldata underlying,
        FlashJoin underlyingJoin
    ) external {
        IERC20 token = IERC20(underlyingJoin.asset());
        token.approve(address(underlyingJoin), type(uint256).max);
        token.approve(address(notional), type(uint256).max);
        ilkInfo[ilkId] = underlying;
    }

    // TODO: Make it auth controlled when deploying
    function approveJoin(address joinAddress) external {
        notional.setApprovalForAll(joinAddress, true);
    }

    /// @notice This function is called from within the flash loan. The high
    ///     level functionality is as follows:
    ///         - We have supplied 'dai' or 'usdc'.
    ///         - We deposit it to get fCash and put it in the vault.
    ///         - Against it, we borrow enough fyDai or fyUSDC to repay the flash loan.
    /// @param ilkId Id of the Ilk
    /// @param seriesId The pool (and thereby series) to borrow from.
    /// @param vaultId The vault id to put collateral into and borrow from.
    /// @param borrowAmount The amount of DAI/USDC borrowed in the flash loan.
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
        // We need to sell fyTokens
        IPool pool = IPool(LADLE.pools(seriesId));
        pool.fyToken().safeTransfer(address(pool), borrowAmount);
        uint256 totalToInvest = baseAmount;
        totalToInvest += pool.sellFYToken(address(this), 0);

        IlkInfo memory ilkIdInfo = ilkInfo[ilkId];
        // Deposit into notional to get the fCash
        (uint88 fCashAmount, , bytes32 encodedTrade) = notional
            .getfCashLendFromDeposit(
                ilkIdInfo.currencyId,
                totalToInvest, // total to invest
                ilkIdInfo.maturity,
                0,
                block.timestamp,
                true
            );

        BalanceActionWithTrades[]
            memory actions = new BalanceActionWithTrades[](1);
        actions[0] = BalanceActionWithTrades({
            actionType: DepositActionType.DepositUnderlying, // Deposit underlying, not cToken
            currencyId: ilkIdInfo.currencyId,
            depositActionAmount: totalToInvest, // total to invest
            withdrawAmountInternalPrecision: 0,
            withdrawEntireCashBalance: false, // Return all residual cash to lender
            redeemToUnderlying: false, // Convert cToken to token
            trades: new bytes32[](1)
        });
        actions[0].trades[0] = encodedTrade;
        notional.batchBalanceAndTradeAction(address(this), actions);

        LADLE.pour(
            vaultId,
            address(this),
            int128(uint128(fCashAmount)),
            int128(uint128(borrowAmount + fee))
        );
    }

    /// @param borrowAmountPlusFee The amount of fyDai/fyUsdc that we have borrowed,
    ///     plus the fee. This should be our final balance.
    /// @param vaultId The vault to repay.
    function repay(
        bytes6 ilkId,
        bytes12 vaultId,
        bytes6 seriesId,
        uint128 borrowAmountPlusFee, // Amount of FYToken received
        uint128 ink,
        uint128 art
    ) internal override {
        // Repay the vault, get collateral back.
        LADLE.pour(vaultId, address(this), -int128(ink), -int128(art));
        {
            IlkInfo memory ilkIdInfo = ilkInfo[ilkId];
            // Trade fCash to receive USDC/DAI
            BalanceActionWithTrades[]
                memory actions = new BalanceActionWithTrades[](1);
            actions[0] = BalanceActionWithTrades({
                actionType: DepositActionType.None,
                currencyId: ilkIdInfo.currencyId,
                depositActionAmount: 0,
                withdrawAmountInternalPrecision: 0,
                withdrawEntireCashBalance: true,
                redeemToUnderlying: true,
                trades: new bytes32[](1)
            });

            (, , , bytes32 encodedTrade) = notional.getPrincipalFromfCashBorrow(
                ilkIdInfo.currencyId,
                ink,
                ilkIdInfo.maturity,
                0,
                block.timestamp
            );

            actions[0].trades[0] = encodedTrade;
            notional.batchBalanceAndTradeAction(address(this), actions);
        }

        // Buy FyTokens to repay flash loan
        IPool pool = IPool(LADLE.pools(seriesId));
        IERC20(pool.base()).safeTransfer(
            address(pool),
            pool.buyFYTokenPreview(borrowAmountPlusFee)
        );
        pool.buyFYToken(address(this), borrowAmountPlusFee, type(uint128).max);

        // The excess base will be transferred to the user.
    }

    /// @notice Close a vault after maturity.
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
        LADLE.close(vaultId, address(this), -int128(ink), -int128(art));
    }

    /// @dev Called by the sender after a transfer to verify it was received. Ensures only `id` tokens are received.
    function onERC1155Received(
        address,
        address,
        uint256, // _id,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    /// @dev Called by the sender after a batch transfer to verify it was received. Ensures only `id` tokens are received.
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata, // _ids,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }
}
