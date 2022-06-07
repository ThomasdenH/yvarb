// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "@yield-protocol/vault-interfaces/src/ILadle.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/vault-v2/other/lido/StEthConverter.sol";
import "@yield-protocol/vault-v2/utils/Giver.sol";
import "./interfaces/IStableSwap.sol";
import "forge-std/Test.sol";

contract YieldStEthLever is IERC3156FlashBorrower {
    IERC3156FlashLender fyToken;
    ILadle constant ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    IStableSwap stableSwap =
        IStableSwap(0x828b154032950C8ff7CF8085D841723Db2696056);
    StEthConverter constant stEthConverter =
        StEthConverter(0x93D232213cCA6e5e7105199ABD8590293C3eb106);
    bytes6 constant ilkId = bytes6(0x303400000000); //wsteth
    IPool pool = IPool(0xc3348D8449d13C364479B1F114bcf5B73DFc0dc6);
    Giver giver;

    constructor(IERC3156FlashLender fyToken_, Giver giver_) {
        giver = giver_;
        fyToken = fyToken_;
        IERC20(address(fyToken_)).approve(address(pool), type(uint256).max);
        pool.base().approve(address(stableSwap), type(uint256).max);
    }

    function invest(
        uint256 baseAmount,
        uint128 borrowAmount,
        uint128 maxFyAmount,
        bytes6 seriesId
    ) external {
        IERC20(address(fyToken)).transferFrom(
            msg.sender,
            address(this),
            baseAmount
        );
        (bytes12 vaultId, ) = ladle.build(seriesId, ilkId, 0);
        uint256 investAmount = baseAmount + borrowAmount;
        bool success = fyToken.flashLoan(
            this, // Loan Receiver
            address(fyToken), // Loan Token
            investAmount, // Loan Amount
            abi.encode(investAmount, borrowAmount, maxFyAmount, vaultId)
        );
        require(success, "Failed to flash loan");
        giver.give(vaultId, msg.sender);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount, // Amount of FYToken received
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        address thisAdd = address(this);
        require(
            msg.sender == address(fyToken),
            "FlashBorrower: Untrusted lender"
        );
        require(
            initiator == thisAdd,
            "FlashBorrower: Untrusted loan initiator"
        );

        (, uint128 borrowAmount, , bytes12 vaultId) = abi.decode(
            data,
            (uint256, uint128, uint128, bytes12)
        );
        IERC20(address(fyToken)).transfer(address(pool), amount);

        // Get WETH
        uint128 baseReceived = pool.buyBase(
            thisAdd,
            uint128(pool.sellFYTokenPreview(uint128(amount))),
            uint128(amount)
        );
        // Swap WETH for stETH on curve
        // 0: WETH
        // 1: STETH
        uint256 stethReceived = stableSwap.exchange(
            0,
            1,
            pool.base().balanceOf(thisAdd), // This value is different from base received
            1
        );
        console.log(IERC20(address(fyToken)).balanceOf(thisAdd));
        // Wrap steth to wsteth
        IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).transfer(
            address(stEthConverter),
            stethReceived
        );
        uint256 wrappedamount = stEthConverter.wrap(
            0x5364d336c2d2391717bD366b29B6F351842D7F82
        );
        // Deposit wstETH in the vault & borrow fyToken
        ladle.pour(
            vaultId,
            thisAdd,
            int128(uint128(wrappedamount)),
            int128(uint128(borrowAmount)) // How much could I borrow?
        );
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    // function unwind(
    //     bytes12 vaultId,
    //     uint256 maxAmount,
    //     uint128 ink,
    //     uint128 art,
    //     bytes6 seriesId
    // ) external {
    //     Vault memory vault_ = cauldron.vaults(vaultId);
    //     Series memory series_ = cauldron.series(seriesId);

    //     // Test that the caller is the owner of the vault.
    //     // This is important as we will take the vault from the user.
    //     require(vault_.owner == msg.sender);

    //     // Give the vault to the contract
    //     giver.give(vaultId, address(this));

    //     if (uint32(block.timestamp) < series_.maturity) {
    //         // Series is not past maturity
    //         // Borrow to repay debt, move directly to the pool.
    //         iUSDC.flashBorrow(
    //             maxAmount,
    //             pool,
    //             address(this),
    //             "",
    //             abi.encodeWithSignature(
    //                 "doRepay(address,bytes12,uint256,uint128)",
    //                 msg.sender,
    //                 vaultId,
    //                 maxAmount,
    //                 ink
    //             )
    //         );
    //     } else {
    //         // Series is past maturity, borrow and move directly to collateral pool
    //         uint128 base = cauldron.debtToBase(seriesId, art);
    //         iUSDC.flashBorrow(
    //             base,
    //             usdcJoin,
    //             address(this),
    //             "",
    //             abi.encodeWithSignature(
    //                 "doClose(address,bytes12,uint128,uint128,uint128)",
    //                 msg.sender,
    //                 vaultId,
    //                 base,
    //                 ink,
    //                 art
    //             )
    //         );
    //     }

    //     // Give the vault back to the sender, just in case there is anything left
    //     giver.give(vaultId, msg.sender);
    // }
}
