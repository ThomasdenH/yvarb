// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/vault-v2/other/lido/StEthConverter.sol";
import "@yield-protocol/vault-v2/utils/Giver.sol";
import "@yield-protocol/vault-v2/FlashJoin.sol";
import "@yield-protocol/vault-v2/FYToken.sol";
import "./interfaces/IStableSwap.sol";

error FlashLoanFailure();
error SlippageFailure();

interface WstEth is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256);

    function unwrap(uint256 _wstETHAmount) external returns (uint256);
}

interface YieldLadle {
    function pools(bytes6 seriesId) external view returns (address);

    function build(
        bytes6 seriesId,
        bytes6 ilkId,
        uint8 salt
    ) external payable returns (bytes12, DataTypes.Vault memory);

    function repay(
        bytes12 vaultId_,
        address to,
        int128 ink,
        uint128 min
    ) external payable returns (uint128 art);

    function repayVault(
        bytes12 vaultId_,
        address to,
        int128 ink,
        uint128 max
    ) external payable returns (uint128 base);

    function close(
        bytes12 vaultId_,
        address to,
        int128 ink,
        int128 art
    ) external payable returns (uint128 base);

    function give(bytes12 vaultId_, address receiver)
        external
        payable
        returns (DataTypes.Vault memory vault);

    function pour(
        bytes12 vaultId,
        address to,
        int128 ink,
        int128 art
    ) external payable;

    function repayFromLadle(bytes12 vaultId_, address to)
        external
        payable
        returns (uint256 repaid);

    function closeFromLadle(bytes12 vaultId_, address to)
        external
        payable
        returns (uint256 repaid);
}

contract YieldStEthLever is IERC3156FlashBorrower {
    using TransferHelper for IERC20;
    using TransferHelper for FYToken;
    using TransferHelper for WstEth;

    bytes32 internal constant FLASH_LOAN_RETURN =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    YieldLadle constant ladle =
        YieldLadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    ICauldron constant cauldron =
        ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    /// @notice Curve.fi token swapping contract between Ether and stETH.
    IStableSwap constant stableSwap =
        IStableSwap(0x828b154032950C8ff7CF8085D841723Db2696056);
    /// @notice Contract to wrap StEth to create WstEth. Unlike StEth, WstEth
    ///     doesn't rebase balances and instead represents a share of the pool.
    StEthConverter constant stEthConverter =
        StEthConverter(0x93D232213cCA6e5e7105199ABD8590293C3eb106);
    bytes6 constant ilkId = bytes6(0x303400000000); //wsteth
    /// @notice The Yield Protocol Join containing WstEth.
    FlashJoin constant flashJoin =
        FlashJoin(0x5364d336c2d2391717bD366b29B6F351842D7F82);
    /// @notice The Yield Protocol Join containing Weth.
    FlashJoin constant flashJoin2 =
        FlashJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0);
    /// @notice Ether Yiels liquidity pool.
    IPool constant pool = IPool(0xc3348D8449d13C364479B1F114bcf5B73DFc0dc6);
    IERC20 constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    WstEth constant wsteth = WstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 constant steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    FYToken immutable fyToken;
    Giver immutable giver;

    constructor(FYToken fyToken_, Giver giver_) {
        fyToken = fyToken_;
        giver = giver_;

        // TODO: What if these approvals fail by returning `false`? Is that even a case worth
        //  considering?
        fyToken_.approve(address(ladle), type(uint256).max);
        fyToken_.approve(address(pool), type(uint256).max);
        pool.base().approve(address(stableSwap), type(uint256).max);
        wsteth.approve(address(stableSwap), type(uint256).max);
        steth.approve(address(stableSwap), type(uint256).max);
        weth.approve(address(flashJoin2), type(uint256).max);
        wsteth.approve(address(flashJoin), type(uint256).max);
        steth.approve(address(wsteth), type(uint256).max);
    }

    /// @notice Invest by creating a levered vault.
    /// @param baseAmount The amount of own liquidity to supply.
    /// @param borrowAmount The amount of additional liquidity to borrow.
    /// @param minCollateral The minimum amount of collateral to end up with in
    ///     the vault. If this requirement is not satisfied, the transaction
    ///     will revert.
    /// @param seriesId The series to create the vault for.
    function invest(
        uint128 baseAmount,
        uint128 borrowAmount,
        uint128 minCollateral,
        bytes6 seriesId
    ) external returns (bytes12) {
        fyToken.safeTransferFrom(msg.sender, address(this), baseAmount);
        (bytes12 vaultId, ) = ladle.build(seriesId, ilkId, 0);
        // Encode data of
        // OperationType    1 byte      [0]
        // vaultId          12 bytes    [1:13]
        // baseAmount       16 bytes    [13:29]
        // minCollateral    16 bytes    [29:45]
        bytes memory data = bytes.concat(
            bytes1(0x01),
            vaultId,
            bytes16(baseAmount),
            bytes16(minCollateral)
        );
        bool success = fyToken.flashLoan(
            this, // Loan Receiver
            address(fyToken), // Loan Token
            borrowAmount, // Loan Amount
            data
        );
        if (!success) revert FlashLoanFailure();
        giver.give(vaultId, msg.sender);
        // We put everything that we borrowed into the vault, so there can't be
        // any FYTokens left. Check:
        // assert(IERC20(address(fyToken)).balanceOf(address(this)) == 0);
        return vaultId;
    }

    /// @param initiator The initator of the flash loan, must be `address(this)`.
    /// @param borrowAmount The amount of fyTokens borrowed.
    function onFlashLoan(
        address initiator,
        address, // token
        uint256 borrowAmount, // Amount of FYToken received
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        // Test that the flash loan was sent from the lender contract and that
        // this contract was the initiator.
        if (
            (msg.sender != address(fyToken) &&
                msg.sender != address(flashJoin2)) || initiator != address(this)
        ) revert FlashLoanFailure();

        // Decode the operation to execute
        bytes1 status = data[0];
        if (status == 0x01) {
            leverUp(borrowAmount, fee, data);
        } else if (status == 0x02) {
            doRepay(uint128(borrowAmount + fee), data);
        } else if (status == 0x03) {
            doClose(borrowAmount, data);
        }
        return FLASH_LOAN_RETURN;
    }

    function leverUp(
        uint256 borrowAmount, // Amount of FYToken received
        uint256 fee,
        bytes calldata data
    ) internal {
        uint128 baseAmount = uint128(bytes16(data[13:29]));
        uint128 minCollateral = uint128(bytes16(data[29:45]));
        bytes12 vaultId = bytes12(data[1:13]);

        // The total amount to invest. Equal to the base plus the borrowed minus the flash loan
        // fee.
        uint128 netInvestAmount = uint128(baseAmount + borrowAmount - fee);

        fyToken.safeTransfer(address(pool), netInvestAmount);

        // Get WETH
        pool.buyBase(
            address(this),
            uint128(pool.sellFYTokenPreview(netInvestAmount)),
            netInvestAmount
        );
        // Swap WETH for stETH on curve
        // 0: WETH
        // 1: STETH
        stableSwap.exchange(
            0,
            1,
            pool.base().balanceOf(address(this)), // This value is different from base received
            1,
            address(stEthConverter)
        );

        // Wrap steth to wsteth
        uint128 wrappedamount = uint128(
            stEthConverter.wrap(address(flashJoin))
        );
        if (wrappedamount < minCollateral) revert SlippageFailure();
        // Deposit wstETH in the vault & borrow fyToken to payback
        ladle.pour(
            vaultId,
            address(this),
            int128(uint128(wrappedamount)),
            int128(uint128(borrowAmount))
        );
    }

    /// @notice Unwind a position.
    ///
    ///     If pre maturity, borrow liquidity tokens to repay `art` debt and
    ///     take `ink` collateral. Repay the loan and return remaining
    ///     collateral as WETH.
    ///
    ///     If post maturity, borrow StEth, sell and repay WEth directly.
    ///     obtain StEth collateral, and send the excess to the user.
    /// @param ink The amount of collateral to recover.
    /// @param art The debt to repay.
    /// @param minWeth Revert the transaction if we don't obtain at least this
    ///     much weth at the end of the operation.
    /// @param vaultId The vault to use.
    /// @param seriesId The seriesId corresponding to the vault.
    function unwind(
        uint128 ink,
        uint128 art,
        uint256 minWeth,
        bytes12 vaultId,
        bytes6 seriesId
    ) external {
        // Test that the caller is the owner of the vault.
        // This is important as we will take the vault from the user.
        require(cauldron.vaults(vaultId).owner == msg.sender);

        // Give the vault to the contract
        giver.seize(vaultId, address(this));

        if (uint32(block.timestamp) < cauldron.series(seriesId).maturity) {
            // REPAY
            // Series is not past maturity
            // Borrow to repay debt, move directly to the pool.
            bytes memory data = bytes.concat(
                bytes1(0x02), // [0]
                vaultId, // [1:13]
                bytes16(ink), // [13:29]
                bytes16(art), // [29:45]
                bytes20(msg.sender), // [45:65]
                bytes32(minWeth) // [65:97]
            );
            bool success = fyToken.flashLoan(
                this, // Loan Receiver
                address(fyToken), // Loan Token
                art, // Loan Amount: borrow the debt to repay
                data
            );
            if (!success) revert FlashLoanFailure();

            // We have borrowed exactly enough for the debt and bought back
            // exactly enough for the loan + fee, so there is no balance of
            // FYToken left.
            // assert(IERC20(address(fyToken)).balanceOf(address(this)) == 0);
        } else {
            // CLOSE
            // Series is past maturity, borrow and move directly to collateral pool
            bytes memory data = bytes.concat(
                bytes1(0x03), // [0]
                vaultId, // [1:13]
                bytes16(ink), // [13:29]
                bytes16(art) // [29:45]
            );
            // We have a debt in terms of fyWeth, but should pay back in Weth.
            // `base` is how much Weth we should pay back.
            uint128 base = cauldron.debtToBase(seriesId, art);
            bool success = flashJoin2.flashLoan(
                this, // Loan Receiver
                address(weth), // Loan Token
                base, // Loan Amount
                data
            );
            if (!success) revert FlashLoanFailure();

            // At this point, we have only Weth left. Hopefully: this comes
            // from the collateral in our vault!

            uint256 wethBalance = weth.balanceOf(address(this));
            if (wethBalance < minWeth) revert SlippageFailure();
            // Transferring the leftover to the user
            IERC20(weth).safeTransfer(msg.sender, wethBalance);
        }

        // Give the vault back to the sender, just in case there is anything left
        giver.give(vaultId, msg.sender);
    }

    /// @dev    - We have borrowed liquidity tokens, for which we have a debt.
    ///         - Remove `ink` collateral and repay `art` debt.
    ///         - Sell obtained `ink` StEth for WEth.
    ///         - Repay loan by buying liquidity tokens
    ///         - Send remaining WEth to user
    function doRepay(
        uint128 borrowAmountPlusFee, // Amount of FYToken received
        bytes calldata data
    ) internal {
        bytes12 vaultId = bytes12(data[1:13]);
        uint128 ink = uint128(bytes16(data[13:29]));
        uint128 art = uint128(bytes16(data[29:45]));
        address borrower = address(bytes20(data[45:65]));
        uint256 minWeth = uint256(bytes32(data[65:97]));

        // Repay the vault, get collateral back.
        ladle.pour(
            vaultId,
            address(this),
            -int128(ink),
            -int128(art) // How much could I borrow?
        );

        // Convert wsteth - steth
        uint256 stEthUnwrapped = wsteth.unwrap(ink);

        // convert steth- weth
        // 0: WETH
        // 1: STETH
        uint256 wethReceived = stableSwap.exchange(
            1,
            0,
            stEthUnwrapped,
            1,
            // We can't send directly to the pool because the remainder is our
            // profit!
            address(this)
        );

        // Convert weth to FY to repay loan. We want `borrowAmountPlusFee`.
        uint128 wethToTran = pool.buyFYTokenPreview(borrowAmountPlusFee);
        weth.safeTransfer(address(pool), wethToTran);
        pool.buyFYToken(address(this), borrowAmountPlusFee, wethToTran);

        // Send remaining weth to user
        uint256 wethRemaining;
        unchecked {
            // Unchecked: This is equal to our balance, so it must be positive.
            wethRemaining = wethReceived - wethToTran;
        }
        if (wethRemaining < minWeth) revert SlippageFailure();
        weth.safeTransfer(borrower, wethRemaining);
    }

    /// @dev    - We have borrowed WstEth
    ///         - Sell it all for WEth and close position.
    function doClose(uint256 borrowAmount, bytes calldata data) internal {
        bytes12 vaultId = bytes12(data[1:13]);
        uint128 ink = uint128(bytes16(data[13:29]));
        uint128 art = uint128(bytes16(data[29:45]));

        // We have obtained Weth, exactly enough to repay the vault. This will
        // give us our WStEth collateral back.
        ladle.close(vaultId, address(this), -int128(ink), -int128(art));

        // Convert wsteth to steth
        uint256 stEthUnwrapped = wsteth.unwrap(ink);

        // convert steth - weth
        // 1: STETH
        // 0: WETH
        // No minimal amount is necessary: The flashloan will try to take the
        // borrowed amount and fee, and we will check for slippage afterwards.
        stableSwap.exchange(1, 0, stEthUnwrapped, 0, address(this));

        // At the end of the flash loan, we repay in terms of Weth and have
        // used everything for the vault, so we have better obtained it!
    }
}
