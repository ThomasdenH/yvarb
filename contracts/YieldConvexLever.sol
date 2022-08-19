// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./interfaces/IStableSwap.sol";
import "./YieldLeverBase.sol";

interface IConvexPool {
    function depositAll(uint256 _pid, bool _stake) external returns (bool);

    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);

    function withdrawTo(
        uint256 _pid,
        uint256 _amount,
        address _to
    ) external returns (bool);
}

interface IConvexJoin {
    function addVault(bytes12 vaultId) external;

    function removeVault(bytes12 vaultId, address account) external;
}

contract YieldConvexLever is YieldLeverBase {
    using TransferHelper for IERC20;
    using TransferHelper for IFYToken;

    IStableSwap constant threecrvPool =
        IStableSwap(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    IConvexPool constant convexDeposit =
        IConvexPool(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant THREECRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address constant CVX3CRV = 0x30D9410ED1D5DA1F6C8391af5338C93ab8d4035C;

    constructor(Giver giver_) YieldLeverBase(giver_) {
        IERC20(USDC).approve(address(threecrvPool), type(uint256).max);
        IERC20(DAI).approve(address(threecrvPool), type(uint256).max);
        IERC20(USDC).approve(
            address(LADLE.joins(0x303200000000)),
            type(uint256).max
        );
        IERC20(DAI).approve(
            address(LADLE.joins(0x303100000000)),
            type(uint256).max
        );
        IERC20(THREECRV).approve(address(convexDeposit), type(uint256).max);
        IERC20(CVX3CRV).approve(address(convexDeposit), type(uint256).max);
    }

    /// @notice This function is called from within the flash loan.
    /// @param ilkId The id of the ilk being borrowed.
    /// @param seriesId The pool (and thereby series) to borrow from.
    /// @param vaultId The vault id to put collateral into and borrow from.
    /// @param borrowAmount The amount of FYWeth borrowed in the flash loan.
    /// @param fee The fee that will be issued by the flash loan.
    /// @param baseAmount The amount of own collateral to supply.
    function borrow(
        bytes6 ilkId,
        bytes6 seriesId,
        bytes12 vaultId,
        uint128 baseAmount,
        uint256 borrowAmount,
        uint256 fee
    ) internal override {
        // Add vault
        IConvexJoin(address(LADLE.joins(ilkId))).addVault(vaultId);
        // We have borrowed FyTokens, so sell those
        IPool pool = IPool(LADLE.pools(seriesId));
        IFYToken tempFyToken = pool.fyToken();
        tempFyToken.safeTransfer(address(pool), borrowAmount);
        uint128 totalToInvest = baseAmount +
            uint128(pool.sellFYToken(address(this), 0));

        // Deposit in curve pool to get 3CRV
        uint256[] memory amounts = new uint256[](3);
        // amounts[0] = 0;
        // amounts[1] = 0;
        // amounts[2] = 0;
        address underlying = tempFyToken.underlying();

        if (underlying == USDC) amounts[1] = totalToInvest - baseAmount;
        else if (underlying == DAI) amounts[0] = totalToInvest - baseAmount;
        else revert();
        (bool success, bytes memory data) = address(threecrvPool).call(
            abi.encodeWithSignature(
                "add_liquidity(uint256[3],uint256)",
                [totalToInvest - baseAmount, 0, 0], //TODO: pass it correctly & not hardcode
                0
            )
        );
        // threecrvPool.add_liquidity(amounts, 0); //TODO: Figure out what should be 0 & how to use this & not the call function
        // Deposit in convex to get cvx3CRV
        convexDeposit.depositAll(9, false); // 9 is the pool ID
        // POUR to get fyToken back & repay the flash loan
        _pour(ilkId, vaultId, borrowAmount, fee);
    }

    function _pour(
        bytes6 ilkId,
        bytes12 vaultId,
        uint256 borrowAmount,
        uint256 fee
    ) internal {
        uint256 transferAmount = IERC20(CAULDRON.assets(ilkId)).balanceOf(
            address(this)
        );
        IERC20(CVX3CRV).safeTransfer(
            address(LADLE.joins(ilkId)),
            transferAmount
        );
        LADLE.pour(
            vaultId,
            address(this),
            int128(uint128(transferAmount)),
            int128(uint128(borrowAmount + fee))
        );
    }

    /// @param ilkId The id of the ilk being invested.
    /// @param seriesId The seriesId corresponding to the vault.
    /// @param vaultId The vault to repay.
    /// @param borrowAmountPlusFee The amount of fyDai/fyUsdc that we have borrowed,
    ///     plus the fee. This should be our final balance.
    /// @param ink The amount of collateral to retake.
    /// @param art The debt to repay.
    ///     slippage.
    function repay(
        bytes6 ilkId,
        bytes12 vaultId,
        bytes6 seriesId,
        uint128 borrowAmountPlusFee,
        uint128 ink,
        uint128 art
    ) internal override {
        // Repay the vault, get collateral back.
        LADLE.pour(vaultId, address(this), -int128(ink), -int128(art));
        // Unstake from convex to get 3crv
        convexDeposit.withdraw(9, IERC20(CVX3CRV).balanceOf(address(this)));

        IPool pool = IPool(LADLE.pools(seriesId));
        if (address(pool.base()) == USDC)
            threecrvPool.remove_liquidity_one_coin(
                IERC20(THREECRV).balanceOf(address(this)),
                1,
                0
            );
        else if (address(pool.base()) == DAI)
            threecrvPool.remove_liquidity_one_coin(
                IERC20(THREECRV).balanceOf(address(this)),
                0,
                0
            );

        uint128 tokenToTran = pool.buyFYTokenPreview(borrowAmountPlusFee);

        pool.base().safeTransfer(address(pool), tokenToTran);
        // buyFyToken
        pool.buyFYToken(address(this), borrowAmountPlusFee, tokenToTran);
    }

    /// @notice Close a vault after maturity.
    /// @param ilkId The id of the ilk.
    /// @param vaultId The ID of the vault to close.
    /// @param ink The collateral to take from the vault.
    /// @param art The debt to repay. This is denominated in fyTokens, even
    ///     though the payment is done in terms of WEth.
    function close(
        bytes6 ilkId,
        bytes12 vaultId,
        uint128 ink,
        uint128 art
    ) internal override {
        // IPool pool = IPool(LADLE.pools(seriesId));
        LADLE.close(vaultId, address(this), -int128(ink), -int128(art));
        // Unstake from convex to get 3crv
        convexDeposit.withdraw(9, IERC20(CVX3CRV).balanceOf(address(this)));

        //TODO: how to identify base??
        // Unstake on curve to get ilkId
        // if (pool.base() == USDC)
        //     threecrvPool.remove_liquidity_one_coin(
        //         IERC20(THREECRV).balanceOf(address(this)),
        //         1,
        //         0
        //     );
        // else if (pool.base() == DAI)
        threecrvPool.remove_liquidity_one_coin(
            IERC20(THREECRV).balanceOf(address(this)),
            0,
            0
        );
        // else revert();
    }
}
