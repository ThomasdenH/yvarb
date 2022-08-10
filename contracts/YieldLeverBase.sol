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
import "forge-std/Test.sol";

error FlashLoanFailure();
error SlippageFailure();

abstract contract YieldLeverBase is IERC3156FlashBorrower, Test {
    using TransferHelper for IWETH9;
    using TransferHelper for IERC20;

    /// @notice The Yield Ladle, the primary entry point for most high-level
    ///     operations.
    ILadle public constant ladle =
        ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    /// @notice The Yield Cauldron, handles debt and collateral balances.
    ICauldron public constant cauldron =
        ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    
    /// @notice WEth.
    IWETH9 public constant weth =
        IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    bytes6 ASSET_ID_MASK = 0xFFFF00000000;

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
        IPool(ladle.pools(seriesId)).fyToken().approve(
            address(ladle),
            type(uint256).max
        );
    }

    /// @notice Invest by creating a levered vault. The basic structure is
    ///     always the same. We borrow FyToken for the series and convert it to
    ///     the yield-bearing token that is used as collateral.
    function _invest(
        bytes6 ilkId,
        bytes6 seriesId,
        uint128 amountToInvest,
        uint128 borrowAmount,
        uint128 minCollateral
    ) internal returns (bytes12 vaultId) {
        // TODO: Maybe check whether the series/ilkId is supported
        // The pool to invest into.
        IPool pool = IPool(ladle.pools(seriesId));
        IFYToken fyToken = pool.fyToken();

        // Build the vault
        // TODO: ilkId
        (vaultId, ) = ladle.build(seriesId, ilkId, 0);

        bytes memory data = bytes.concat(
            bytes1(uint8(uint256(Operation.BORROW))),
            seriesId,
            vaultId,
            bytes16(amountToInvest),
            bytes16(minCollateral)
        );
        bool success = IERC3156FlashLender(address(fyToken)).flashLoan(
            this, // Loan Receiver
            address(fyToken), // Loan Token
            borrowAmount, // Loan Amount
            data
        );
        if (!success) revert FlashLoanFailure();
        giver.give(vaultId, msg.sender);
    }

    function invest(
        bytes6 ilkId,
        bytes6 seriesId,
        uint128 amountToInvest,
        uint128 borrowAmount,
        uint128 minCollateral
    ) external returns (bytes12 vaultId) {
        return _invest(ilkId, seriesId, amountToInvest, borrowAmount, minCollateral);
    }

    function investEther(
        bytes6 ilkId,
        bytes6 seriesId,
        uint128 borrowAmount,
        uint128 minCollateral
    ) external payable returns (bytes12 vaultId) {
        weth.deposit{ value: msg.value }();
        return _invest(ilkId, seriesId, uint128(msg.value), borrowAmount, minCollateral);
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
    ) external override returns (bytes32) {
        Operation status = Operation(uint256(uint8(data[0])));
        bytes6 seriesId = bytes6(data[1:7]);
        bytes12 vaultId = bytes12(data[7:19]);
        {
            IFYToken fyToken = IPool(ladle.pools(seriesId)).fyToken();
            // Test that the lender is either a fyToken contract or the join.
            bytes6 assetId = seriesId & ASSET_ID_MASK;
            IJoin join = ladle.joins(assetId);
            if (msg.sender != address(fyToken) && msg.sender != address(join))
                revert FlashLoanFailure();
            // We trust the lender, so now we can check that we were the initiator.
            if (initiator != address(this)) revert FlashLoanFailure();
        }

        // Decode the operation to execute and then call that function.
        if (status == Operation.BORROW) {
            uint128 baseAmount = uint128(uint128(bytes16(data[19:35])));
            uint256 minCollateral = uint128(bytes16(data[35:51]));
            borrow(
                seriesId,
                vaultId,
                baseAmount,
                borrowAmount,
                fee,
                minCollateral
            );
        } else if (status == Operation.REPAY) {
            repay(vaultId, seriesId, uint128(borrowAmount + fee), data);
        } else if (status == Operation.CLOSE) {
            uint128 ink = uint128(bytes16(data[19:35]));
            uint128 art = uint128(bytes16(data[35:51]));
            close(vaultId, ink, art);
        }
        return FLASH_LOAN_RETURN;
    }

    function divest(
        bytes12 vaultId,
        bytes6 seriesId,
        uint128 ink,
        uint128 art,
        uint256 minOut
    ) external {
        _divest(vaultId, seriesId, ink, art);
        IPool pool = IPool(ladle.pools(seriesId));
        IERC20 baseAsset = IERC20(pool.base());
        uint256 assetBalance = baseAsset.balanceOf(address(this));
        if (assetBalance < minOut) revert SlippageFailure();
        // Transferring the leftover to the user
        IERC20(baseAsset).safeTransfer(msg.sender, assetBalance);
    }

    function divestEther(
        bytes12 vaultId,
        bytes6 seriesId,
        uint128 ink,
        uint128 art,
        uint256 minOut
    ) external {
        _divest(vaultId, seriesId, ink, art);
        uint256 assetBalance = weth.balanceOf(address(this));
        if (assetBalance < minOut) revert SlippageFailure();
        weth.withdraw(assetBalance);
        payable(msg.sender).transfer(assetBalance);
    }

    receive() external payable {}

    function _divest(
        bytes12 vaultId,
        bytes6 seriesId,
        uint128 ink,
        uint128 art
    ) internal {
        // Test that the caller is the owner of the vault.
        // This is important as we will take the vault from the user.
        require(cauldron.vaults(vaultId).owner == msg.sender);

        // Give the vault to the contract
        giver.seize(vaultId, address(this));

        IPool pool = IPool(ladle.pools(seriesId));
        IERC20 baseAsset = IERC20(pool.base());

        // Check if we're pre or post maturity.
        if (uint32(block.timestamp) < cauldron.series(seriesId).maturity) {
            IFYToken fyToken = pool.fyToken();
            // Repay:
            // Series is not past maturity.
            // Borrow to repay debt, move directly to the pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.REPAY)))), // [0:1]
                seriesId, // [1:7]
                vaultId, // [7:19]
                bytes16(ink), // [19:35]
                bytes16(art), // [35:51]
                bytes20(msg.sender) // [51:71]
            );
            bool success = IERC3156FlashLender(address(fyToken)).flashLoan(
                this, // Loan Receiver
                address(fyToken), // Loan Token
                art, // Loan Amount: borrow exactly the debt to repay.
                data
            );
            if (!success) revert FlashLoanFailure();
        } else {
            bytes6 assetId = seriesId & ASSET_ID_MASK;
            FlashJoin join = FlashJoin(address(ladle.joins(assetId)));
            uint256 availableInJoin = baseAsset.balanceOf(address(join)) - join.storedBalance();

            // Close:
            // Series is past maturity, borrow and move directly to collateral pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.CLOSE)))), // [0:1]
                seriesId, // [1:7]
                vaultId, // [7:19]
                bytes16(ink), // [19:35]
                bytes16(art) // [35:51]
            );
            // We have a debt in terms of fyWEth, but should pay back in WEth.
            // `base` is how much WEth we should pay back.
            uint128 base = cauldron.debtToBase(seriesId, art);
            bool success = join.flashLoan(
                this, // Loan Receiver
                address(baseAsset), // Loan Token
                base, // Loan Amount
                data
            );
            if (!success) revert FlashLoanFailure();

            // At this point, we have only Weth left. Hopefully: this comes
            // from the collateral in our vault!

            // There is however one caveat. If there was Weth in the join to
            // begin with, this will be billed first. Since we want to return
            // the join to the starting state, we should deposit Weth back.
            uint256 assetToDeposit = availableInJoin
                - (baseAsset.balanceOf(address(join)) - join.storedBalance());
            baseAsset.safeTransfer(address(join), assetToDeposit);
        }

        // Give the vault back to the sender, just in case there is anything left
        giver.give(vaultId, msg.sender);
    }

    /// @notice We start with base tokens (e.g. Weth, not eWeth) and borrowed
    ///     fyTokens. We need to sell the fyTokens and then convert all to the
    ///     yield-bearing tokens.
    function borrow(
        bytes6 seriesId,
        bytes12 vaultId,
        uint128 baseAmount,
        uint256 borrowAmount,
        uint256 fee,
        uint256 minCollateral
    ) internal virtual;

    function repay(
        bytes12 vaultId,
        bytes6 seriesId,
        uint128 borrowAmountPlusFee, // Amount of FYToken received
        bytes calldata data
    ) internal virtual;

    function close(
        bytes12 vaultId,
        uint128 ink,
        uint128 art
    ) internal virtual;
}
