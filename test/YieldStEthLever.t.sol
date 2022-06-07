// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/YieldStEthLever.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "vault-v2/FYToken.sol";

// fyeth 0x53358d088d835399F1E97D2a01d79fC925c7D999
contract YieldStEthLever is Test {
    address timeLock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    YieldStEthLever lever;
    IFYToken fyToken;

    function setUp() public {
        lever = new YieldStEthLever(
            IERC3156FlashLender(0x53358d088d835399F1E97D2a01d79fC925c7D999)
        );
        fyToken = IFYToken(0x53358d088d835399F1E97D2a01d79fC925c7D999);
        // Set the flash fee factor
        vm.prank(timeLock);
        fyToken.setFlashFeeFactor((5 * 1e18) / 100);
    }
}
