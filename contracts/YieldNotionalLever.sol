// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./YieldLeverBase.sol";
import "./NotionalTypes.sol";
import "forge-std/console.sol";
import "@yield-protocol/vault-v2/other/notional/ERC1155.sol";

contract YieldNotionalLever is YieldLeverBase, ERC1155TokenReceiver {
    using TransferHelper for IERC20;
    using TransferHelper for IFYToken;
    FlashJoin immutable usdcJoin;
    FlashJoin immutable daiJoin;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    Notional constant notional =
        Notional(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);

    mapping(bytes6 => bytes1) ilkToUnderlying;
    mapping(bytes6 => uint40) ilkToMaturity;
    mapping(bytes6 => uint16) ilkToCurrencyId;

    constructor(
        Giver giver_,
        address usdcJoin_,
        address daiJoin_
    ) YieldLeverBase(giver_) {
        usdcJoin = FlashJoin(usdcJoin_);
        daiJoin = FlashJoin(daiJoin_);

        IERC20(USDC).approve(usdcJoin_, type(uint256).max);
        IERC20(DAI).approve(daiJoin_, type(uint256).max);
        IERC20(USDC).approve(address(notional), type(uint256).max);
        IERC20(DAI).approve(address(notional), type(uint256).max);

        notional.setApprovalForAll(address(ladle), true);
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
    function setIlkToUnderlying(bytes6 ilkId, bytes1 under) external {
        ilkToUnderlying[ilkId] = under;
    }

    // TODO: Make it auth controlled when deploying
    function setIlkToMaturity(bytes6 ilkId, uint40 maturity) external {
        ilkToMaturity[ilkId] = maturity;
    }

    // TODO: Make it auth controlled when deploying
    function setIlkToCurrencyId(bytes6 ilkId, uint16 currencyId) external {
        ilkToCurrencyId[ilkId] = currencyId;
    }

    // TODO: Make it auth controlled when deploying
    function approveJoin(address joinAddress) external {
        notional.setApprovalForAll(joinAddress, true);
    }

    /// @notice Approve maximally for an fyToken.
    /// @param seriesId The id of the pool to approve to.
    function approveFyToken(bytes6 seriesId) external {
        IPool(ladle.pools(seriesId)).fyToken().approve(
            address(ladle),
            type(uint256).max
        );
    }

    /// @notice Invest by creating a levered vault.
    ///
    ///     We invest `USDC` or `DAI`. For this the user should have given approval
    ///     first. We borrow `borrowAmount` extra. We use it to deposit in notional and get fCash, which we use as collateral.
    /// @param baseAmount The amount of own liquidity to supply.
    /// @param borrowAmount The amount of additional liquidity to borrow.
    /// @param seriesId The series to create the vault for.
    function invest(
        uint128 baseAmount,
        uint128 borrowAmount,
        bytes6 seriesId,
        bytes6 ilkId
    ) external returns (bytes12 vaultId) {
        (vaultId, ) = ladle.build(seriesId, ilkId, 0);
        // Since we know the sizes exactly, packing values in this way is more
        // efficient than using `abi.encode`.
        //
        // Encode data of
        // OperationType    1 byte      [0:1]
        // seriesId         6 bytes     [1:7]
        // ilkId            6 bytes     [7:13]
        // vaultId          12 bytes    [13:25]
        // baseAmount       16 bytes    [25:41]
        bytes memory data = bytes.concat(
            bytes1(uint8(uint256(Operation.LEVER_UP))),
            seriesId,
            ilkId,
            vaultId,
            bytes16(baseAmount)
        );

        bool success;
        if (ilkToUnderlying[ilkId] == 0x01) {
            // USDC
            IERC20(USDC).safeTransferFrom(
                msg.sender,
                address(this),
                baseAmount
            );
            success = usdcJoin.flashLoan(this, USDC, borrowAmount, data);
        } else {
            // DAI
            IERC20(DAI).safeTransferFrom(msg.sender, address(this), baseAmount);
            success = daiJoin.flashLoan(this, DAI, borrowAmount, data);
        }
        if (!success) revert FlashLoanFailure();
        giver.give(vaultId, msg.sender);

        DataTypes.Balances memory vault = cauldron.balances(vaultId);
    }

    /// @notice Called by a flash lender, which can be `usdcJoin` or
    ///     `daiJoin` or 'fyToken`. The primary purpose is to check conditions
    ///     and route to the correct internal function.
    ///
    ///     This function reverts if not called through a flashloan initiated
    ///     by this contract.
    /// @param initiator The initator of the flash loan, must be `address(this)`.
    /// @param borrowAmount The amount of fyTokens received.
    /// @param fee The fee that is subtracted in addition to the borrowed
    ///     amount when repaying.
    /// @param data The data we encoded for the functions. Here, we only check
    ///     the first byte for the router.
    function onFlashLoan(
        address initiator,
        address, // The token, not checked as we check the lender address.
        uint256 borrowAmount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        Operation status = Operation(uint256(uint8(data[0])));
        bytes6 seriesId = bytes6(data[1:7]);
        IFYToken fyToken = IPool(ladle.pools(seriesId)).fyToken();
        // Test that the lender is either the fyToken contract or the usdc Join or daiJoin
        if (
            msg.sender != address(fyToken) &&
            msg.sender != address(usdcJoin) &&
            msg.sender != address(daiJoin)
        ) revert FlashLoanFailure();
        // We trust the lender, so now we can check that we were the initiator.
        if (initiator != address(this)) revert FlashLoanFailure();

        // Decode the operation to execute and then call that function.
        if (status == Operation.LEVER_UP) {
            bytes6 ilkId = bytes6(data[7:13]);
            bytes12 vaultId = bytes12(data[13:25]);
            uint128 baseAmount = uint128(uint128(bytes16(data[25:41])));

            leverUp(borrowAmount, fee, baseAmount, vaultId, seriesId, ilkId);
        } else if (status == Operation.REPAY) {
            bytes6 ilkId = bytes6(data[7:13]);
            bytes12 vaultId = bytes12(data[13:25]);
            uint128 ink = uint128(bytes16(data[25:41]));
            uint128 art = uint128(bytes16(data[41:57]));
            address borrower = address(bytes20(data[57:77]));
            doRepay(
                uint128(borrowAmount + fee),
                vaultId,
                ilkId,
                ink,
                art,
                borrower,
                seriesId
            );
        } else if (status == Operation.CLOSE) {
            bytes12 vaultId = bytes12(data[7:19]);
            uint128 ink = uint128(bytes16(data[19:35]));
            uint128 art = uint128(bytes16(data[35:51]));

            doClose(vaultId, ink, art);
        }
        return FLASH_LOAN_RETURN;
    }

    /// @notice This function is called from within the flash loan. The high
    ///     level functionality is as follows:
    ///         - We have supplied 'dai' or 'usdc'.
    ///         - We deposit it to get fCash and put it in the vault.
    ///         - Against it, we borrow enough fyDai or fyUSDC to repay the flash loan.
    /// @param borrowAmount The amount of DAI/USDC borrowed in the flash loan.
    /// @param fee The fee that will be issued by the flash loan.
    /// @param baseAmount The amount of own collateral to supply.
    /// @param vaultId The vault id to put collateral into and borrow from.
    /// @param seriesId The pool (and thereby series) to borrow from.
    function leverUp(
        uint256 borrowAmount,
        uint256 fee,
        uint128 baseAmount,
        bytes12 vaultId,
        bytes6 seriesId,
        bytes6 ilkId
    ) internal {
        // uint128 netInvestAmount = uint128(baseAmount + borrowAmount - fee);
        // Deposit into notional to get the fCash
        BalanceActionWithTrades[]
            memory actions = new BalanceActionWithTrades[](1);

        (uint88 fCashAmount, , bytes32 encodedTrade) = notional
            .getfCashLendFromDeposit(
                ilkToCurrencyId[ilkId],
                uint128(baseAmount + borrowAmount - fee),
                ilkToMaturity[ilkId], // September maturity
                0,
                block.timestamp,
                true
            );

        actions[0] = BalanceActionWithTrades({
            actionType: DepositActionType.DepositUnderlying, // Deposit underlying, not cToken
            currencyId: ilkToCurrencyId[ilkId],
            depositActionAmount: uint128(baseAmount + borrowAmount - fee),
            withdrawAmountInternalPrecision: 0,
            withdrawEntireCashBalance: false, // Return all residual cash to lender
            redeemToUnderlying: false, // Convert cToken to token
            trades: new bytes32[](1)
        });
        actions[0].trades[0] = encodedTrade;
        notional.batchBalanceAndTradeAction(address(this), actions);

        _pourAndSell(vaultId, fCashAmount, borrowAmount, seriesId);
    }

    /// @dev Additional function to get over stack too deep
    /// @param vaultId VaultId
    /// @param fCashAmount Amount of collateral
    /// @param borrowAmount Amount being borrowed
    /// @param seriesId SeriesId being
    function _pourAndSell(
        bytes12 vaultId,
        uint256 fCashAmount,
        uint256 borrowAmount,
        bytes6 seriesId
    ) internal {
        IPool pool = IPool(ladle.pools(seriesId));
        ladle.pour(
            vaultId,
            address(pool),
            int128(uint128(fCashAmount)),
            int128(pool.buyBasePreview(uint128(borrowAmount) + 1)) // TODO: +1 here borrows the correct amount what to do?
        );
        pool.sellFYToken(address(this), 0);
    }

    /// @notice Unwind a position.
    ///
    ///     If pre maturity, borrow liquidity tokens to repay `art` debt and
    ///     take `ink` collateral.
    ///
    ///     If post maturity, borrow USDC/DAI to pay off the debt directly.
    ///
    ///     This function will take the vault from you using `Giver`, so make
    ///     sure you have given it permission to do that.
    /// @param ink The amount of collateral to recover.
    /// @param art The debt to repay.
    /// @param vaultId The vault to use.
    /// @param seriesId The seriesId corresponding to the vault.
    /// @dev It is more gas efficient to let the user supply the `seriesId`,
    ///     but it should match the pool.
    function unwind(
        uint128 ink,
        uint128 art,
        bytes12 vaultId,
        bytes6 seriesId,
        bytes6 ilkId
    ) external {
        // Test that the caller is the owner of the vault.
        // This is important as we will take the vault from the user.
        require(cauldron.vaults(vaultId).owner == msg.sender);

        // Give the vault to the contract
        giver.seize(vaultId, address(this));

        // Check if we're pre or post maturity.
        if (uint32(block.timestamp) < cauldron.series(seriesId).maturity) {
            IPool pool = IPool(ladle.pools(seriesId));
            IFYToken fyToken = pool.fyToken();
            // Close:
            // Series is not past maturity.
            // Borrow to repay debt, move directly to the pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.REPAY)))), // [0:1]
                seriesId, // [1:7]
                ilkId, // [7:13]
                vaultId, // [13:25]
                bytes16(ink), // [25:41]
                bytes16(art), // [41:57]
                bytes20(msg.sender)
            );
            bool success = IERC3156FlashLender(address(fyToken)).flashLoan(
                this, // Loan Receiver
                address(fyToken), // Loan Token
                art, // Loan Amount: borrow exactly the debt to repay.
                data
            );
            if (!success) revert FlashLoanFailure();

            // We have borrowed exactly enough for the debt and bought back
            // exactly enough for the loan + fee, so there is no balance of
            // FYToken left. Check:
            require(IERC20(address(fyToken)).balanceOf(address(this)) == 0);
        } else {
            // Close:
            // Series is not past maturity.
            // Borrow to repay debt, move directly to the pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.CLOSE)))), // [0:1]
                seriesId, // [1:7]
                vaultId, // [7:19]
                bytes16(ink), // [19:35]
                bytes16(art)
            );
            bool success;
            if (ilkToUnderlying[ilkId] == 0x01) {
                // USDC
                success = usdcJoin.flashLoan(
                    this, // Loan Receiver
                    USDC, // Loan Token
                    art, // Loan Amount: borrow exactly the debt to repay.
                    data
                );
                if (!success) revert FlashLoanFailure();
                uint256 balance = IERC20(USDC).balanceOf(address(this));
                if (balance > 0) IERC20(USDC).safeTransfer(msg.sender, balance);
            } else {
                // DAI
                success = daiJoin.flashLoan(
                    this, // Loan Receiver
                    DAI, // Loan Token
                    art, // Loan Amount: borrow exactly the debt to repay.
                    data
                );
                if (!success) revert FlashLoanFailure();
                uint256 balance = IERC20(DAI).balanceOf(address(this));
                if (balance > 0) IERC20(DAI).safeTransfer(msg.sender, balance);
            }
        }

        // Give the vault back to the sender, just in case there is anything left
        giver.give(vaultId, msg.sender);
    }

    /// @param borrowAmountPlusFee The amount of fyDai/fyUsdc that we have borrowed,
    ///     plus the fee. This should be our final balance.
    /// @param vaultId The vault to repay.
    /// @param ink The amount of collateral to retake.
    /// @param art The debt to repay.
    ///     slippage.
    /// @param borrower The borrower, the previous owner of the vault.
    function doRepay(
        uint128 borrowAmountPlusFee, // Amount of FYToken received
        bytes12 vaultId,
        bytes6 ilkId,
        uint128 ink,
        uint128 art,
        address borrower,
        bytes6 seriesId
    ) internal {
        // Repay the vault, get collateral back.
        ladle.pour(vaultId, address(this), -int128(ink), -int128(art));

        // Trade fCash to receive USDC/DAI
        BalanceActionWithTrades[]
            memory actions = new BalanceActionWithTrades[](1);

        actions[0] = BalanceActionWithTrades({
            actionType: DepositActionType.None,
            currencyId: ilkToCurrencyId[ilkId],
            depositActionAmount: 0,
            withdrawAmountInternalPrecision: 0,
            withdrawEntireCashBalance: true,
            redeemToUnderlying: true,
            trades: new bytes32[](1)
        });

        (, , , bytes32 encodedTrade) = notional.getPrincipalFromfCashBorrow(
            ilkToCurrencyId[ilkId],
            ink,
            ilkToMaturity[ilkId],
            0,
            block.timestamp
        );

        actions[0].trades[0] = encodedTrade;
        notional.batchBalanceAndTradeAction(address(this), actions);

        // buyFyToken
        IPool pool = IPool(ladle.pools(seriesId));
        uint128 tokenToTran = pool.buyFYTokenPreview(borrowAmountPlusFee);
        if (ilkToUnderlying[ilkId] == 0x01) {
            IERC20(USDC).safeTransfer(address(pool), tokenToTran);
        } else {
            // DAI
            IERC20(DAI).safeTransfer(address(pool), tokenToTran);
        }
        pool.buyFYToken(address(this), borrowAmountPlusFee, tokenToTran);
    }

    /// @notice Close a vault after maturity.
    /// @param vaultId The ID of the vault to close.
    /// @param ink The collateral to take from the vault.
    /// @param art The debt to repay. This is denominated in fyTokens, even
    ///     though the payment is done in terms of WEth.
    function doClose(
        bytes12 vaultId,
        uint128 ink,
        uint128 art
    ) internal {
        ladle.close(vaultId, address(this), -int128(ink), -int128(art));
    }

    /// @dev Called by the sender after a transfer to verify it was received. Ensures only `id` tokens are received.
    function onERC1155Received(
        address,
        address,
        uint256 _id,
        uint256,
        bytes calldata
    ) external override returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    /// @dev Called by the sender after a batch transfer to verify it was received. Ensures only `id` tokens are received.
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata _ids,
        uint256[] calldata,
        bytes calldata
    ) external override returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }
}
