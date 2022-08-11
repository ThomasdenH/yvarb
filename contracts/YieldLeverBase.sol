// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";
import "@yield-protocol/vault-interfaces/src/ILadle.sol";
import "@yield-protocol/vault-interfaces/src/IFYToken.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/vault-v2/utils/Giver.sol";
import "@yield-protocol/vault-v2/FlashJoin.sol";
import "@yield-protocol/vault-v2/Join.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";

error FlashLoanFailure();
error SlippageFailure();

interface Ladle is ILadle {
    function give(bytes12 vaultId_, address receiver)
        external payable
        returns(DataTypes.Vault memory vault);
}

abstract contract YieldLeverBase is IERC3156FlashBorrower {
    using TransferHelper for IWETH9;
    using TransferHelper for IERC20;

    /// @notice The Yield Ladle, the primary entry point for most high-level
    ///     operations.
    Ladle public constant LADLE =
        Ladle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);

    /// @notice The Yield Cauldron, handles debt and collateral balances.
    ICauldron public constant CAULDRON =
        ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);

    /// @notice WEth.
    IWETH9 public constant WETH =
        IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    bytes6 constant ASSET_ID_MASK = 0xFFFF00000000;

    // TODO: Events?
    event LeveredUp();
    event Repaid();
    event Closed();

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

    /// @notice The Giver contract can give vaults on behalf on a user who gave
    ///     permission.
    Giver public immutable giver;

    /// @notice By IERC3156, the flash loan should return this constant.
    bytes32 public constant FLASH_LOAN_RETURN =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(Giver giver_) {
        giver = giver_;
    }

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
    /// @param minCollateral Used for countering slippage. This is the minimum
    ///     amount of collateral that should be locked. The debt is always
    ///     equal to the borrowAmount plus flash loan fees.
    function _invest(
        bytes6 ilkId,
        bytes6 seriesId,
        uint128 amountToInvest,
        uint128 borrowAmount,
        uint128 minCollateral
    ) internal returns (bytes12 vaultId) {
        // TODO: Maybe check whether the series/ilkId is supported

        // Build the vault
        (vaultId, ) = LADLE.build(seriesId, ilkId, 0);

        bytes memory data = bytes.concat(
            bytes1(uint8(uint256(Operation.BORROW))),
            seriesId,
            vaultId,
            ilkId,
            bytes16(amountToInvest)
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

        LADLE.give(vaultId, msg.sender);
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
    /// @param minCollateral Used for countering slippage. This is the minimum
    ///     amount of collateral that should be locked. The debt is always
    ///     equal to the borrowAmount plus flash loan fees.
    function invest(
        bytes6 ilkId,
        bytes6 seriesId,
        uint128 amountToInvest,
        uint128 borrowAmount,
        uint128 minCollateral
    ) external returns (bytes12 vaultId) {
        IPool(LADLE.pools(seriesId)).base().safeTransferFrom(
            msg.sender,
            address(this),
            amountToInvest
        );
        return
            _invest(
                ilkId,
                seriesId,
                amountToInvest,
                borrowAmount,
                minCollateral
            );
    }

    /// @notice Invest by creating a levered vault. The basic structure is
    ///     always the same. We borrow FyToken for the series and convert it to
    ///     the yield-bearing token that is used as collateral.
    ///
    ///     This function will invest Ether, which will be wrapped first. After
    ///     that, the behaviour will be as if wrapped Ether was supplied.
    /// @param ilkId The ilkId to invest in. This is often a yield-bearing
    ///     token, for example 0x303400000000 (WStEth).
    /// @param seriesId The series to invest in. This series doesn't usually
    ///     have the ilkId as base, but the asset the yield bearing token is
    ///     based on. For example: 0x303030370000 (WEth) instead of WStEth.
    /// @param borrowAmount The amount to borrow. This is denoted in terms of
    ///     debt at maturity (and will thus be less before maturity).
    /// @param minCollateral Used for countering slippage. This is the minimum
    ///     amount of collateral that should be locked. The debt is always
    ///     equal to the borrowAmount plus flash loan fees.
    function investEther(
        bytes6 ilkId,
        bytes6 seriesId,
        uint128 borrowAmount,
        uint128 minCollateral
    ) external payable returns (bytes12 vaultId) {
        WETH.deposit{value: msg.value}();
        return
            _invest(
                ilkId,
                seriesId,
                uint128(msg.value),
                borrowAmount,
                minCollateral
            );
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
            uint128 baseAmount = uint128(bytes16(data[25:41]));
            borrow(ilkId, seriesId, vaultId, baseAmount, borrowAmount, fee);
        } else {
            uint128 ink = uint128(bytes16(data[25:41]));
            uint128 art = uint128(bytes16(data[41:57]));
            if (status == Operation.REPAY) {
                repay(
                    ilkId,
                    vaultId,
                    seriesId,
                    uint128(borrowAmount + fee),
                    ink,
                    art
                );
            } else if (status == Operation.CLOSE) {
                close(ilkId, vaultId, ink, art);
            }
        }
    }

    /// @notice Divest, either before or after maturity.
    /// @param vaultId The vault to divest from.
    /// @param seriesId The series to divest from.
    /// @param ink The amount of collateral to recover.
    /// @param art The amount of debt to repay.
    /// @param minOut Used to minimize slippage. The transaction will revert
    ///     if we don't obtain at least this much of the base asset.
    function divest(
        bytes6 ilkId,
        bytes12 vaultId,
        bytes6 seriesId,
        uint128 ink,
        uint128 art,
        uint256 minOut
    ) external {
        _divest(ilkId, vaultId, seriesId, ink, art);
        IERC20 baseAsset = IERC20(IPool(LADLE.pools(seriesId)).base());
        uint256 assetBalance = baseAsset.balanceOf(address(this));
        if (assetBalance < minOut) revert SlippageFailure();
        // Transferring the leftover to the user
        IERC20(baseAsset).safeTransfer(msg.sender, assetBalance);
    }

    /// @notice Divest, either before or after maturity. This function will
    ///     then unwrap WEth.
    /// @param vaultId The vault to divest from.
    /// @param seriesId The series to divest from.
    /// @param ink The amount of collateral to recover.
    /// @param art The amount of debt to repay.
    /// @param minOut Used to minimize slippage. The transaction will revert
    ///     if we don't obtain at least this much of the base asset.
    function divestEther(
        bytes6 ilkId,
        bytes12 vaultId,
        bytes6 seriesId,
        uint128 ink,
        uint128 art,
        uint256 minOut
    ) external {
        _divest(ilkId, vaultId, seriesId, ink, art);
        WETH.withdraw(WETH.balanceOf(address(this)));
        if (address(this).balance < minOut) revert SlippageFailure();
        payable(msg.sender).transfer(address(this).balance);
    }

    receive() external payable {}

    function _divest(
        bytes6 ilkId,
        bytes12 vaultId,
        bytes6 seriesId,
        uint128 ink,
        uint128 art
    ) internal {
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
                ilkId,
                bytes16(ink),
                bytes16(art)
            );
            success = IERC3156FlashLender(address(fyToken)).flashLoan(
                this, // Loan Receiver
                address(fyToken), // Loan Token
                art, // Loan Amount: borrow exactly the debt to repay.
                data
            );
        } else {
            FlashJoin join = FlashJoin(address(LADLE.joins(seriesId & ASSET_ID_MASK)));
            IERC20 baseAsset = IERC20(pool.base());
            uint256 depositIntoJoin = baseAsset.balanceOf(address(join)) - join.storedBalance();

            // Close:
            // Series is past maturity, borrow and move directly to collateral pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.CLOSE)))), // [0:1]
                seriesId, // [1:7]
                vaultId, // [7:19]
                ilkId,
                bytes16(ink),
                bytes16(art)
            );
            // We have a debt in terms of fyWEth, but should pay back in WEth.
            // `base` is how much WEth we should pay back.
            uint128 base = CAULDRON.debtToBase(seriesId, art);
            success = join.flashLoan(
                this, // Loan Receiver
                address(baseAsset), // Loan Token
                base, // Loan Amount
                data
            );

            // At this point, we have only Weth left. Hopefully: this comes
            // from the collateral in our vault!

            // There is however one caveat. If there was Weth in the join to
            // begin with, this will be billed first. Since we want to return
            // the join to the starting state, we should deposit tokens back.
            // The amount is simply what was in it before, minus what is still
            // in it. The calculation is as `available` in the Join contract.
            depositIntoJoin += join.storedBalance() - baseAsset.balanceOf(address(join));
            baseAsset.safeTransfer(address(join), depositIntoJoin);
        }
        if (!success) revert FlashLoanFailure();

        // Give the vault back to the sender, just in case there is anything left
        LADLE.give(vaultId, msg.sender);
    }

    /// @notice We start with base tokens (e.g. Weth, not eWeth) and borrowed
    ///     fyTokens. We need to sell the fyTokens and then convert all to the
    ///     yield-bearing tokens.
    function borrow(
        bytes6 ilkId,
        bytes6 seriesId,
        bytes12 vaultId,
        uint128 baseAmount,
        uint256 borrowAmount,
        uint256 fee
    ) internal virtual;

    /// @notice The series is pre-maturity. We have borrowed art FyTokens. We
    ///     should use it to repay the vault and take out ink collateral. This
    ///     collateral should be converted to FyTokens to repay the flash loan
    ///     exactly, and the rest should be converted to the base. It will then
    ///     be sent to the borrower by this contract.
    function repay(
        bytes6 ilkId,
        bytes12 vaultId,
        bytes6 seriesId,
        uint128 borrowAmountPlusFee, // Amount of FYToken received
        uint128 ink,
        uint128 art
    ) internal virtual;

    /// @notice The series is post-maturity. We have borrowed the base, which
    ///     is exactly enough to pay back the vault debt. We should convert the
    ///     collateral to base to repay the loan. The leftover will be sent to
    ///     the vault owner.
    function close(
        bytes6 ilkId,
        bytes12 vaultId,
        uint128 ink,
        uint128 art
    ) internal virtual;
}
