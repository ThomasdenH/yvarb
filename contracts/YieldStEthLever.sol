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

error FlashLoanFailure();

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

contract YieldStEthLever is IERC3156FlashBorrower {

    using TransferHelper for IERC20;
    using TransferHelper for FyToken;

    /// @notice The encoding of the operation to execute.
    enum OperationType {
        LEVER_UP,
        REPAY,
        CLOSE
    }

    FyToken immutable fyToken;
    YieldLadle constant ladle =
        YieldLadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    ICauldron constant cauldron =
        ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    /// @notice Curve.fi token swapping contract between Ether and stETH.
    IStableSwap stableSwap =
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
    IPool pool = IPool(0xc3348D8449d13C364479B1F114bcf5B73DFc0dc6);
    Giver immutable giver;
    IERC20 constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant wsteth = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 constant steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    constructor(FyToken fyToken_, Giver giver_) {
        giver = giver_;
        fyToken = fyToken_;

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
    /// @param seriesId The series to create the vault for.
    function invest(
        uint128 baseAmount,
        uint128 borrowAmount,
        bytes6 seriesId
    ) external returns (bytes12) {
        fyToken.safeTransferFrom(
            msg.sender,
            address(this),
            baseAmount
        );
        (bytes12 vaultId, ) = ladle.build(seriesId, ilkId, 0);
        bool success = fyToken.flashLoan(
            this, // Loan Receiver
            address(fyToken), // Loan Token
            borrowAmount, // Loan Amount
            abi.encode(
                OperationType.LEVER_UP,
                abi.encode(baseAmount, vaultId)
            )
        );
        if (!success) revert FlashLoanFailure();
        giver.give(vaultId, msg.sender);
        return vaultId;
    }

    /// @param initiator The initator of the flash loan, must be `address(this)`.
    /// @param borrowAmount The amount of fyTokens borrowed.
    function onFlashLoan(
        address initiator,
        address, // token
        uint256 borrowAmount, // Amount of FYToken received
        uint256 fee,
        bytes memory data
    ) external returns (bytes32) {
        // Test that the flash loan was sent from the lender contract and that
        // this contract was the initiator.
        if (
            (msg.sender != address(fyToken) &&
                msg.sender != address(flashJoin)) || initiator != address(this)
        ) revert FlashLoanFailure();

        // Decode the operation to execute
        (OperationType status, bytes memory data2) = abi.decode(
            data,
            (OperationType, bytes)
        );
        if (status == OperationType.LEVER_UP) {
            leverUp(
                borrowAmount, // Amount of FYToken received
                fee,
                data2
            );
        } else if (status == OperationType.REPAY) {
            doRepay(uint128(borrowAmount) + uint128(fee), data2);
        } else if (status == OperationType.CLOSE) {
            doClose(data2);
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function leverUp(
        uint256 borrowAmount, // Amount of FYToken received
        uint256 fee,
        bytes memory data
    ) internal {
        address thisAdd = address(this);

        (uint128 baseAmount, bytes12 vaultId) = abi.decode(
            data,
            (uint128, bytes12)
        );
        // The total amount to invest. Equal to the base, the borrowed minus the flash loan fee.
        uint128 netInvestAmount = baseAmount + uint128(borrowAmount - fee);
        fyToken.safeTransfer(address(pool), netInvestAmount);

        // Get WETH
        // uint128 baseReceived = 
        pool.buyBase(
            thisAdd,
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
            pool.base().balanceOf(thisAdd), // This value is different from base received
            1,
            address(stEthConverter)
        );

        // Wrap steth to wsteth
        uint256 wrappedamount = stEthConverter.wrap(address(flashJoin));
        // Deposit wstETH in the vault & borrow fyToken to payback
        ladle.pour(
            vaultId,
            thisAdd,
            int128(uint128(wrappedamount)),
            int128(uint128(borrowAmount))
        );
    }

    function unwind(
        bytes12 vaultId,
        uint256 maxAmount,
        uint128 ink,
        uint128 art,
        bytes6 seriesId
    ) external {
        DataTypes.Vault memory vault_ = cauldron.vaults(vaultId);
        DataTypes.Series memory series_ = cauldron.series(seriesId);

        // Test that the caller is the owner of the vault.
        // This is important as we will take the vault from the user.
        require(vault_.owner == msg.sender);

        // Give the vault to the contract
        giver.seize(vaultId, address(this));
        bool success;
        if (uint32(block.timestamp) < series_.maturity) {
            // Series is not past maturity
            // Borrow to repay debt, move directly to the pool.
            success = fyToken.flashLoan(
                this, // Loan Receiver
                address(fyToken), // Loan Token
                maxAmount, // Loan Amount
                abi.encode(
                    OperationType.REPAY,
                    abi.encode(msg.sender, vaultId, ink, art)
                )
            );
        } else {
            // Series is past maturity, borrow and move directly to collateral pool
            uint128 base = cauldron.debtToBase(seriesId, art);
            bytes memory data = abi.encode(
                vaultId,
                maxAmount,
                ink,
                art
            );
            success = flashJoin.flashLoan(
                this, // Loan Receiver
                address(wsteth), // Loan Token
                base, // Loan Amount
                abi.encode(OperationType.CLOSE, data)
            );
        }
        if (!success) revert FlashLoanFailure();

        // Give the vault back to the sender, just in case there is anything left
        giver.give(vaultId, msg.sender);
        // Transferring the leftover to the borrower
        fyToken.safeTransfer(
            msg.sender,
            fyToken.balanceOf(address(this))
        );
    }

    function doRepay(
        uint128 borrowAmountPlusFee, // Amount of FYToken received
        bytes memory data
    ) internal {
        (address borrower, bytes12 vaultId, uint128 ink, uint128 art) = abi
            .decode(data, (address, bytes12, uint128, uint128));

        fyToken.approve(address(ladle), art);
        ladle.pour(
            vaultId,
            address(this),
            -int128(ink),
            -int128(uint128(art)) // How much could I borrow?
        );

        // Convert wsteth - steth
        wsteth.safeTransfer(address(stEthConverter), ink);
        stEthConverter.unwrap(address(this));
        // convert steth- weth
        // 0: WETH
        // 1: STETH
        stableSwap.exchange(
            1,
            0,
            steth.balanceOf(address(this)), // balance of steth
            1,
            address(pool)
        );
        uint128 wethToTran = pool.buyFYTokenPreview(borrowAmountPlusFee);
        // weth.transfer(address(pool), wethToTran);
        pool.sellBase(address(this), wethToTran);
        // Transferring the leftover to the borrower
        weth.safeTransfer(borrower, weth.balanceOf(address(this)));
    }

    function doClose(
        bytes memory data
    ) internal {
        (
            bytes12 vaultId,
            uint256 maxAmount,
            uint128 ink,
            uint128 art
        ) = abi.decode(
                data,
                (bytes12, uint256, uint128, uint128)
            );

        // Convert wsteth - steth
        wsteth.safeTransfer(address(stEthConverter), maxAmount);
        stEthConverter.unwrap(address(this));
        // convert steth- weth
        // 0: WETH
        // 1: STETH
        stableSwap.exchange(
            1,
            0,
            steth.balanceOf(address(this)), // balance of steth
            1,
            address(this)
        );

        ladle.close(vaultId, address(this), -int128(ink), -int128(art));
    }
}
