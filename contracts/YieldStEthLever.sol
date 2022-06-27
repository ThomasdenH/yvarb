// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";
import "@yield-protocol/vault-interfaces/src/ILadle.sol";
import "@yield-protocol/vault-interfaces/src/IFYToken.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/vault-v2/utils/Giver.sol";
import "@yield-protocol/vault-v2/FlashJoin.sol";
import "./interfaces/IStableSwap.sol";

error FlashLoanFailure();
error SlippageFailure();

interface WstEth is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256);

    function unwrap(uint256 _wstETHAmount) external returns (uint256);
}

/// @notice This contracts allows a user to 'lever up' via StEth. The concept
///     is as follows: Using Yield, it is possible to borrow Weth, which in
///     turn can be used as collateral, which in turn can be used to borrow and
///     so on.
///
///     The way to do this in practice is by first borrowing the desired debt
///     through a flash loan and using this in additon to your own collateral.
///     The flash loan is repayed using funds borrowed using your collateral.
contract YieldStEthLever is IERC3156FlashBorrower {
    using TransferHelper for IERC20;
    using TransferHelper for IFYToken;
    using TransferHelper for WstEth;

    /// @notice By IERC3156, the flash loan should return this constant.
    bytes32 public constant FLASH_LOAN_RETURN =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @notice WEth.
    IERC20 public constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    /// @notice StEth, represents Ether stakes on Lido.
    IERC20 public constant steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    /// @notice WStEth, wrapped StEth, useful because StEth rebalances.
    WstEth public constant wsteth = WstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    /// @notice The Yield Ladle, the primary entry point for most high-level
    ///     operations.
    ILadle public constant ladle =
        ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    /// @notice The Yield Cauldron, handles debt and collateral balances.
    ICauldron public constant cauldron =
        ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    /// @notice Curve.fi token swapping contract between Ether and StETH.
    IStableSwap public constant stableSwap =
        IStableSwap(0x828b154032950C8ff7CF8085D841723Db2696056);
    /// @notice The ild ID for WStEth.
    bytes6 public constant ilkId = bytes6(0x303400000000);
    /// @notice The Yield Protocol Join containing WstEth.
    FlashJoin public constant wstethJoin =
        FlashJoin(0x5364d336c2d2391717bD366b29B6F351842D7F82);
    /// @notice The Yield Protocol Join containing Weth.
    FlashJoin public constant wethJoin =
        FlashJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0);
    /// @notice Ether Yield liquidity pool. Exchanges Weth with FYWeth.
    //IPool public constant pool = IPool(0xc3348D8449d13C364479B1F114bcf5B73DFc0dc6);
    /// @notice FyWeth, used to borrow based on Weth.
    //FYToken public constant fyToken = FYToken(0x53358d088d835399F1E97D2a01d79fC925c7D999);
    /// @notice The Giver contract can give vaults on behalf on a user who gave
    ///     permission.
    Giver public immutable giver;

    /// @notice The operation to execute in the flash loan.
    enum Operation {
        LEVER_UP,
        REPAY,
        CLOSE
    }

    /// @notice Deploy this contract.
    /// @param giver_ The `Giver` contract to use.
    /// @dev The contract should never own anything in between transactions;
    ///     no tokens, no vaults. To save gas we give these tokens full
    ///     approval.
    constructor(Giver giver_) {
        giver = giver_;

        // TODO: What if these approvals fail by returning `false`? Is that even a case worth
        //  considering?
        weth.approve(address(stableSwap), type(uint256).max);
        steth.approve(address(stableSwap), type(uint256).max);
        weth.approve(address(wethJoin), type(uint256).max);
        steth.approve(address(wsteth), type(uint256).max);
    }

    /// @notice Approve maximally for an fyToken.
    /// @param seriesId The id of the pool to approve to.
    function approveFyToken(bytes6 seriesId) external {
        IPool(ladle.pools(seriesId)).fyToken().approve(address(ladle), type(uint256).max);
    }

    /// @notice Invest by creating a levered vault.
    ///
    ///     We invest `FYToken`. For this the user should have given approval
    ///     first. We borrow `borrowAmount` extra. We use it to buy Weth,
    ///     exchange it to (W)StEth, which we use as collateral. The contract
    ///     tests that at least `minCollateral` is attained in order to prevent
    ///     sandwich attacks.
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
    ) external returns (bytes12 vaultId) {
        IFYToken fyToken = IPool(ladle.pools(seriesId)).fyToken();
        fyToken.safeTransferFrom(msg.sender, address(this), baseAmount);
        (vaultId, ) = ladle.build(seriesId, ilkId, 0);
        // Since we know the sizes exactly, packing values in this way is more
        // efficient than using `abi.encode`.
        //
        // Encode data of
        // OperationType    1 byte      [0:1]
        // seriesId         6 bytes     [1:7]
        // vaultId          12 bytes    [7:19]
        // baseAmount       16 bytes    [19:35]
        // minCollateral    16 bytes    [35:51]
        bytes memory data = bytes.concat(
            bytes1(uint8(uint256(Operation.LEVER_UP))),
            seriesId,
            vaultId,
            bytes16(baseAmount),
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
        // We put everything that we borrowed into the vault, so there can't be
        // any FYTokens left. Check:
        require(IERC20(address(fyToken)).balanceOf(address(this)) == 0);
    }

    /// @notice Called by a flash lender, which can be `wstethJoin` or
    ///     `wethJoin` (for Weth). The primary purpose is to check conditions
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
    ) external returns (bytes32) {
        Operation status = Operation(uint256(uint8(data[0])));
        bytes6 seriesId = bytes6(data[1:7]);

        IFYToken fyToken = IPool(ladle.pools(seriesId)).fyToken();
        // Test that the lender is either the fyToken contract or the Weth
        // Join.
        if (msg.sender != address(fyToken) && msg.sender != address(wethJoin))
            revert FlashLoanFailure();
        // We trust the lender, so now we can check that we were the initiator.
        if (initiator != address(this))
            revert FlashLoanFailure();

        // Decode the operation to execute and then call that function.
        if (status == Operation.LEVER_UP) {
            bytes12 vaultId = bytes12(data[7:19]);
            uint128 baseAmount = uint128(uint128(bytes16(data[19:35])));
            uint256 minCollateral = uint128(bytes16(data[35:51]));
            leverUp(borrowAmount, fee, baseAmount, minCollateral, vaultId, seriesId);
        } else if (status == Operation.REPAY) {
            bytes12 vaultId = bytes12(data[7:19]);
            uint128 ink = uint128(bytes16(data[19:35]));
            uint128 art = uint128(bytes16(data[35:51]));
            address borrower = address(bytes20(data[51:71]));
            uint256 minWeth = uint256(bytes32(data[71:103]));
            doRepay(uint128(borrowAmount + fee), vaultId, ink, art, minWeth, borrower, seriesId);
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
    ///         - We have supplied and borrowed FYWeth.
    ///         - We convert it to StEth and put it in the vault.
    ///         - Against it, we borrow enough FYWeth to repay the flash loan.
    /// @param borrowAmount The amount of FYWeth borrowed in the flash loan.
    /// @param fee The fee that will be issued by the flash loan.
    /// @param baseAmount The amount of own collateral to supply.
    /// @param minCollateral The final amount of collateral to end up with, or
    ///     the function will revert. Used to prevent slippage.
    /// @param vaultId The vault id to put collateral into and borrow from.
    /// @param seriesId The pool (and thereby series) to borrow from.
    function leverUp(
        uint256 borrowAmount,
        uint256 fee,
        uint128 baseAmount,
        uint256 minCollateral,
        bytes12 vaultId,
        bytes6 seriesId
    ) internal {
        // The total amount to invest. Equal to the base plus the borrowed
        // minus the flash loan fee. The fee saved here together with the
        // borrowed amount later pays off the flash loan. This makes sure we
        // borrow exactly `borrowAmount`.
        IPool pool;
        {
            uint128 netInvestAmount = uint128(baseAmount + borrowAmount - fee);

            // Get WEth by selling borrowed FYTokens. We don't need to check for a
            // minimum since we check that we have enough collateral later on.
            pool = IPool(ladle.pools(seriesId));
            IFYToken fyToken = pool.fyToken();
            fyToken.safeTransfer(address(pool), netInvestAmount);
        }
        uint256 wethReceived = pool.sellFYToken(address(this), 0);

        // Swap WEth for StEth on Curve.fi. Again, we do not check for a
        // minimum.
        // 0: WEth
        // 1: StEth
        uint256 boughtStEth = stableSwap.exchange(
            0,
            1,
            wethReceived,
            0,
            address(this)
        );

        // Wrap StEth to WStEth.
        uint128 wrappedStEth = uint128(wsteth.wrap(boughtStEth));

        // This is the amount to deposit, so we check for slippage here. As
        // long as we end up with the desired amount, it doesn't matter what
        // slippage occurred where.
        if (wrappedStEth < minCollateral) revert SlippageFailure();

        // Deposit WStEth in the vault & borrow `borrowAmount` fyToken to
        // pay back.
        wsteth.safeTransfer(address(wstethJoin), wrappedStEth);
        ladle.pour(
            vaultId,
            address(this),
            int128(uint128(wrappedStEth)),
            int128(uint128(borrowAmount))
        );

        // At the end, the flash loan will take exactly `borrowedAmount + fee`,
        // so the final balance should be exactly 0.
    }

    /// @notice Unwind a position.
    ///
    ///     If pre maturity, borrow liquidity tokens to repay `art` debt and
    ///     take `ink` collateral. Repay the loan and return remaining
    ///     collateral as WEth.
    ///
    ///     If post maturity, borrow WEth to pay off the debt directly. Convert
    ///     the WStEth collateral to WEth and return excess to user.
    ///
    ///     This function will take the vault from you using `Giver`, so make
    ///     sure you have given it permission to do that.
    /// @param ink The amount of collateral to recover.
    /// @param art The debt to repay.
    /// @param minWeth Revert the transaction if we don't obtain at least this
    ///     much WEth at the end of the operation.
    /// @param vaultId The vault to use.
    /// @param seriesId The seriesId corresponding to the vault.
    /// @dev It is more gas efficient to let the user supply the `seriesId`,
    ///     but it should match the pool.
    function unwind(
        uint128 ink,
        uint128 art,
        uint256 minWeth,
        bytes12 vaultId,
        bytes6 seriesId
    ) external {
        // Test that the caller is the owner of the vault.
        // This is important as we will take the vault from the user.
        (address owner, , ) = cauldron.vaults(vaultId);
        require(owner == msg.sender);

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
                vaultId, // [7:19]
                bytes16(ink), // [19:35]
                bytes16(art), // [35:51]
                bytes20(msg.sender), // [51:71]
                bytes32(minWeth) // [71:103]
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
            // Repay:
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
            bool success = wethJoin.flashLoan(
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
    /// @param borrowAmountPlusFee The amount of fyWeth that we have borrowed,
    ///     plus the fee. This should be our final balance.
    /// @param vaultId The vault to repay.
    /// @param ink The amount of collateral to retake.
    /// @param art The debt to repay.
    /// @param minWeth The minimum amount of WEth to end up with. Used against
    ///     slippage.
    /// @param borrower The borrower, the previous owner of the vault.
    function doRepay(
        uint128 borrowAmountPlusFee, // Amount of FYToken received
        bytes12 vaultId,
        uint128 ink,
        uint128 art,
        uint256 minWeth,
        address borrower,
        bytes6 seriesId
    ) internal {
        // Repay the vault, get collateral back.
        ladle.pour(
            vaultId,
            address(this),
            -int128(ink),
            -int128(art)
        );

        // Unwrap WStEth to obtain StEth.
        uint256 stEthUnwrapped = wsteth.unwrap(ink);

        // Exchange StEth for WEth.
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
        IPool pool = IPool(ladle.pools(seriesId));
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

        // We should have exactly `borrowAmountPlusFee` fyWeth as that is what
        // we have bought. This pays back the flash loan exactly.
    }

    /// @notice Close a vault after maturity.
    ///         - We have borrowed WEth
    ///         - Use it to repay the debt and take the collateral.
    ///         - Sell it all for WEth and close position.
    /// @param vaultId The ID of the vault to close.
    /// @param ink The collateral to take from the vault.
    /// @param art The debt to repay. This is denominated in fyTokens, even
    ///     though the payment is done in terms of WEth.
    function doClose(bytes12 vaultId, uint128 ink, uint128 art) internal {
        // We have obtained Weth, exactly enough to repay the vault. This will
        // give us our WStEth collateral back.
        // data[1:13]: vaultId
        // data[29:45]: art
        ladle.close(vaultId, address(this), -int128(ink), -int128(art));

        // Convert wsteth to steth
        uint256 stEthUnwrapped = wsteth.unwrap(ink);

        // convert steth - weth
        // 1: STETH
        // 0: WETH
        // No minimal amount is necessary: The flashloan will try to take the
        // borrowed amount and fee, and we will check for slippage afterwards.
        stableSwap.exchange(1, 0, stEthUnwrapped, 0, address(this));

        // At the end of the flash loan, we repay in terms of WEth and have
        // used the inital balance entirely for the vault, so we have better
        // obtained it!
    }
}
