// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "./interfaces/IEulerMarkets.sol";
import "./interfaces/IEulerEToken.sol";
import "./YieldLeverBase.sol";

// Get flash loan of USDC/DAI/WETH
// Deposit to get eulerToken
// Deposit & borrow against it
// Sell the fyToken to get USDC/DAI
// Close the flash loan
contract YieldEulerLever is YieldLeverBase {
    using TransferHelper for IERC20;

    // address constant EULER_MAINNET;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant EULER = 0x27182842E098f60e3D576794A5bFFb0777E025d3;

    // Use the markets module:
    IEulerMarkets public constant markets =
        IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);

    mapping(bytes6 => FlashJoin) public flashJoins;
    mapping(bytes6 => address) public ilkToAsset;

    // EulerMainMarket: 0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3
    constructor(Giver giver_) YieldLeverBase(giver_) {
        // Approve the main euler contract to pull your tokens:
        IERC20(USDC).approve(EULER, type(uint256).max);
        IERC20(DAI).approve(EULER, type(uint256).max);
        IERC20(WETH).approve(EULER, type(uint256).max);

        flashJoins[0x323000000000] = FlashJoin(
            0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc
        ); // daiJoin
        flashJoins[0x323100000000] = FlashJoin(
            0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4
        ); // usdcJoin
        flashJoins[0x323200000000] = FlashJoin(
            0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0
        ); // wethJoin

        ilkToAsset[0x323000000000] = DAI;
        ilkToAsset[0x323100000000] = USDC;
        ilkToAsset[0x323200000000] = WETH;

        // Approve join for
        IERC20(USDC).approve(
            0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4, // USDC Join
            type(uint256).max
        );
        IERC20(DAI).approve(
            0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc, // DAI Join
            type(uint256).max
        );
        IERC20(WETH).approve(
            0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0, // WETH Join
            type(uint256).max
        );
    }

    /// @notice Approve maximally for an fyToken.
    /// @param seriesId The id of the pool to approve to.
    function approveFyToken(bytes6 seriesId) external {
        IPool(ladle.pools(seriesId)).fyToken().approve(
            address(ladle),
            type(uint256).max
        );
    }

    function invest(
        uint128 baseAmount,
        uint128 borrowAmount,
        uint128 minCollateral,
        bytes6 seriesId,
        bytes6 ilkId // We are having a custom one here since we will have different eulerTokens
    ) external returns (bytes12 vaultId) {
        console.log(
            "Start amount",
            IERC20(ilkToAsset[ilkId]).balanceOf(address(this)) / 1e18
        );
        address eulerToken = markets.underlyingToEToken(ilkToAsset[ilkId]);
        // Transfer the tokens from user based on the ilk
        IERC20(eulerToken).safeTransferFrom(
            msg.sender,
            address(this),
            baseAmount
        );

        // Build vault
        (vaultId, ) = ladle.build(seriesId, ilkId, 0);

        // Encode data of
        // OperationType    1 byte      [0:1]
        // seriesId         6 bytes     [1:7]
        // ilkId            6 bytes     [7:13]
        // vaultId          12 bytes    [13:25]
        // baseAmount       16 bytes    [25:41]
        // minCollateral    16 bytes    [41:57]
        bytes memory data = bytes.concat(
            bytes1(uint8(uint256(Operation.LEVER_UP))),
            seriesId,
            ilkId,
            vaultId,
            bytes16(baseAmount),
            bytes16(minCollateral)
        );

        bool success = flashJoins[ilkId].flashLoan(
            this, // Loan Receiver
            ilkToAsset[ilkId], // Loan Token
            borrowAmount, // Loan Amount
            data
        );

        if (!success) revert FlashLoanFailure();
        giver.give(vaultId, msg.sender);
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
    ) external override returns (bytes32) {
        Operation status = Operation(uint256(uint8(data[0])));
        bytes6 seriesId = bytes6(data[1:7]);
        bytes6 ilkId = bytes6(data[7:13]);

        // We trust the lender, so now we can check that we were the initiator.
        if (initiator != address(this)) revert FlashLoanFailure();

        // Decode the operation to execute and then call that function.
        if (status == Operation.LEVER_UP) {
            bytes12 vaultId = bytes12(data[13:25]);
            uint128 baseAmount = uint128(uint128(bytes16(data[25:41])));
            uint256 minCollateral = uint128(bytes16(data[41:57]));
            leverUp(
                borrowAmount,
                fee,
                baseAmount,
                minCollateral,
                vaultId,
                seriesId,
                ilkId
            );
        } else if (status == Operation.REPAY) {
            bytes12 vaultId = bytes12(data[13:25]);
            uint128 ink = uint128(bytes16(data[25:41]));
            uint128 art = uint128(bytes16(data[41:57]));
            doRepay(
                uint128(borrowAmount + fee),
                vaultId,
                ilkId,
                ink,
                art,
                seriesId
            );
        } else if (status == Operation.CLOSE) {
            bytes12 vaultId = bytes12(data[13:25]);
            uint128 ink = uint128(bytes16(data[25:41]));
            uint128 art = uint128(bytes16(data[41:57]));

            doClose(vaultId, ink, art, ilkId);
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
        bytes6 seriesId,
        bytes6 ilkId
    ) internal {
        baseAmount += uint128(borrowAmount - fee);
        // Deposit to get Euler token in return which would be used to payback flashloan
        // Get the eToken address using the markets module:

        IEulerEToken eToken = IEulerEToken(
            markets.underlyingToEToken(ilkToAsset[ilkId])
        );

        eToken.deposit(0, borrowAmount - fee);

        uint256 eBalance = IERC20(address(eToken)).balanceOf(address(this));

        IERC20(address(eToken)).transfer(address(ladle.joins(ilkId)), eBalance);

        _pourAndSell(vaultId, eBalance, borrowAmount - fee, seriesId);
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
            int128(pool.buyBasePreview(uint128(borrowAmount)))
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
                bytes16(art) // [41:57]
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
            address asset = ilkToAsset[ilkId];
            // Close:
            // Series is not past maturity.
            // Borrow to repay debt, move directly to the pool.
            bytes memory data = bytes.concat(
                bytes1(bytes1(uint8(uint256(Operation.CLOSE)))), // [0:1]
                seriesId, // [1:7]
                ilkId, // [7:13]
                vaultId, // [13:25]
                bytes16(ink), // [25:41]
                bytes16(art) // [41:57]
            );

            bool success = flashJoins[ilkId].flashLoan(
                this, // Loan Receiver
                asset, // Loan Token
                art, // Loan Amount
                data
            );

            if (!success) revert FlashLoanFailure();
            uint256 balance = IERC20(asset).balanceOf(address(this));

            if (balance > 0) IERC20(asset).safeTransfer(msg.sender, balance);
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
    function doRepay(
        uint128 borrowAmountPlusFee, // Amount of FYToken received
        bytes12 vaultId,
        bytes6 ilkId,
        uint128 ink,
        uint128 art,
        bytes6 seriesId
    ) internal {
        // Repay the vault, get collateral back.
        ladle.pour(vaultId, address(this), -int128(ink), -int128(art));

        IEulerEToken eToken = IEulerEToken(
            markets.underlyingToEToken(ilkToAsset[ilkId])
        );

        eToken.withdraw(0, type(uint256).max);

        // buyFyToken
        IPool pool = IPool(ladle.pools(seriesId));
        uint128 tokenToTran = pool.buyFYTokenPreview(borrowAmountPlusFee);

        IERC20(ilkToAsset[ilkId]).safeTransfer(address(pool), tokenToTran);

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
        uint128 art,
        bytes6 ilkId
    ) internal {
        ladle.close(vaultId, address(this), -int128(ink), -int128(art));

        IEulerEToken eToken = IEulerEToken(
            markets.underlyingToEToken(ilkToAsset[ilkId])
        );

        eToken.withdraw(0, type(uint256).max);
    }
}
