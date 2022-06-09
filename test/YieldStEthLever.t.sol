// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/YieldStEthLever.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/vault-v2/FYToken.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "./Protocol.sol";
import "@yield-protocol/vault-v2/utils/Giver.sol";
import "@yield-protocol/vault-v2/FlashJoin.sol";
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";

contract YieldStEthLeverTest is Test {
    address timeLock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    address fyTokenWhale = 0x1c15b746360BB8E792C6ED8cB83f272Ce1D170E0;
    YieldStEthLever lever;
    FYToken fyToken;
    Protocol protocol;
    Giver giver;

    IPool pool = IPool(0xc3348D8449d13C364479B1F114bcf5B73DFc0dc6);
    FlashJoin flashJoin;
    bytes6 seriesId = 0x303030370000;
    ICauldron cauldron;

    constructor() {
        protocol = new Protocol();
        fyToken = FYToken(0x53358d088d835399F1E97D2a01d79fC925c7D999);
        flashJoin = FlashJoin(0x5364d336c2d2391717bD366b29B6F351842D7F82); //wsteth
        cauldron = ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
        // Set the flash fee factor
        vm.prank(timeLock);
        fyToken.setFlashFeeFactor(1);

        vm.prank(timeLock);
        flashJoin.setFlashFeeFactor(1);
        vm.label(address(fyToken), "FYToken");
        vm.label(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0, "WETH JOIN");
        giver = new Giver(cauldron);
        // Orchestrate Giver
        AccessControl cauldronAccessControl = AccessControl(
            0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867
        );
        vm.prank(timeLock);
        cauldronAccessControl.grantRole(0x798a828b, address(giver));
    }

    function setUp() public {
        lever = new YieldStEthLever(
            IERC3156FlashLender(0x53358d088d835399F1E97D2a01d79fC925c7D999),
            giver
        );

        //Label
        vm.label(address(lever), "YieldLever");

        vm.prank(fyTokenWhale);
        fyToken.transfer(address(this), 2e18);
        // vm.prank(fyTokenWhale);
        // fyToken.transfer(address(lever), 3e18);
        AccessControl giverAccessControl = AccessControl(address(giver));
        giverAccessControl.grantRole(0xe4fd9dc5, timeLock);
        giverAccessControl.grantRole(0x35775afb, address(lever));
    }

    function leverUp(uint256 baseAmount, uint128 borrowAmount)
        public
        returns (bytes12 vaultId)
    {
        fyToken.approve(address(lever), baseAmount);
        vaultId = lever.invest(baseAmount, borrowAmount, seriesId);
    }

    function unwind(bytes12 vaultId) public returns (bytes12) {
        DataTypes.Balances memory balances = ICauldron(
            0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867
        ).balances(vaultId);
        lever.unwind(
            vaultId,
            balances.art,
            balances.ink,
            balances.art,
            seriesId
        );
        return vaultId;
    }

    function testVault() public {
        bytes12 vaultId = leverUp(2e18, 6e18);
        DataTypes.Vault memory vault = ICauldron(
            0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867
        ).vaults(vaultId);
        assertEq(vault.owner, address(this));
    }

    function testLever() public {
        bytes12 vaultId = leverUp(2e18, 5e18);
        DataTypes.Balances memory balances = ICauldron(
            0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867
        ).balances(vaultId);
        assertEq(balances.art, 5e18);
    }

    function testLoanAndRepay() public {
        bytes12 vaultId = leverUp(2e18, 4e18);
        unwind(vaultId);

        DataTypes.Balances memory balances = ICauldron(
            0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867
        ).balances(vaultId);
        assertEq(balances.art, 0);
        assertEq(balances.ink, 0);
    }

    function testLoanAndClose() public {
        bytes12 vaultId = leverUp(2e18, 4e18);

        DataTypes.Series memory series_ = ICauldron(
            0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867
        ).series(seriesId);

        vm.warp(series_.maturity);

        unwind(vaultId);

        DataTypes.Balances memory balances = ICauldron(
            0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867
        ).balances(vaultId);
        assertEq(balances.art, 0);
        assertEq(balances.ink, 0);
    }
}
