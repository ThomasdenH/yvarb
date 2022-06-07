// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "yieldspace-interfaces/IPool.sol";
import "vault-interfaces/ILadle.sol";
import "vault-interfaces/ICauldron.sol";
import "yield-utils-v2/token/IERC20.sol";
import "./interfaces/IStableSwap.sol";

contract YieldStEthLever is IERC3156FlashBorrower {
    IERC3156FlashLender fyToken;
    ILadle constant ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    ICauldron constant cauldron =
        ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    IStableSwap stableSwap =
        IStableSwap(0x828b154032950C8ff7CF8085D841723Db2696056);
    bytes6 constant ilkId = bytes6(0x303000000000);
    IPool pool = IPool(0xc3348D8449d13C364479B1F114bcf5B73DFc0dc6);

    constructor(IERC3156FlashLender fyToken_) public {
        fyToken = fyToken_;
    }

    function invest(
        uint256 baseAmount,
        uint128 borrowAmount,
        uint128 maxFyAmount,
        bytes6 seriesId
    ) external {
        (bytes12 vaultId, ) = ladle.build(seriesId, ilkId, 0);
        uint256 investAmount = baseAmount + borrowAmount;
        fyToken.flashLoan(
            this,
            address(fyToken),
            investAmount,
            abi.encode(investAmount, borrowAmount, maxFyAmount, vaultId)
        );
        cauldron.give(vaultId, msg.sender);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount, // Amount of FYToken received
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        require(
            msg.sender == address(fyToken),
            "FlashBorrower: Untrusted lender"
        );
        require(
            initiator == address(this),
            "FlashBorrower: Untrusted loan initiator"
        );

        (
            uint256 investAmount,
            uint128 borrowAmount,
            uint128 maxFyAmount,
            bytes12 vaultId
        ) = abi.decode(data, (uint256, uint128, uint128, bytes12));

        // Get WETH
        pool.buyBase(address(this), borrowAmount, uint128(amount));
        // Swap WETH for stETH on curve
        // 0: WETH
        // 1: STETH
        stableSwap.exchange(0, 1, borrowAmount, 1);

        // Deposit stETH in the vault & borrow fyToken
        ladle.pour(
            vaultId,
            address(fyToken),
            int128(uint128(investAmount)),
            int128(borrowAmount)
        );

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}