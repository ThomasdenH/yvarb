// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/YieldStEthLever.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/vault-v2/FYToken.sol";
import "./Protocol.sol";

// fyeth 0x53358d088d835399F1E97D2a01d79fC925c7D999
contract YieldStEthLeverTest is Test {
    address timeLock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    YieldStEthLever lever;
    FYToken fyToken;
    address fyTokenWhale = 0x1c15b746360BB8E792C6ED8cB83f272Ce1D170E0;
    Protocol protocol;

    function setUp() public {
        protocol = new Protocol();
        lever = new YieldStEthLever(
            IERC3156FlashLender(0x53358d088d835399F1E97D2a01d79fC925c7D999)
        );
        fyToken = FYToken(0x53358d088d835399F1E97D2a01d79fC925c7D999);
        // Set the flash fee factor
        vm.prank(timeLock);
        fyToken.setFlashFeeFactor((5 * 1e18) / 100);

        //Label
        vm.label(address(lever), "YieldLever");
        vm.label(address(fyToken), "FYToken");

        vm.prank(fyTokenWhale);
        fyToken.transfer(address(lever), 1e18);
    }

    function testLoan() public {
        uint256 baseAmount = 1e18;
        uint128 borrowAmount = 20e18;
        uint128 maxFyAmount = 1e18;
        bytes6 seriesId = 0x303030370000;
        lever.invest(baseAmount, borrowAmount, maxFyAmount, seriesId);
    }
}
