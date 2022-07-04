// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./YieldLeverBase.sol";
import "./NotionalTypes.sol";
import "forge-std/console.sol";

interface BatchAction {
    function batchBalanceAndTradeAction(
        address account,
        BalanceActionWithTrades[] calldata actions
    ) external;
}

// Flash borrow USDC/DAI
// Deposit to get the fCash
// Deposit fCash & borrow fyToken
// Sell fyToken to get USDC/DAI
// Repay flash loan

contract YieldNotionalLever is YieldLeverBase {
    FlashJoin usdcJoin;
    FlashJoin daiJoin;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant notional = 0x1344A36A1B56144C3Bc62E7757377D288fDE0369;
    mapping(bytes6 => bytes1) ilkToUnderlying;

    constructor(
        Giver giver_,
        address usdcJoin_,
        address daiJoin_
    ) YieldLeverBase(giver_) {
        usdcJoin = FlashJoin(usdcJoin_);
        daiJoin = FlashJoin(daiJoin_);

        IERC20(USDC).approve(usdcJoin_, type(uint256).max);
        IERC20(DAI).approve(daiJoin_, type(uint256).max);
        IERC20(USDC).approve(notional, type(uint256).max);
    }

    // TODO: Make it auth controlled when deploying
    function setIlkToUnderlying(bytes6 ilkId, bytes1 under) external {
        ilkToUnderlying[ilkId] = under;
    }

    function invest(
        uint128 baseAmount,
        uint128 borrowAmount,
        uint128 minCollateral,
        bytes6 seriesId,
        bytes6 ilkId
    ) external returns (bytes12 vaultId) {
        (vaultId, ) = ladle.build(seriesId, ilkId, 0);
        // Since we know the sizes exactly, packing values in this way is more
        // efficient than using `abi.encode`.
        //
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

        bool success;
        if (ilkToUnderlying[ilkId] == 0x01) {
            // USDC

            success = usdcJoin.flashLoan(this, USDC, borrowAmount, data);
        } else {
            // DAI
            success = daiJoin.flashLoan(this, DAI, borrowAmount, data);
        }
        if (!success) revert FlashLoanFailure();
        giver.give(vaultId, msg.sender);
    }

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
            if (ilkToUnderlying[ilkId] == 0x01) {
                // USDC
                leverUp(
                    borrowAmount,
                    fee,
                    baseAmount,
                    minCollateral,
                    vaultId,
                    seriesId,
                    ilkId
                );
            } else {
                // DAI
            }
        } else if (status == Operation.REPAY) {} else if (
            status == Operation.CLOSE
        ) {}
        return FLASH_LOAN_RETURN;
    }

    function leverUp(
        uint256 borrowAmount,
        uint256 fee,
        uint128 baseAmount,
        uint256 minCollateral,
        bytes12 vaultId,
        bytes6 seriesId,
        bytes6 ilkId
    ) internal {
        // Deposit into notional to get the fCash
        BalanceActionWithTrades[]
            memory actions = new BalanceActionWithTrades[](1);
        bytes32[] memory trade = new bytes32[](1);
        trade[0] = encodeLendTrade(3,10e6,0);
        actions[0] = BalanceActionWithTrades({
            actionType: DepositActionType.DepositUnderlying, // Deposit USDC, not cUSDC
            currencyId: 3, // USDC
            depositActionAmount: 100e6, // Specified in USDC 6 decimal precision
            withdrawAmountInternalPrecision: 0,
            withdrawEntireCashBalance: true, // Return all residual cash to lender
            redeemToUnderlying: true, // Convert cUSDC to USDC
            trades: trade // Example on how to specify this below
        });
        
        address(notional).call(
            abi.encodeWithSelector(
                BatchAction.batchBalanceAndTradeAction.selector,
                address(this),
                actions
            )
        );

        // BatchAction(0xA9597DEa21e9D7839Ad0A1A7Dad0842A9C2f4C84).batchBalanceAndTradeAction(address(this),actions);
        // Pour fCash & borrow to get fyToken
        // Sell fyToken to get DAI/USDC to repay the flash loan
    }
}
