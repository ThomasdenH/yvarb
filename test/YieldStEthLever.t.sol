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
import "@yield-protocol/vault-interfaces/src/ICauldron.sol";
// fyeth 0x53358d088d835399F1E97D2a01d79fC925c7D999
contract YieldStEthLeverTest is Test {
    address timeLock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    YieldStEthLever lever;
    FYToken fyToken;
    address fyTokenWhale = 0x1c15b746360BB8E792C6ED8cB83f272Ce1D170E0;
    Protocol protocol;
    Giver giver;

    function setUp() public {
        protocol = new Protocol();
        giver = new Giver(ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867));
        lever = new YieldStEthLever(
            IERC3156FlashLender(0x53358d088d835399F1E97D2a01d79fC925c7D999),
            giver
        );
        fyToken = FYToken(0x53358d088d835399F1E97D2a01d79fC925c7D999);
        // Set the flash fee factor
        vm.prank(timeLock);
        fyToken.setFlashFeeFactor(0);

        //Label
        vm.label(address(lever), "YieldLever");
        vm.label(address(fyToken), "FYToken");

        vm.prank(fyTokenWhale);
        fyToken.transfer(address(this), 1e18);

        // Orchestrate Giver
        AccessControl cauldronAccessControl = AccessControl(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
        vm.prank(timeLock);
        cauldronAccessControl.grantRole(0x798a828b,address(giver));

        AccessControl giverAccessControl = AccessControl(address(giver));
        giverAccessControl.grantRole(0xe4fd9dc5,timeLock);


    }

    function testLoan() public {
        uint256 baseAmount = 0;
        uint128 borrowAmount = 2e18;
        uint128 maxFyAmount = 1e18;
        bytes6 seriesId = 0x303030370000;
        fyToken.approve(address(lever), baseAmount);

        lever.invest(baseAmount, borrowAmount, maxFyAmount, seriesId);
    }
}
