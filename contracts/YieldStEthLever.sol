// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
// import "@yield-protocol/vault-interfaces/src/ILadle.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/vault-interfaces/src/DataTypes.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/vault-v2/other/lido/StEthConverter.sol";
import "@yield-protocol/vault-v2/utils/Giver.sol";
import "@yield-protocol/vault-v2/FlashJoin.sol";
import "./interfaces/IStableSwap.sol";

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
    IERC3156FlashLender fyToken;
    YieldLadle constant ladle =
        YieldLadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    ICauldron constant cauldron =
        ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    IStableSwap stableSwap =
        IStableSwap(0x828b154032950C8ff7CF8085D841723Db2696056);
    StEthConverter constant stEthConverter =
        StEthConverter(0x93D232213cCA6e5e7105199ABD8590293C3eb106);
    bytes6 constant ilkId = bytes6(0x303400000000); //wsteth
    FlashJoin constant flashJoin =
        FlashJoin(0x5364d336c2d2391717bD366b29B6F351842D7F82);
    IPool pool = IPool(0xc3348D8449d13C364479B1F114bcf5B73DFc0dc6);
    Giver giver;
    address constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant steth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    FlashJoin constant flashJoin2 =
        FlashJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0); //WETH JOIN

    constructor(IERC3156FlashLender fyToken_, Giver giver_) {
        giver = giver_;
        fyToken = fyToken_;

        IERC20(address(fyToken_)).approve(address(pool), type(uint256).max);
        pool.base().approve(address(stableSwap), type(uint256).max);
        IERC20(wsteth).approve(address(stableSwap), type(uint256).max); //wsteth
        IERC20(steth).approve(address(stableSwap), type(uint256).max); //steth
        IERC20(weth).approve(
            0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0, //join
            type(uint256).max
        ); //weth
        IERC20(wsteth).approve(
            0x5364d336c2d2391717bD366b29B6F351842D7F82, //flashjoin
            type(uint256).max
        ); //wsteth
    }

    function invest(
        uint256 baseAmount,
        uint128 borrowAmount,
        bytes6 seriesId
    ) external returns (bytes12) {
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
            abi.encode(0, abi.encode(borrowAmount, vaultId))
        );
        require(success, "Failed to flash loan");
        giver.give(vaultId, msg.sender);
        IERC20(address(fyToken)).transfer(
            msg.sender,
            IERC20(address(fyToken)).balanceOf(address(this))
        );
        return vaultId;
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount, // Amount of FYToken received
        uint256 fee,
        bytes memory data
    ) external returns (bytes32) {
        address thisAdd = address(this);
        require(
            initiator == thisAdd,
            "FlashBorrower: Untrusted loan initiator"
        );

        (uint128 status, bytes memory data2) = abi.decode(
            data,
            (uint128, bytes)
        );
        if (status == 0) {
            leverUp(
                amount, // Amount of FYToken received
                fee,
                data2
            );
        } else if (status == 1) {
            doRepay(amount, fee, data2);
        } else if (status == 2) {
            doClose(amount, fee, data2);
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function leverUp(
        uint256 amount, // Amount of FYToken received
        uint256 fee,
        bytes memory data
    ) internal {
        address thisAdd = address(this);

        (uint128 borrowAmount, bytes12 vaultId) = abi.decode(
            data,
            (uint128, bytes12)
        );
        IERC20(address(fyToken)).transfer(address(pool), amount - fee);

        // Get WETH
        uint128 baseReceived = pool.buyBase(
            thisAdd,
            uint128(pool.sellFYTokenPreview(uint128(amount - fee))),
            uint128(amount - fee)
        );
        // Swap WETH for stETH on curve
        // 0: WETH
        // 1: STETH
        uint256 stethReceived = stableSwap.exchange(
            0,
            1,
            pool.base().balanceOf(thisAdd), // This value is different from base received
            1,
            address(stEthConverter)
        );

        // Wrap steth to wsteth
        uint256 wrappedamount = stEthConverter.wrap(
            0x5364d336c2d2391717bD366b29B6F351842D7F82
        );

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
                    1,
                    abi.encode(msg.sender, vaultId, maxAmount, ink, art)
                )
            );

            // Transferring the leftover to the user
            IERC20(address(fyToken)).transfer(
                msg.sender,
                IERC20(address(fyToken)).balanceOf(address(this))
            );
        } else {
            // Series is past maturity, borrow and move directly to collateral pool
            uint128 base = cauldron.debtToBase(seriesId, art);
            bytes memory data = abi.encode(
                msg.sender,
                vaultId,
                maxAmount,
                base,
                ink,
                art
            );
            success = flashJoin.flashLoan(
                this, // Loan Receiver
                wsteth, // Loan Token
                base, // Loan Amount
                abi.encode(2, data)
            );

            // Transferring the leftover to the user
            IERC20(wsteth).transfer(
                msg.sender,
                IERC20(wsteth).balanceOf(address(this))
            );
        }
        require(success, "Failed to flash loan");

        // Give the vault back to the sender, just in case there is anything left
        giver.give(vaultId, msg.sender);
    }

    function doRepay(
        uint256 amount, // Amount of FYToken received
        uint256 fee,
        bytes memory data
    ) internal {
        (address borrower, bytes12 vaultId, , uint128 ink, uint128 art) = abi
            .decode(data, (address, bytes12, uint256, uint128, uint128));

        IERC20(address(fyToken)).approve(address(ladle), art);
        ladle.pour(
            vaultId,
            address(this),
            -int128(ink),
            -int128(uint128(art)) // How much could I borrow?
        );

        // Convert wsteth - steth
        IERC20(wsteth).transfer(address(stEthConverter), ink);
        stEthConverter.unwrap(address(this));
        // convert steth- weth
        // 0: WETH
        // 1: STETH
        stableSwap.exchange(
            1,
            0,
            IERC20(steth).balanceOf(address(this)), // balance of steth
            1,
            address(pool)
        );
        uint128 wethToTran = pool.buyFYTokenPreview(uint128(amount + fee));
        // IERC20(weth).transfer(address(pool), wethToTran);
        pool.sellBase(address(this), wethToTran);
        // Transferring the leftover to the borrower
        IERC20(weth).transfer(borrower, IERC20(weth).balanceOf(address(this)));
    }

    function doClose(
        uint256 amount, // Amount of FYToken received
        uint256 fee,
        bytes memory data
    ) internal {
        (
            address owner,
            bytes12 vaultId,
            uint256 maxAmount,
            uint128 base,
            uint128 ink,
            uint128 art
        ) = abi.decode(
                data,
                (address, bytes12, uint256, uint128, uint128, uint128)
            );

        // Convert wsteth - steth
        IERC20(wsteth).transfer(address(stEthConverter), maxAmount);
        stEthConverter.unwrap(address(this));
        // convert steth- weth
        // 1: STETH
        // 0: WETH
        stableSwap.exchange(
            1,
            0,
            IERC20(steth).balanceOf(address(this)), // balance of steth
            1,
            address(this)
        );

        ladle.close(vaultId, address(this), -int128(ink), -int128(art));
    }
}
