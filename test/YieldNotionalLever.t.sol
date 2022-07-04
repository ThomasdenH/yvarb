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
    address eDaiWhale = 0xb84Cd93582cF94b0625C740F7Ea441e33bc6fd6c;
    address eDai = 0xe025E3ca2bE02316033184551D4d3Aa22024D9DC;
    address usdcWhale = 0x0D2703ac846c26d5B6Bbddf1FD6027204F409785;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    Protocol protocol;
    Giver giver;
    YieldNotionalLever lever;
    ICauldron cauldron;
    FlashJoin daiJoin;
    FlashJoin usdcJoin;
    FlashJoin wethJoin;
    IERC20 constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    bytes6 seriesId = 0x303230370000;

    constructor() {
        protocol = new Protocol();
        cauldron = ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
        daiJoin = FlashJoin(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc); // dai
        wethJoin = FlashJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0); // weth
        usdcJoin = FlashJoin(0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4); // usdc
        giver = new Giver(cauldron);
        // Orchestrate Giver
        AccessControl cauldronAccessControl = AccessControl(
            0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867
        );
        vm.prank(timeLock);
        cauldronAccessControl.grantRole(0x798a828b, address(giver));

        vm.label(
            address(0x07df2ad9878F8797B4055230bbAE5C808b8259b3),
            "eToken Flash Lender"
        );

        vm.label(
            address(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0),
            "weth Join"
        );
        vm.label(
            address(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc),
            "dai Join"
        );
        vm.label(
            address(0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4),
            "usdc Join"
        );
        vm.label(address(0x1344A36A1B56144C3Bc62E7757377D288fDE0369),'Notional');
        vm.label(address(0xA9597DEa21e9D7839Ad0A1A7Dad0842A9C2f4C84),'BatchAction');
        vm.label(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),'USDC');
        vm.label(address(0x39AA39c021dfbaE8faC545936693aC917d5E7563),'cUSDC');

        vm.prank(eDaiWhale);
        IERC20(eDai).transfer(address(this), 1000e18);
        // IERC20(USDC).transfer(address(this), 10000e6);

        vm.prank(timeLock);
        wethJoin.setFlashFeeFactor(1);
        vm.prank(timeLock);
        usdcJoin.setFlashFeeFactor(1);
        vm.prank(timeLock);
        daiJoin.setFlashFeeFactor(1);
    }

    function setUp() public virtual {
        lever = new YieldNotionalLever(
            giver,
            0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4,// USDC Join
            0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc// DAI Join
        );
        vm.prank(usdcWhale);
        IERC20(USDC).transfer(address(lever), 10000e6);
        lever.setIlkToUnderlying(0x313700000000,0x01);
        vm.label(address(lever),"LEVER");
    }

    /// @notice Create a vault.
    function leverUp(uint128 baseAmount, uint128 borrowAmount)
        public
        returns (bytes12 vaultId)
    {
        // Expect at least 80% of the value to end up as collateral
        // uint256 eulerAmount = pool.sellFYTokenPreview(baseAmount + borrowAmount);
        IERC20(eDai).approve(address(lever), 1000e18);
        vaultId = lever.invest(
            baseAmount,
            borrowAmount,
            0, //minCollateral,
            seriesId,
            0x313700000000 // ilkId
        );
    }
}

contract ZeroStateTest is ZeroState {
    function testVault() public {
        bytes12 vaultId = leverUp(200e6, 600e6);
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        assertEq(vault.owner, address(this));
    }
}
