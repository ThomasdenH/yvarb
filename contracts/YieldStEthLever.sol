// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
// import "@yield-protocol/vault-interfaces/src/ILadle.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/vault-v2/other/lido/StEthConverter.sol";
import "@yield-protocol/vault-v2/utils/Giver.sol";
import "@yield-protocol/vault-v2/FlashJoin.sol";
import "./interfaces/IStableSwap.sol";
import "forge-std/Test.sol";

error FlashLoanFailure();
error SlippageFailure();

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

interface FyToken is IERC3156FlashLender, IERC20 {}

contract YieldStEthLever is IERC3156FlashBorrower, Test {
    using TransferHelper for IERC20;
    using TransferHelper for FyToken;

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
    IERC20 constant wsteth = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 constant steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    FyToken immutable fyToken;
    Giver immutable giver;

    constructor(FyToken fyToken_, Giver giver_) {
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
        IERC20(address(fyToken)).transfer(
            msg.sender,
            IERC20(address(fyToken)).balanceOf(address(this))
        );
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
                msg.sender != address(flashJoin)) || initiator != address(this)
        ) revert FlashLoanFailure();

        // Decode the operation to execute
        bytes1 status = data[0];
        if (status == 0x01) {
            leverUp(
                borrowAmount, // Amount of FYToken received
                fee,
                data
            );
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
        uint128 netInvestAmount = baseAmount + uint128(borrowAmount - fee);

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
        // uint256 stethReceived =
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
    function unwind(
        uint128 ink,
        uint128 art,
        bytes12 vaultId,
        bytes6 seriesId,
        uint256 minWeth
    ) external {
        // Test that the caller is the owner of the vault.
        // This is important as we will take the vault from the user.
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);
        require(vault_.owner == msg.sender);

        // Give the vault to the contract
        giver.seize(vaultId, address(this));

        DataTypes.Series memory series_ = cauldron.series(seriesId);
        if (uint32(block.timestamp) < series_.maturity) {
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

            // Transferring the leftover to the user
            IERC20(address(fyToken)).transfer(
                msg.sender,
                IERC20(address(fyToken)).balanceOf(address(this))
            );
        } else {
            // CLOSE
            // Series is past maturity, borrow and move directly to collateral pool
            bytes memory data = bytes.concat(
                bytes1(0x03), // [0]
                vaultId, // [1:13]
                bytes16(ink), // [13:29]
                bytes16(art) // [29:45]
            );
            uint128 base = cauldron.debtToBase(seriesId, art);
            bool success = flashJoin.flashLoan(
                this, // Loan Receiver
                address(wsteth), // Loan Token
                base, // Loan Amount
                data
            );
            if (!success) revert FlashLoanFailure();

            // At this point, there may be a remainder of WEth, as well as
            // WStEth. Sell all WStEth for WEth and test if it is sufficient.
            uint256 wethBalance = weth.balanceOf(address(this));
            // How much to obtain from setting WStEth
            uint256 minWethObtainedBySelling = 0;
            if (wethBalance < minWeth) {
                unchecked {
                    minWethObtainedBySelling = minWeth - wethBalance;
                }
            }
            wsteth.safeTransfer(address(stEthConverter), wsteth.balanceOf(address(this)));
            uint256 stEthUnwrapped = stEthConverter.unwrap(address(this));
            uint256 wethObtained = stableSwap.exchange(
                1, // StEth
                0, // WEth
                stEthUnwrapped, // balance of steth
                minWethObtainedBySelling,
                address(this)
            );

            // Transferring the leftover to the user
            IERC20(weth).transfer(msg.sender, wethObtained + wethBalance);
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

        ladle.pour(
            vaultId,
            address(this),
            -int128(ink),
            -int128(art) // How much could I borrow?
        );

        // Convert wsteth - steth
        wsteth.safeTransfer(address(stEthConverter), ink);
        uint256 stEthUnwrapped = stEthConverter.unwrap(address(this));
        // convert steth- weth
        // 0: WETH
        // 1: STETH
        uint256 wethReceived = stableSwap.exchange(
            1,
            0,
            stEthUnwrapped,
            1,
            address(this)
        );

        // Convert weth to FY to repay loan
        uint128 wethToTran = pool.buyFYTokenPreview(borrowAmountPlusFee);
        weth.safeTransfer(address(pool), wethToTran);
        pool.sellBase(address(this), wethToTran);

        // Send remaining weth to user
        uint256 wethRetrieved = wethReceived - wethToTran;
        // assertEq(weth.balanceOf(address(this)), wethRetrieved);
        if (wethRetrieved < minWeth) revert SlippageFailure();
        weth.safeTransfer(borrower, wethRetrieved);
    }

    /// @dev    - We have borrowed WstEth
    ///         - Sell it all for WEth and close position.
    function doClose(uint256 borrowAmount, bytes calldata data) internal {
        bytes12 vaultId = bytes12(data[1:13]);
        uint128 ink = uint128(bytes16(data[13:29]));
        uint128 art = uint128(bytes16(data[29:45]));

        // Convert wsteth - steth
        wsteth.safeTransfer(address(stEthConverter), borrowAmount);
        uint256 stEthUnwrapped = stEthConverter.unwrap(address(this));

        // convert steth- weth
        // 1: STETH
        // 0: WETH
        uint256 wethObtained = stableSwap.exchange(
            1,
            0,
            stEthUnwrapped, // balance of steth
            art, // We want to use it to repay the debt, so we better obtain at least `art`.
            address(this)
        );

        // Close vault. We obtain `ink` StEth, which will be used to repay the
        // loan. The rest is returned to the vault owner in `unwind`.
        ladle.close(vaultId, address(this), -int128(ink), -int128(art));
    }
}
