// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./YieldLeverBase.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IMaturingToken.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface ICrabStrategy {
    function totalSupply() external view returns (uint256);

    function balanceOf(address _user) external view returns (uint256);

    /**
     * @notice get the vault composition of the strategy
     * @return operator
     * @return nft collateral id
     * @return collateral amount
     * @return short amount
     */
    function getVaultDetails()
        external
        view
        returns (
            address,
            uint256,
            uint256,
            uint256
        );

    /**
     * @notice flash deposit into strategy, providing ETH, selling wSqueeth and receiving strategy tokens
     * @dev this function will execute a flash swap where it receives ETH, deposits and mints using flash swap proceeds and msg.value, and then repays the flash swap with wSqueeth
     * @dev _ethToDeposit must be less than msg.value plus the proceeds from the flash swap
     * @dev the difference between _ethToDeposit and msg.value provides the minimum that a user can receive for their sold wSqueeth
     * @param _ethToDeposit total ETH that will be deposited in to the strategy which is a combination of msg.value and flash swap proceeds
     * @param _poolFee Uniswap pool fee
     */
    function flashDeposit(uint256 _ethToDeposit, uint24 _poolFee)
        external
        payable;

    /**
     * @notice flash withdraw from strategy, providing strategy tokens, buying wSqueeth, burning and receiving ETH
     * @dev this function will execute a flash swap where it receives wSqueeth, burns, withdraws ETH and then repays the flash swap with ETH
     * @param _crabAmount strategy token amount to burn
     * @param _maxEthToPay maximum ETH to pay to buy back the wSqueeth debt
     * @param _poolFee Uniswap pool fee

     */
    function flashWithdraw(
        uint256 _crabAmount,
        uint256 _maxEthToPay,
        uint24 _poolFee
    ) external;
}

/// @title A contract to help users build levered position on crab strategy token
///        using ETH/WETH/DAI/USDC as collateral
/// @author iamsahu
/// @notice Each external function has the details on how this works
contract YieldCrabLever is YieldLeverBase {
    using TransferHelper for IERC20;
    using TransferHelper for IMaturingToken;
    using CastU128I128 for uint128;
    using CastU256U128 for uint256;

    ICrabStrategy public constant crabStrategy =
        ICrabStrategy(0x3B960E47784150F5a63777201ee2B15253D713e8);

    ISwapRouter public constant swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IERC20 public crab;
    bytes6 public constant crabId = 0x333800000000;
    bytes6 public constant wethId = 0x303000000000;
    bytes6 public constant daiId = 0x303100000000;
    bytes6 public constant usdcId = 0x303200000000;

    constructor(Giver giver_) YieldLeverBase(giver_) {}

    /// @notice Invest by creating a levered vault.
    /// The steps are as follows:
    /// 1. Based on the base transfer it from the user
    /// @param seriesId The series to invest in
    /// @param baseId The collateral to use
    /// @param amountToInvest The amount of ETH/WETH/DAI/USDC supplied by the user
    /// @param borrowAmount The amount of fyToken to be borrowed
    /// @param minCollateral to be received
    function invest(
        bytes6 seriesId,
        bytes6 baseId,
        uint256 amountToInvest,
        uint256 borrowAmount,
        uint256 minCollateral
    ) external payable returns (bytes12 vaultId) {
        IPool pool = IPool(ladle.pools(seriesId));
        IMaturingToken fyToken = pool.fyToken();
        // Depend on baseId we will have to choose the operation
        if (baseId != wethId || msg.value == 0) {
            // transfer the amountToInvest to this contract
            pool.base().safeTransferFrom(
                msg.sender,
                address(this),
                amountToInvest
            );
        }

        // Build the vault
        (vaultId, ) = ladle.build(seriesId, crabId, 0);

        bytes memory data = bytes.concat(
            bytes1(uint8(uint256(Operation.BORROW))), //[0]
            seriesId, // [1:7]
            vaultId, // [7:19]
            baseId, // [19:25]
            bytes32(amountToInvest) // [25:57]
        );

        bool success = IERC3156FlashLender(address(fyToken)).flashLoan(
            this, // Loan Receiver
            address(fyToken), // Loan Token
            borrowAmount, // Loan Amount
            data
        );

        if (!success) revert FlashLoanFailure();

        DataTypes.Balances memory balances = cauldron.balances(vaultId);

        // This is the amount to deposit, so we check for slippage here. As
        // long as we end up with the desired amount, it doesn't matter what
        // slippage occurred where.
        if (balances.ink < minCollateral) revert SlippageFailure();

        giver.give(vaultId, msg.sender);

        // This is end of execution so no concern for reentrancy here
        if (address(this).balance > 0)
            payable(msg.sender).call{value: address(this).balance}("");

        emit Invested(
            vaultId,
            seriesId,
            msg.sender,
            balances.ink,
            balances.art
        );
    }

    /// @notice Divest, either before or after maturity.
    /// @param vaultId The vault to divest from.
    /// @param seriesId The series
    /// @param baseId The baseId
    /// @param ink The amount of collateral to recover.
    /// @param art The amount of debt to repay.
    /// @param minBaseOut Used to minimize slippage. The transaction will revert
    ///     if we don't obtain at least this much of the base asset.
    function divest(
        bytes12 vaultId,
        bytes6 seriesId,
        bytes6 baseId,
        uint256 ink,
        uint256 art,
        uint256 minBaseOut
    ) external {
        // Test that the caller is the owner of the vault.
        // This is important as we will take the vault from the user.
        require(cauldron.vaults(vaultId).owner == msg.sender);

        // Give the vault to the contract
        giver.seize(vaultId, address(this));

        // Check if we're pre or post maturity.
        bool success;
        if (uint32(block.timestamp) > cauldron.series(seriesId).maturity) {
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.CLOSE)))), // [0:1]
                seriesId, // [1:7]
                vaultId, // [7:19]
                baseId, // [19:25]
                bytes32(ink), // [25:57]
                bytes32(art)
            );

            address join = address(ladle.joins(cauldron.series(seriesId).baseId));

            // Close:
            // Series is not past maturity, borrow and move directly to collateral pool.
            // We have a debt in terms of fyToken, but should pay back in base.
            uint128 base = cauldron.debtToBase(seriesId, art.u128());
            success = IERC3156FlashLender(join).flashLoan(
                this, // Loan Receiver
                address(IJoin(join).asset()), // Loan Token
                base, // Loan Amount
                data
            );
        } else {
            IPool pool = IPool(ladle.pools(seriesId));
            IMaturingToken fyToken = pool.fyToken();
            // Repay:
            // Series is not past maturity.
            // Borrow to repay debt, move directly to the pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.REPAY)))), // [0:1]
                seriesId, // [1:7]
                vaultId, // [7:19]
                baseId, // [19:25]
                bytes32(ink), // [25:57]
                bytes32(art) // [57:89]
            );
            success = IERC3156FlashLender(address(fyToken)).flashLoan(
                this, // Loan Receiver
                address(fyToken), // Loan Token
                art, // Loan Amount: borrow exactly the debt to repay.
                data
            );
        }
        if (!success) revert FlashLoanFailure();
        IERC20 baseToken = IERC20(cauldron.assets(baseId));
        uint256 baseLeftOver = baseToken.balanceOf(address(this));
        if (baseLeftOver < minBaseOut) revert SlippageFailure();
        // Transferring the leftover to the user
        baseToken.safeTransfer(msg.sender, baseLeftOver);
        // Give the vault back to the sender, just in case there is anything left
        giver.give(vaultId, msg.sender);
    }

    /// @notice Callback for the flash loan.
    /// @dev Used as a router to the correct function based
    ///      on the operation present in the data.
    function onFlashLoan(
        address initiator,
        address token, // The token, not checked as we check the lender address.
        uint256 borrowAmount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32 returnValue) {
        returnValue = FLASH_LOAN_RETURN;

        Operation status = Operation(uint256(uint8(data[0])));
        bytes6 seriesId = bytes6(data[1:7]);
        IPool pool = IPool(ladle.pools(seriesId));

        // Test that the lender is either a fyToken contract or the join.
        if (
            msg.sender != address(pool.fyToken()) &&
            msg.sender != address(ladle.joins(cauldron.series(seriesId).baseId))
        ) revert FlashLoanFailure();
        // We trust the lender, so now we can check that we were the initiator.
        if (initiator != address(this)) revert FlashLoanFailure();

        // Based on the operation we call the correct function.
        if (status == Operation.BORROW) {
            // Approve the repayment to the lender.
            IERC20(token).safeApprove(msg.sender, borrowAmount + fee);
            _borrow(borrowAmount, fee, token, pool, data);
        } else if (status == Operation.REPAY) {
            // Approve the repayment to the lender.
            IERC20(token).safeApprove(msg.sender, borrowAmount + fee);
            _repay(borrowAmount + fee, token, pool, data);
        } else if (status == Operation.CLOSE) {
            // Approve the repayment to the lender.
            // We double the amount of approval as the join will pull the debt payment & flash loan payment
            IERC20(token).safeApprove(msg.sender, 2 * borrowAmount + fee);
            _close(data);
        }
    }

    /// @notice This function is called from within the flash loan. The high
    ///     level functionality is as follows:
    ///     for ETH borrowing,
    ///      1. flash borrow fyETH
    ///      2. sell for ETH and combine with user ETH
    ///      3. deposit to get Crab
    ///      4. borrow against crab to payback flash loan
    ///
    ///     for USDC/DAI borrowing,
    ///      1. flash borrow fyUSDC
    ///      2. sell for USDC and combine with USDC
    ///      3. sell USDC for ETH
    ///      4. deposit to get Crab
    ///      5. borrow against crab to payback flashloan
    /// @param borrowAmount The amount of FYWeth borrowed in the flash loan.
    /// @param fee The fee that will be issued by the flash loan.
    /// @param fyToken The fyToken that was borrowed.
    /// @param pool The pool from in which we will sell borrowed fyToken.
    /// @param data The data that was passed to the flash loan.
    function _borrow(
        uint256 borrowAmount,
        uint256 fee,
        address fyToken,
        IPool pool,
        bytes calldata data
    ) internal {
        bytes12 vaultId = bytes12(data[7:19]);
        bytes6 baseId = bytes6(data[19:25]);
        uint256 amountToInvest = uint256(bytes32(data[25:57]));

        // Get base by selling borrowed FYTokens.
        IERC20(fyToken).safeTransfer(address(pool), borrowAmount - fee);
        uint256 baseReceived = pool.sellFYToken(address(this), 0);

        // Based on the base, we either deposit the base directly or
        // we need to convert it to ETH first.
        if (baseId == wethId) {
            // TODO: Check what happens when the user sent amount of ETH less than amountToInvest
            if (address(this).balance == amountToInvest)
                weth.withdraw(baseReceived);
            else weth.withdraw(baseReceived + amountToInvest); // When user has supplied WETH
        } else if (baseId == daiId || baseId == usdcId) {
            // Swap dai/usdc to get weth & withdraw
            weth.withdraw(_swap(cauldron.assets(baseId), address(weth)));
        } else {
            revert();
        }

        // Flash deposit ETH to get Crab
        crabStrategy.flashDeposit{value: address(this).balance}(
            address(this).balance,
            3000
        );

        uint256 crabBalance = crabStrategy.balanceOf(address(this));
        IERC20(address(crabStrategy)).safeApprove(
            address(ladle.joins(crabId)),
            crabBalance
        );
        // borrow against crab to payback flashloan
        _pour(vaultId, crabBalance.u128().i128(), borrowAmount.u128().i128());
    }

    /// @notice Unwind position and repay using fyToken
    /// Here are the steps:
    /// 1. Pay off the debt by using the flash borrowed fyToken
    /// 2. Flash withdraw the crab to get the ETH
    /// 3. Deposit ETH to get WETH
    /// 4. Swap WETH for USDC/DAI if base is USDC/DAI
    /// 5. Buy fyToken to pay back flash loan
    /// @param borrowAmountPlusFee The amount of fyToken that we have borrowed,
    ///     plus the fee. This should be our final balance.
    /// @param fyToken the fyToken that was borrowed.
    /// @param pool The pool from which we will buy fyToken.
    /// @param data The data that was passed to the flash loan.
    function _repay(
        uint256 borrowAmountPlusFee,
        address fyToken,
        IPool pool,
        bytes calldata data
    ) internal {
        bytes12 vaultId = bytes12(data[7:19]);
        bytes6 baseId = bytes6(data[19:25]);
        uint256 ink = uint256(bytes32(data[25:57]));
        uint256 art = uint256(bytes32(data[57:89]));

        // Payback debt to get back the underlying
        IERC20(fyToken).transfer(fyToken, art);
        _pour(vaultId, -ink.u128().i128(), -art.u128().i128());

        // Flash withdraw the crab to get the ETH
        crabStrategy.flashWithdraw(ink, type(uint256).max, 3000);

        weth.deposit{value: address(this).balance}();
        if (baseId != wethId) {
            _swap(address(weth), cauldron.assets(baseId));
        }

        uint128 fyTokenToBuy = borrowAmountPlusFee.u128();
        pool.base().transfer(
            address(pool),
            pool.buyFYTokenPreview(fyTokenToBuy) + 1 // Extra wei is to counter the Euler calculation bug
        );

        // Buy fyToken to pay back flash loan
        pool.buyFYToken(address(this), fyTokenToBuy, 0);
    }

    /// @notice Unwind position using the base asset and redeeming any fyToken
    /// Here are the steps:
    /// 1. Close the position with the flashloaned WETH/USDC/DAI
    /// 2. Withdraw the crab received to get ETH
    /// 3. Deposit ETH to get WETH
    /// 4. If baseId was USDC/DAI, swap WETH for USDC/DAI to payback the flash loan
    /// @param data The data that was passed to the flash loan.
    function _close(bytes calldata data) internal {
        bytes12 vaultId = bytes12(data[7:19]);
        bytes6 baseId = bytes6(data[19:25]);
        uint256 ink = uint256(bytes32(data[25:57]));
        uint256 art = uint256(bytes32(data[57:89]));
        ladle.close(
            vaultId,
            address(this),
            -ink.u128().i128(),
            -art.u128().i128()
        );

        // Flash withdraw the crab to get the ETH
        crabStrategy.flashWithdraw(ink, type(uint256).max, 3000);
        weth.deposit{value: address(this).balance}();

        // If baseId was USDC/DAI, swap WETH for USDC/DAI to payback the flash loan
        if (baseId != wethId) {
            _swap(address(weth), cauldron.assets(baseId));
        }
    }

    function _pour(
        bytes12 vaultId,
        int128 crabBalance,
        int128 borrowAmount
    ) internal {
        ladle.pour(vaultId, address(this), crabBalance, borrowAmount);
    }

    /// @notice Swap tokens using Uniswap
    function _swap(address tokenIn_, address tokenOut_)
        internal
        returns (uint256 amountReceived)
    {
        uint256 amountIn_ = IERC20(tokenIn_).balanceOf(address(this));
        IERC20(tokenIn_).approve(address(swapRouter), amountIn_);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn_,
                tokenOut: tokenOut_,
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn_,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        amountReceived = swapRouter.exactInputSingle(params);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {}

    receive() external payable {}
}
