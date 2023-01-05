// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "@yield-protocol/utils-v2/contracts/cast/CastU128I128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastI128U128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I256.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "./interfaces/IEulerMarkets.sol";
import "./interfaces/IEulerEToken.sol";
import "./YieldLeverBase.sol";
import "forge-std/console.sol";

/// @title A simple euler lever designed to work for one euler token & its underlying at a time
/// @author iamsahu
/// @notice Working:
///         - Get flash loan of USDC/DAI/WETH
///         - Deposit to get eulerToken
///         - Deposit & borrow against it
///         - Sell the fyToken to get USDC/DAI/WETH
///         - Close the flash loan
contract YieldEulerLever is YieldLeverBase {
    using TransferHelper for IERC20;
    using CastU128I128 for uint128;
    using CastI128U128 for int128;
    using CastU256U128 for uint256;
    using CastU256I256 for uint256;

    /// @notice euler market
    IEulerMarkets public constant eulerMarkets =
        IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
    /// @notice Euler protocol address
    address constant euler = 0x27182842E098f60e3D576794A5bFFb0777E025d3;

    struct ETokenInfo {
        IEulerEToken eToken;
        FlashJoin join;
    }

    mapping(bytes6 => ETokenInfo) public eTokenInfo;

    constructor(Giver giver_) YieldLeverBase(giver_) {}

    /// @notice Invest by creating a levered vault.
    /// @param seriesId The series to create the vault for.
    /// @param amountToInvest The amount of own eToken to supply as collateral.
    /// @param borrowAmount The amount of additional liquidity to borrow.
    /// @param minCollateral The minimum amount of collateral to end up with in
    ///     the vault. If this requirement is not satisfied, the transaction
    ///     will revert.
    // +-------+                                            +-------+                                                  +-------+ +-------------+ +-------+ +-------+
    // | User  |                                            | Lever |                                                  | Join  | | eulerMarket | | Ladle | | Pool  |
    // +-------+                                            +-------+                                                  +-------+ +-------------+ +-------+ +-------+
    //     |                                                    |                                                          |            |            |         |
    //     | invest x amount & borrow y amount                  |                                                          |            |            |         |
    //     |--------------------------------------------------->|                                                          |            |            |         |
    //     |                                                    |                                                          |            |            |         |
    //     | transfer x amount of eToken from user to lever     |                                                          |            |            |         |
    //     |--------------------------------------------------->|                                                          |            |            |         |
    //     |                                                    |                                                          |            |            |         |
    //     |                                                    | Build a vault                                            |            |            |         |
    //     |                                                    |----------------------------------------------------------------------------------->|         |
    //     |                                                    |                                                          |            |            |         |
    //     |                                                    | borrow y amount using flashLoan from underlying join     |            |            |         |
    //     |                                                    |--------------------------------------------------------->|            |            |         |
    //     |                                                    |                                                          |            |            |         |
    //     |                                                    | Deposit y token                                          |            |            |         |
    //     |                                                    |---------------------------------------------------------------------->|            |         |
    //     |                                                    |                                                          |            |            |         |
    //     |                                                    |                                                       Transfer eToken |            |         |
    //     |                                                    |<----------------------------------------------------------------------|            |         |
    //     |                                                    |                                                          |            |            |         |
    //     |                                                    | pour x+y to borrow y fyToken                             |            |            |         |
    //     |                                                    |----------------------------------------------------------------------------------->|         |
    //     |                                                    |                                                          |            |            |         |
    //     |                                                    | sell y to get underlying to payback the flashloan        |            |            |         |
    //     |                                                    |--------------------------------------------------------------------------------------------->|
    //     |                                                    |                                                          |            |            |         |
    //     |                Transfer the vault back to the user |                                                          |            |            |         |
    //     |<---------------------------------------------------|                                                          |            |            |         |
    //     |                                                    |                                                          |            |            |         |
    function invest(
        bytes6 seriesId,
        bytes6 ilkId,
        uint256 amountToInvest,
        uint256 borrowAmount,
        uint256 minCollateral
    ) external returns (bytes12 vaultId) {
        if (eTokenInfo[ilkId].eToken == IEulerEToken(address(0))) {
            bytes6 baseId = cauldron.series(seriesId).baseId;
            ETokenInfo storage info = eTokenInfo[ilkId];
            info.eToken = IEulerEToken(
                eulerMarkets.underlyingToEToken(cauldron.assets(baseId))
            );
            info.join = FlashJoin(address(ladle.joins(baseId)));
            IERC20(info.join.asset()).approve(euler, type(uint256).max);
        }
        // Transfer the tokens from user based on the ilk
        IERC20(address(eTokenInfo[ilkId].eToken)).safeTransferFrom(
            msg.sender,
            address(this),
            amountToInvest
        );

        // Build vault
        (vaultId, ) = ladle.build(seriesId, ilkId, 0);

        // Encode data of
        // OperationType    1 byte      [0:1]
        // seriesId         6 bytes     [1:7]
        // vaultId          12 bytes    [7:19]
        // amountToInvest       32 bytes    [19:51]
        // minCollateral    32 bytes    [51:83]
        bytes memory data = bytes.concat(
            bytes1(uint8(uint256(Operation.BORROW))),
            seriesId,
            ilkId,
            vaultId,
            bytes32(amountToInvest),
            bytes32(minCollateral)
        );

        bool success = eTokenInfo[ilkId].join.flashLoan(
            this, // Loan Receiver
            eTokenInfo[ilkId].join.asset(), // Loan Token
            borrowAmount, // Loan Amount
            data
        );

        if (!success) revert FlashLoanFailure();
        giver.give(vaultId, msg.sender);
    }

    /// @notice divest a position.
    ///
    ///     If pre maturity, borrow liquidity tokens to repay `art` debt and
    ///     take `ink` collateral.
    ///
    ///     If post maturity, borrow USDC/DAI/ETH to pay off the debt directly.
    ///
    ///     This function will take the vault from the user, using `Giver`, so make
    ///     sure you have given it permission to do that.
    /// @param seriesId The seriesId corresponding to the vault.
    /// @param vaultId The vault to use.
    /// @param ink The amount of collateral to recover.
    /// @param art The debt to repay.
    /// @dev It is more gas efficient to let the user supply the `seriesId`,
    ///     but it should match the pool.
    function divest(
        bytes12 vaultId,
        bytes6 seriesId,
        bytes6 ilkId,
        uint256 ink,
        uint256 art
    ) external {
        // Test that the caller is the owner of the vault.
        // This is important as we will take the vault from the user.
        require(cauldron.vaults(vaultId).owner == msg.sender);

        // Give the vault to the contract
        giver.seize(vaultId, address(this));

        // Check if we're pre or post maturity.
        if (uint32(block.timestamp) < cauldron.series(seriesId).maturity) {
            IMaturingToken fyToken = IPool(ladle.pools(seriesId)).fyToken();
            // Close:
            // Series is not past maturity.
            // Borrow to repay debt, move directly to the pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.REPAY)))), // [0:1]
                seriesId, // [1:7]
                ilkId,
                vaultId, // [7:19]
                bytes32(ink), // [19:51]
                bytes32(art) // [51:83]
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
            // Series is past maturity.
            // Borrow to repay debt, move directly to the pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.CLOSE)))), // [0:1]
                seriesId, // [1:7]
                ilkId, // [7:13]
                vaultId, // [13:25]
                bytes32(ink), // [25:57]
                bytes32(art) // [57:89]
            );

            bool success = eTokenInfo[ilkId].join.flashLoan(
                this, // Loan Receiver
                eTokenInfo[ilkId].join.asset(), // Loan Token
                art, // Loan Amount
                data
            );

            if (!success) revert FlashLoanFailure();
            uint256 balance = IERC20(eTokenInfo[ilkId].join.asset()).balanceOf(
                address(this)
            );

            if (balance > 0)
                IERC20(eTokenInfo[ilkId].join.asset()).safeTransfer(
                    msg.sender,
                    balance
                );
        }

        // Give the vault back to the sender, just in case there is anything left
        giver.give(vaultId, msg.sender);
    }

    /// @notice Callback for the flash loan.
    /// @dev Used as a router to the correct function based
    ///      on the operation present in the data.
    function onFlashLoan(
        address initiator,
        address token,
        uint256 borrowAmount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        Operation status = Operation(uint256(uint8(data[0])));
        bytes6 seriesId = bytes6(data[1:7]);
        bytes6 ilkId = bytes6(data[7:13]);
        bytes12 vaultId = bytes12(data[13:25]);
        uint256 baseAmount = uint256(bytes32(data[25:57]));
        uint256 minCollateral = uint256(bytes32(data[57:89]));
        IPool pool = IPool(ladle.pools(seriesId));

        // Test that the lender is either a fyToken contract or the join.
        if (
            msg.sender != address(pool.fyToken()) &&
            msg.sender != address(ladle.joins(cauldron.series(seriesId).baseId))
        ) revert FlashLoanFailure();
        // We trust the lender, so now we can check that we were the initiator.
        if (initiator != address(this)) revert FlashLoanFailure();

        // Decode the operation to execute and then call that function.
        if (status == Operation.BORROW) {
            IERC20(token).safeApprove(msg.sender, borrowAmount + fee);
            _borrow(
                vaultId,
                ilkId,
                ladle.pools(seriesId),
                borrowAmount,
                fee,
                minCollateral
            );
        } else if (status == Operation.REPAY) {
            IERC20(token).safeApprove(msg.sender, borrowAmount + fee);
            _repay(
                vaultId,
                seriesId,
                ilkId,
                address(pool),
                uint256(borrowAmount + fee),
                baseAmount,
                minCollateral
            );
        } else if (status == Operation.CLOSE) {
            IERC20(token).safeApprove(msg.sender, 2 * borrowAmount + fee);
            _close(vaultId, ilkId, baseAmount, minCollateral);
        }

        return FLASH_LOAN_RETURN;
    }

    /// @notice This function is called from within the flash loan. The high
    ///     level functionality is as follows:
    ///         - We have supplied and borrowed underlying asset.
    ///         - We deposit it to euler and put the etoken received in the vault.
    ///         - Against it, we borrow enough fyToken to sell & repay the flash loan.
    /// @param poolAddress The pool (and thereby series) to borrow from.
    /// @param vaultId The vault id to put collateral into and borrow from.
    /// @param ilkId Id of the Ilk
    /// @param borrow The amount of underlying asset borrowed in the flash loan.
    /// @param fee The fee that will be issued by the flash loan.
    /// @param minCollateral The final amount of collateral to end up with, or
    ///     the function will revert. Used to prevent slippage.
    function _borrow(
        bytes12 vaultId,
        bytes6 ilkId,
        address poolAddress,
        uint256 borrow,
        uint256 fee,
        uint256 minCollateral
    ) internal {
        // Deposit to get Euler token in return which would be used to payback flashloan
        IEulerEToken eToken = eTokenInfo[ilkId].eToken;
        eToken.deposit(0, borrow - fee);

        uint256 eBalance = IERC20(address(eToken)).balanceOf(address(this));

        IERC20(address(eToken)).safeApprove(
            address(ladle.joins(ilkId)),
            eBalance
        );

        _pourAndSell(vaultId, poolAddress, eBalance, borrow);
    }

    /// @dev Additional function to get over stack too deep
    /// @param vaultId VaultId
    /// @param poolAddress Address of the pool to trade on
    /// @param ink Amount of collateral
    /// @param borrow Amount being borrowed
    function _pourAndSell(
        bytes12 vaultId,
        address poolAddress,
        uint256 ink,
        uint256 borrow
    ) internal {
        IPool pool = IPool(poolAddress);
        uint128 fyBorrow = pool.buyBasePreview(borrow.u128());
        ladle.pour(vaultId, address(pool), ink.u128().i128(), fyBorrow.i128());
        pool.buyBase(address(this), borrow.u128(), fyBorrow);
    }

    /// @param vaultId The vault to repay.
    /// @param poolAddress The address of the pool.
    /// @param borrowPlusFee The amount of fyToken that we have borrowed,
    ///     plus the fee. This should be our final balance.
    /// @param ink The amount of collateral to retake.
    /// @param art The debt to repay.
    ///     slippage.
    function _repay(
        bytes12 vaultId,
        bytes6 seriesId,
        bytes6 ilkId,
        address poolAddress,
        uint256 borrowPlusFee, // Amount of FYToken received
        uint256 ink,
        uint256 art
    ) internal {
        // Repay the vault, get collateral back.
        cauldron.series(seriesId).fyToken.approve(address(ladle), art);
        ladle.pour(
            vaultId,
            address(this),
            -ink.u128().i128(),
            -art.u128().i128()
        );

        eTokenInfo[ilkId].eToken.withdraw(0, type(uint256).max);

        IPool pool = IPool(poolAddress);
        // buyFyToken
        uint128 tokensTransferred = pool.buyFYTokenPreview(
            borrowPlusFee.u128()
        );

        IERC20(eTokenInfo[ilkId].join.asset()).safeTransfer(
            poolAddress,
            tokensTransferred
        );

        pool.buyFYToken(address(this), borrowPlusFee.u128(), tokensTransferred);
    }

    /// @notice Close a vault after maturity.
    /// @param vaultId The ID of the vault to close.
    /// @param ink The collateral to take from the vault.
    /// @param art The debt to repay. This is denominated in fyTokens, even
    ///     though the payment is done in terms of underlying.
    function _close(
        bytes12 vaultId,
        bytes6 ilkId,
        uint256 ink,
        uint256 art
    ) internal {
        ladle.close(
            vaultId,
            address(this),
            -ink.u128().i128(),
            -art.u128().i128()
        );

        eTokenInfo[ilkId].eToken.withdraw(0, type(uint256).max);
    }
}
