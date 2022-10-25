// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./interfaces/IStrategy.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU128I128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/ILadle.sol";
import "@yield-protocol/vault-interfaces/src/IFYToken.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/vault-v2/utils/Giver.sol";
import "@yield-protocol/vault-v2/FlashJoin.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";

error FlashLoanFailure();
error SlippageFailure();

/// @notice This contracts allows a user to 'lever up' their StrategyToken position.
///     Levering up happens as follows:
///     1. FlashBorrow fyToken
///     2. Sell fyToken to get base (USDC/DAI/ETH)
///     3. Mint LP token & deposit to strategy
///     4. Mint strategy token
///     5. Put strategy token as a collateral to borrow fyToken to repay flash loan
///
///     To get out of the levered position depending on whether we are past maturity the following happens:
///     1. Before maturity
///         i. FlashBorrow fyToken
///         ii. Payback the debt to get back the underlying
///         iii. Burn the strategy token to get LP
///         iv. Burn LP to get base & fyToken
///         v. Buy fyToken using the base to repay the flash loan
///     2. After maturity
///         i. FlashBorrow base
///         ii. Close the debt position using the base
///         iii. Burn the strategy token received from closing the position to get LP token
///         iv. Burn LP token to obtain base to repay the flash loan
/// @notice For leveringup we could flash borrow base instead of fyToken as well
/// @author iamsahu
contract YieldStrategyLever is IERC3156FlashBorrower {
    using TransferHelper for IWETH9;
    using TransferHelper for IERC20;
    using TransferHelper for IFYToken;
    using CastU128I128 for uint128;
    using CastU256U128 for uint256;

    /// @notice The operation to execute in the flash loan.
    ///     - BORROW: Invest
    ///     - REPAY: Unwind before maturity
    ///     - CLOSE: Unwind after maturity
    enum Operation {
        BORROW,
        REPAY,
        CLOSE
    }

    /// @notice By IERC3156, the flash loan should return this constant.
    bytes32 public constant FLASH_LOAN_RETURN =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    bytes6 constant ASSET_ID_MASK = 0xFFFF00000000;

    /// @notice The Yield Cauldron, handles debt and collateral balances.
    ICauldron public constant CAULDRON =
        ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);

    /// @notice The Yield Ladle, the primary entry point for most high-level
    ///     operations.
    ILadle public constant LADLE =
        ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);

    /// @notice The Giver contract can give vaults on behalf on a user who gave
    ///     permission.
    Giver public immutable giver;

    event Invested(
        bytes12 indexed vaultId,
        bytes6 seriesId,
        bytes6 ilkId,
        address indexed investor,
        uint256 amountToInvest,
        uint256 borrowAmount
    );

    event Repaid(
        bytes12 indexed vaultId,
        bytes6 seriesId,
        bytes6 ilkId,
        address indexed investor,
        uint256 borrowAmountPlusFee,
        uint256 ink,
        uint256 art
    );

    event Closed(
        bytes6 ilkId,
        bytes12 indexed vaultId,
        address indexed investor,
        uint256 ink,
        uint256 art
    );

    constructor(Giver giver_) {
        giver = giver_;
    }

    /// @notice Invest by creating a levered vault. The basic structure is
    ///     always the same. We borrow FyToken for the series and convert it to
    ///     the yield-bearing token that is used as collateral.
    /// @param seriesId The series to invest in. This series doesn't usually
    ///     have the ilkId as base, but the asset the yield bearing token is
    ///     based on. For example: 0x303030370000 (WEth) instead of WStEth.
    /// @param strategyId The strategyId to invest in. This is often a yield-bearing
    ///     token, for example 0x303400000000 (WStEth).
    /// @param amountToInvest The amount of the base to invest. This is denoted
    ///     in terms of the base asset: USDC, DAI, etc.
    /// @param borrowAmount The amount to borrow. This is denoted in terms of
    ///     debt at maturity (and will thus be less before maturity).
    /// @param fyTokenToBuy The amount of fyToken to be bought from the base
    /// @param minCollateral Used for countering slippage. This is the minimum
    ///     amount of collateral that should be locked. The debt is always
    ///     equal to the borrowAmount plus flash loan fees.
    function invest(
        bytes6 seriesId,
        bytes6 strategyId,
        uint256 amountToInvest,
        uint256 borrowAmount,
        uint256 fyTokenToBuy,
        uint256 minCollateral
    ) external returns (bytes12 vaultId) {
        IPool(LADLE.pools(seriesId)).base().safeTransferFrom(
            msg.sender,
            address(this),
            amountToInvest
        );
        // Build the vault
        (vaultId, ) = LADLE.build(seriesId, strategyId, 0);

        bytes memory data = bytes.concat(
            bytes1(uint8(uint256(Operation.BORROW))), //[0]
            seriesId, //[1:7]
            vaultId, //[7:19]
            strategyId, //[19:25]
            bytes32(fyTokenToBuy) //[25:57]
        );
        address fyToken = address(IPool(LADLE.pools(seriesId)).fyToken());

        bool success = IERC3156FlashLender(fyToken).flashLoan(
            this, // Loan Receiver
            fyToken, // Loan Token
            borrowAmount, // Loan Amount
            data
        );

        if (!success) revert FlashLoanFailure();

        // This is the amount to deposit, so we check for slippage here. As
        // long as we end up with the desired amount, it doesn't matter what
        // slippage occurred where.
        if (CAULDRON.balances(vaultId).ink < minCollateral)
            revert SlippageFailure();

        giver.give(vaultId, msg.sender);

        emit Invested(
            vaultId,
            seriesId,
            strategyId,
            msg.sender,
            amountToInvest,
            borrowAmount
        );
    }

    /// @notice Divest, either before or after maturity.
    /// @param vaultId The vault to divest from.
    /// @param seriesId The series to divest from.
    /// @param strategyId The strategyId to invest in. This is often a yield-bearing
    /// @param ink The amount of collateral to recover.
    /// @param art The amount of debt to repay.
    /// @param minBaseOut Used to minimize slippage. The transaction will revert
    ///     if we don't obtain at least this much of the base asset.
    function divest(
        bytes12 vaultId,
        bytes6 seriesId,
        bytes6 strategyId,
        uint256 ink,
        uint256 art,
        uint256 minBaseOut
    ) external {
        // Test that the caller is the owner of the vault.
        // This is important as we will take the vault from the user.
        require(CAULDRON.vaults(vaultId).owner == msg.sender);

        // Give the vault to the contract
        giver.seize(vaultId, address(this));

        IPool pool = IPool(LADLE.pools(seriesId));

        // Check if we're pre or post maturity.
        bool success;
        if (uint32(block.timestamp) < CAULDRON.series(seriesId).maturity) {
            address fyToken = address(pool.fyToken());
            // Repay:
            // Series is not past maturity.
            // Borrow to repay debt, move directly to the pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.REPAY)))), // [0:1]
                seriesId, // [1:7]
                vaultId, // [7:19]
                strategyId, // [19:25]
                bytes32(ink), // [25:57]
                bytes32(art) // [57:89]
            );
            success = IERC3156FlashLender(fyToken).flashLoan(
                this, // Loan Receiver
                fyToken, // Loan Token
                art, // Loan Amount: borrow exactly the debt to repay.
                data
            );
        } else {
            FlashJoin join = FlashJoin(
                address(LADLE.joins(seriesId & ASSET_ID_MASK))
            );
            IERC20 baseAsset = IERC20(pool.base());

            // Close:
            // Series is past maturity, borrow and move directly to collateral pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.CLOSE)))), // [0:1]
                seriesId, // [1:7]
                vaultId, // [7:19]
                strategyId, // [19:25]
                bytes32(ink), // [25:57]
                bytes32(art) // [57:89]
            );
            // We have a debt in terms of fyToken, but should pay back in base.
            uint128 base = CAULDRON.debtToBase(seriesId, art.u128());
            success = join.flashLoan(
                this, // Loan Receiver
                address(baseAsset), // Loan Token
                base, // Loan Amount
                data
            );
        }
        if (!success) revert FlashLoanFailure();

        // Give the vault back to the sender, just in case there is anything left
        giver.give(vaultId, msg.sender);
        IERC20 baseAsset = IERC20(IPool(LADLE.pools(seriesId)).base());
        uint256 assetBalance = baseAsset.balanceOf(address(this));
        if (assetBalance < minBaseOut) revert SlippageFailure();
        // Transferring the leftover to the user
        IERC20(baseAsset).safeTransfer(msg.sender, assetBalance);
    }

    /// @notice Called by a flash lender. The primary purpose is to check
    ///     conditions and route to the correct internal function.
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
    ) external override returns (bytes32 returnValue) {
        returnValue = FLASH_LOAN_RETURN;
        Operation status = Operation(uint256(uint8(data[0])));
        bytes6 seriesId = bytes6(data[1:7]);
        bytes12 vaultId = bytes12(data[7:19]);
        bytes6 ilkId = bytes6(data[19:25]);

        // Test that the lender is either a fyToken contract or the join.
        if (
            msg.sender != address(IPool(LADLE.pools(seriesId)).fyToken()) &&
            msg.sender != address(LADLE.joins(seriesId & ASSET_ID_MASK))
        ) revert FlashLoanFailure();
        // We trust the lender, so now we can check that we were the initiator.
        if (initiator != address(this)) revert FlashLoanFailure();

        // Decode the operation to execute and then call that function.
        if (status == Operation.BORROW) {
            uint256 fyTokenToBuy = uint256(bytes32(data[25:57]));
            _borrow(vaultId, seriesId, ilkId, borrowAmount, fee, fyTokenToBuy);
        } else {
            uint256 ink = uint256(bytes32(data[25:57]));
            uint256 art = uint256(bytes32(data[57:89]));
            if (status == Operation.REPAY) {
                _repay(
                    vaultId,
                    seriesId,
                    ilkId,
                    (borrowAmount + fee),
                    ink.u128(),
                    art.u128()
                );
            } else if (status == Operation.CLOSE) {
                bytes6 seriesId = CAULDRON.vaults(vaultId).seriesId;
                IPool pool = IPool(LADLE.pools(seriesId));
                // Approving the join to pull required amount of token to close the position & the flash loan
                pool.base().approve(
                    address(LADLE.joins(seriesId & ASSET_ID_MASK)),
                    2 * art + fee
                );
                _close(ilkId, vaultId, ink, art, pool);
            }
        }
    }

    /// @notice The function does the following to create a leveraged position:
    ///         1. Sells the flash loaned fyToken to get base
    ///         2. Add the base as liquidity to obtain LP tokens
    ///         3. Deposit LP tokens in strategy to obtain strategy token
    ///         4. Finally use the Strategy tokens to borrow fyToken to repay the flash loan
    /// @param vaultId The vault id to put collateral into and borrow from.
    /// @param seriesId The pool (and thereby series) to borrow from.
    /// @param ilkId The id of the ilk being borrowed.
    /// @param borrowAmount The amount of FYTOKEN borrowed in the flash loan.
    /// @param fee The fee that will be issued by the flash loan.
    /// @param fyTokenToBuy the amount of fyTokenToBuy from the base.
    function _borrow(
        bytes12 vaultId,
        bytes6 seriesId,
        bytes6 ilkId,
        uint256 borrowAmount,
        uint256 fee,
        uint256 fyTokenToBuy
    ) internal {
        // We have borrowed FyTokens, so sell those
        IPool pool = IPool(LADLE.pools(seriesId));
        IFYToken fyToken = pool.fyToken();
        fyToken.safeTransfer(address(pool), borrowAmount - fee);
        pool.sellFYToken(address(pool), 0); // Sell fyToken to get USDC/DAI/ETH
        pool.base().transfer(
            address(pool),
            pool.base().balanceOf(address(this))
        );
        address strategyAddress = CAULDRON.assets(ilkId);
        // Mint LP token & deposit to strategy
        pool.mintWithBase(
            strategyAddress,
            msg.sender,
            fyTokenToBuy,
            0,
            type(uint256).max
        );

        // Mint strategy token
        uint256 tokensMinted = IStrategy(strategyAddress).mint(
            address(LADLE.joins(ilkId))
        );

        // Borrow fyToken to repay the flash loan
        LADLE.pour(
            vaultId,
            address(this),
            tokensMinted.u128().i128(),
            borrowAmount.u128().i128()
        );
    }

    /// @param vaultId The vault to repay.
    /// @param seriesId The seriesId corresponding to the vault.
    /// @param ilkId The id of the ilk being invested.
    /// @param borrowAmountPlusFee The amount of fyDai/fyUsdc that we have borrowed,
    ///     plus the fee. This should be our final balance.
    /// @param ink The amount of collateral to retake.
    /// @param art The debt to repay.
    ///     slippage.
    function _repay(
        bytes12 vaultId,
        bytes6 seriesId,
        bytes6 ilkId,
        uint256 borrowAmountPlusFee,
        uint256 ink,
        uint256 art
    ) internal {
        IPool pool = IPool(LADLE.pools(seriesId));
        address strategy = CAULDRON.assets(ilkId);

        // Approving the Ladle to pull required amount of tokens from the lever before pouring
        CAULDRON.series(seriesId).fyToken.approve(address(LADLE), ink);
        // Payback debt to get back the underlying
        LADLE.pour(vaultId, strategy, -ink.u128().i128(), -art.u128().i128());

        // Burn strat token to get LP
        IStrategy(strategy).burn(address(pool));

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
            (borrowAmountPlusFee - fyTokens).u128(),
            bases.u128()
        );

        emit Repaid(
            vaultId,
            seriesId,
            ilkId,
            msg.sender,
            borrowAmountPlusFee,
            ink,
            art
        );
    }

    /// @notice Close a vault after maturity.
    /// @param ilkId The id of the ilk.
    /// @param vaultId The ID of the vault to close.
    /// @param ink The collateral to take from the vault.
    /// @param art The debt to repay. This is denominated in fyTokens
    function _close(
        bytes6 ilkId,
        bytes12 vaultId,
        uint256 ink,
        uint256 art,
        IPool pool
    ) internal {
        address strategy = CAULDRON.assets(ilkId);

        LADLE.close(vaultId, strategy, -ink.u128().i128(), -art.u128().i128());
        // Burn Strategy Tokens and send LP token to the pool
        IStrategy(strategy).burn(address(pool));
        // Burn LP token to obtain base to repay the flash loan
        pool.burnForBase(address(this), 0, type(uint256).max);

        emit Closed(ilkId, vaultId, msg.sender, ink, art);
    }

    receive() external payable {}
}
