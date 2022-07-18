// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/YieldNotionalLever.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/vault-v2/FYToken.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "./Protocol.sol";
import "@yield-protocol/vault-v2/utils/Giver.sol";
import "@yield-protocol/vault-v2/FlashJoin.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";

abstract contract ZeroState is Test {
    address timeLock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    address usdcWhale = 0x72A53cDBBcc1b9efa39c834A540550e23463AAcB;
    address daiWhale = 0xaD0135AF20fa82E106607257143d0060A7eB5cBf;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    Protocol protocol;
    Giver giver;
    YieldNotionalLever lever;
    ICauldron cauldron;
    FlashJoin daiJoin;
    FlashJoin usdcJoin;

    bytes6 seriesId = 0x303230370000;
    bytes6 ilkId = 0x313700000000;

    FYToken immutable fyToken;

    constructor() {
        protocol = new Protocol();
        cauldron = ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
        daiJoin = FlashJoin(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc); // dai
        usdcJoin = FlashJoin(0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4); // usdc
        fyToken = FYToken(0x53C2a1bA37FF3cDaCcb3EA030DB3De39358e5593);
        giver = new Giver(cauldron);
        // Orchestrate Giver
        AccessControl cauldronAccessControl = AccessControl(
            0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867
        );
        vm.prank(timeLock);
        cauldronAccessControl.grantRole(0x798a828b, address(giver));

        vm.label(address(address(daiJoin)), "dai Join");
        vm.label(address(address(usdcJoin)), "usdc Join");
        vm.label(
            address(0x1344A36A1B56144C3Bc62E7757377D288fDE0369),
            "Notional"
        );
        vm.label(
            address(0xA9597DEa21e9D7839Ad0A1A7Dad0842A9C2f4C84),
            "BatchAction"
        );

        vm.label(
            address(0x0Bfd3B8570A4247157c5468861d37dA55AAb9B4b),
            "Notional Join USDC"
        );
        vm.label(
            address(0x399bA81A1f1Ed0221c39179C50d4d4Bc85C3F3Ab),
            "Notional Join DAI"
        );
        vm.label(
            address(0x53C2a1bA37FF3cDaCcb3EA030DB3De39358e5593),
            "FYTOKEN SEP2022"
        );
        vm.label(address(0xf5Fd5A9Db9CcCc6dc9f5EF1be3A859C39983577C), "POOL");

        vm.prank(usdcWhale);
        IERC20(USDC).transfer(address(this), 2000e6);
        vm.prank(daiWhale);
        IERC20(DAI).transfer(address(this), 2000e18);

        vm.prank(timeLock);
        usdcJoin.setFlashFeeFactor(1);
        vm.prank(timeLock);
        daiJoin.setFlashFeeFactor(1);

        vm.prank(timeLock);
        fyToken.setFlashFeeFactor(1); // FUSDC2209

        vm.prank(timeLock);
        FYToken(0xFCb9B8C5160Cf2999f9879D8230dCed469E72eeb).setFlashFeeFactor(
            1
        ); // FDAI2209
    }

    function setUp() public virtual {
        lever = new YieldNotionalLever(giver);
        vm.label(address(lever), "LEVER");

        IERC20(USDC).approve(address(lever), type(uint256).max);
        IERC20(DAI).approve(address(lever), type(uint256).max);

        // USDC
        lever.setIlkInfo(
            0x313700000000,
            YieldNotionalLever.IlkInfo({
                join: usdcJoin,
                maturity: 1664064000,
                currencyId: 3
            })
        );

        // DAI
        lever.setIlkInfo(
            0x313600000000,
            YieldNotionalLever.IlkInfo({
                join: daiJoin,
                maturity: 1664064000,
                currencyId: 2
            })
        );

        AccessControl giverAccessControl = AccessControl(address(giver));
        giverAccessControl.grantRole(0xe4fd9dc5, timeLock);
        giverAccessControl.grantRole(0x35775afb, address(lever));

        lever.approveFyToken(seriesId);
    }

    /// @notice Create a vault.
    function leverUp(uint128 baseAmount, uint128 borrowAmount)
        public
        returns (bytes12 vaultId)
    {
        // Expect at least 80% of the value to end up as collateral
        // uint256 eulerAmount = pool.sellFYTokenPreview(baseAmount + borrowAmount);

        vaultId = lever.invest(
            ilkId, // ilkId
            seriesId,
            baseAmount,
            borrowAmount
        );
    }
}

contract VaultTest is ZeroState {
    function testVault() public {
        bytes12 vaultId = leverUp(2000e6, 5000e6);
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        assertEq(vault.owner, address(this));
    }
}

contract DivestTest is ZeroState {
    bytes12 vaultId;

    function setUp() public override {
        super.setUp();
        emit log_uint(IERC20(USDC).balanceOf(address(this)));
        vaultId = leverUp(2000e6, 5000e6);
        // DataTypes.Vault memory vault = cauldron.vaults(vaultId);
    }

    function testRepay() public {
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        emit log_uint(IERC20(USDC).balanceOf(address(this)));
        lever.divest(ilkId, seriesId, vaultId, balances.ink, balances.art);
        emit log_uint(IERC20(USDC).balanceOf(address(this)));
    }

    function testDoClose() public {
        DataTypes.Series memory series_ = cauldron.series(seriesId);
        emit log_uint(IERC20(USDC).balanceOf(address(this)));
        vm.warp(series_.maturity);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        lever.divest(ilkId, seriesId, vaultId, balances.ink, balances.art);
        emit log_uint(IERC20(USDC).balanceOf(address(this)));
    }
}
