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
contract YieldStrategyLever is IERC3156FlashBorrower {
    using TransferHelper for IWETH9;
    using TransferHelper for IERC20;
    using TransferHelper for IFYToken;
    using CastU128I128 for uint128;
    using CastU256U128 for uint256;

    /// @notice The operation to execute in the flash loan.
    ///
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

    mapping(bytes6 => IStrategy) strategies;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    event Invested(
        bytes6 ilkId,
        bytes12 indexed vaultId,
        bytes6 seriesId,
        address indexed investor,
        uint256 amountToInvest,
        uint256 borrowAmount
    );

    event Repaid(
        bytes6 ilkId,
        bytes12 indexed vaultId,
        bytes6 seriesId,
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
        IERC20(USDC).approve(
            address(LADLE.joins(0x303200000000)),
            type(uint256).max
        );
        IERC20(DAI).approve(
            address(LADLE.joins(0x303100000000)),
            type(uint256).max
        );
        IERC20(WETH).approve(
            address(LADLE.joins(0x303000000000)),
            type(uint256).max
        );
    }

    // TODO: add auth when shipping
    /// @notice Sets strategy for different ilks
    /// @param ilkId Id of the ilk
    /// @param strategy Strategy for the ilk
    function setStrategy(bytes6 ilkId, IStrategy strategy) external {
        strategies[ilkId] = strategy;
        IERC20(CAULDRON.assets(ilkId)).approve(
            address(LADLE.joins(ilkId)),
            type(uint256).max
        );
    }

    // TODO: add auth when shipping
    /// @notice Approve maximally for an fyToken.
    /// @param seriesId The id of the pool to approve to.
    function approveFyToken(bytes6 seriesId) external {
        IPool(LADLE.pools(seriesId)).fyToken().approve(
            address(LADLE),
            type(uint256).max
        );
    }

    /// @notice Invest by creating a levered vault. The basic structure is
    ///     always the same. We borrow FyToken for the series and convert it to
    ///     the yield-bearing token that is used as collateral.
    /// @param ilkId The ilkId to invest in. This is often a yield-bearing
    ///     token, for example 0x303400000000 (WStEth).
    /// @param seriesId The series to invest in. This series doesn't usually
    ///     have the ilkId as base, but the asset the yield bearing token is
    ///     based on. For example: 0x303030370000 (WEth) instead of WStEth.
    /// @param amountToInvest The amount of the base to invest. This is denoted
    ///     in terms of the base asset: USDC, DAI, etc.
    /// @param borrowAmount The amount to borrow. This is denoted in terms of
    ///     debt at maturity (and will thus be less before maturity).
    /// @param fyTokenToBuy The amount of fyToken to be bought from the base
    /// @param minCollateral Used for countering slippage. This is the minimum
    ///     amount of collateral that should be locked. The debt is always
    ///     equal to the borrowAmount plus flash loan fees.
    function invest(
        bytes6 ilkId,
        bytes6 seriesId,
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
        (vaultId, ) = LADLE.build(seriesId, ilkId, 0);

        bytes memory data = bytes.concat(
            bytes1(uint8(uint256(Operation.BORROW))), //[0]
            seriesId, //[1:7]
            vaultId, //[7:19]
            ilkId, //[19:25]
            bytes32(amountToInvest), //[25:57]
            bytes32(fyTokenToBuy) //[57:89]
        );
        IFYToken fyToken = IPool(LADLE.pools(seriesId)).fyToken();
        bool success = IERC3156FlashLender(address(fyToken)).flashLoan(
            this, // Loan Receiver
            address(fyToken), // Loan Token
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
            ilkId,
            vaultId,
            seriesId,
            msg.sender,
            amountToInvest,
            borrowAmount
        );
    }

    /// @notice Divest, either before or after maturity.
    /// @param vaultId The vault to divest from.
    /// @param seriesId The series to divest from.
    /// @param ink The amount of collateral to recover.
    /// @param art The amount of debt to repay.
    /// @param minBaseOut Used to minimize slippage. The transaction will revert
    ///     if we don't obtain at least this much of the base asset.
    function divest(
        bytes6 ilkId,
        bytes12 vaultId,
        bytes6 seriesId,
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
            IFYToken fyToken = pool.fyToken();
            // Repay:
            // Series is not past maturity.
            // Borrow to repay debt, move directly to the pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.REPAY)))), // [0:1]
                seriesId, // [1:7]
                vaultId, // [7:19]
                ilkId, // [19:25]
                bytes32(ink), // [25:57]
                bytes32(art) // [57:89]
            );
            success = IERC3156FlashLender(address(fyToken)).flashLoan(
                this, // Loan Receiver
                address(fyToken), // Loan Token
                art, // Loan Amount: borrow exactly the debt to repay.
                data
            );
        } else {
            FlashJoin join = FlashJoin(
                address(LADLE.joins(seriesId & ASSET_ID_MASK))
            );
            IERC20 baseAsset = IERC20(pool.base());
            uint256 depositIntoJoin = baseAsset.balanceOf(address(join)) -
                join.storedBalance();

            // Close:
            // Series is past maturity, borrow and move directly to collateral pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.CLOSE)))), // [0:1]
                seriesId, // [1:7]
                vaultId, // [7:19]
                ilkId, // [19:25]
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

            // At this point, we have only base left.

            // There is however one caveat. If there was base in the join to
            // begin with, this will be billed first. Since we want to return
            // the join to the starting state, we should deposit tokens back.
            // The amount is simply what was in it before, minus what is still
            // in it. The calculation is as `available` in the Join contract.
            depositIntoJoin +=
                join.storedBalance() -
                baseAsset.balanceOf(address(join));
            baseAsset.safeTransfer(address(join), depositIntoJoin);
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
            uint256 baseAmount = uint256(bytes32(data[25:57]));
            uint256 fyTokenToBuy = uint256(bytes32(data[57:89]));
            _borrow(
                ilkId,
                seriesId,
                vaultId,
                baseAmount.u128(),
                borrowAmount,
                fee,
                fyTokenToBuy
            );
        } else {
            uint256 ink = uint256(bytes32(data[25:57]));
            uint256 art = uint256(bytes32(data[57:89]));
            if (status == Operation.REPAY) {
                _repay(
                    ilkId,
                    vaultId,
                    seriesId,
                    (borrowAmount + fee),
                    ink.u128(),
                    art.u128()
                );
            } else if (status == Operation.CLOSE) {
                _close(ilkId, vaultId, ink, art);
            }
        }
    }

    /// @notice This function is called from within the flash loan.
    /// @param ilkId The id of the ilk being borrowed.
    /// @param seriesId The pool (and thereby series) to borrow from.
    /// @param vaultId The vault id to put collateral into and borrow from.
    /// @param baseAmount The amount of own collateral to supply.
    /// @param borrowAmount The amount of FYTOKEN borrowed in the flash loan.
    /// @param fee The fee that will be issued by the flash loan.
    /// @param fyTokenToBuy the amount of fyTokenToBuy from the base.
    function _borrow(
        bytes6 ilkId,
        bytes6 seriesId,
        bytes12 vaultId,
        uint256 baseAmount,
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
        // Mint LP token & deposit to strategy
        pool.mintWithBase(
            address(strategies[ilkId]),
            msg.sender,
            fyTokenToBuy,
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
            tokensMinted.u128().i128(),
            borrowAmount.u128().i128()
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
    function _repay(
        bytes6 ilkId,
        bytes12 vaultId,
        bytes6 seriesId,
        uint256 borrowAmountPlusFee,
        uint256 ink,
        uint256 art
    ) internal {
        IPool pool = IPool(LADLE.pools(seriesId));
        // Payback debt to get back the underlying
        LADLE.pour(
            vaultId,
            address(strategies[ilkId]),
            -ink.u128().i128(),
            -art.u128().i128()
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
            (borrowAmountPlusFee - fyTokens).u128(),
            bases.u128()
        );

        emit Repaid(
            ilkId,
            vaultId,
            seriesId,
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
        uint256 art
    ) internal {
        IStrategy strategy = strategies[ilkId];
        IPool pool = strategy.pool();

        LADLE.close(
            vaultId,
            address(strategy),
            -ink.u128().i128(),
            -art.u128().i128()
        );
        // Burn Strategy Tokens and send LP token to the pool
        strategy.burn(address(pool));
        // Burn LP token to obtain base to repay the flash loan
        pool.burnForBase(address(this), 0, type(uint256).max);

        emit Closed(ilkId, vaultId, msg.sender, ink, art);
    }

    receive() external payable {}
}
