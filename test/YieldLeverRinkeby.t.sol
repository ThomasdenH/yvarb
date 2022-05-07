// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/YieldLeverRinkeby.sol";

interface AccessControl {
    function grantRole(bytes4 role, address account) external;
}

interface Pool {
    function buyBasePreview(uint128 tokenOut)
        external view
        returns(uint128);
    function buyFYTokenPreview(uint128 fyTokenOut)
        external view
        returns(uint128);
    function getBaseBalance()
        external view
        returns(uint112);
}

contract HelperContract is Test {
    RinkebyToken constant usdc = RinkebyToken(0xf4aDD9708888e654C042613843f413A8d6aDB8Fe);
    AccessControl constant cauldron = AccessControl(0x84EFA55faA9d774B4846c7a51c1C470232DFE50f);

    constructor() {
        vm.label(address(usdc), "USDC");
        vm.label(address(cauldron), "Cauldron");
    }

    function buyUsdc(uint amountOut, address receiver) external {
        usdc.mint(receiver, amountOut);
    }

    function grantYieldLeverAccess(address yieldLeverAddress) external {
        bytes4 sig = bytes4(abi.encodeWithSignature("give(bytes12,address)"));

        // Call as the Yield Admin contract
        vm.prank(0x1BE7654F12BFC3ea2C53d05E512033d5a634c2b5);
        cauldron.grantRole(sig, yieldLeverAddress);
    }

    receive() payable external {}

    function testBuyUsdc() external {
        uint amount = 5_000_000;
        this.buyUsdc(amount, address(this));
    }
}

contract YieldLeverTest is Test {
    YieldLever yieldLever;
    HelperContract helperContract;

    RinkebyToken constant usdc = RinkebyToken(0xf4aDD9708888e654C042613843f413A8d6aDB8Fe);
    Cauldron constant cauldron = Cauldron(0x84EFA55faA9d774B4846c7a51c1C470232DFE50f);
    YieldLadle constant ladle = YieldLadle(0xAE53c79926cb960feA17aF2369DE10938f5D0d52);
    YVault constant yVault = YVault(0x2381d065e83DDdBaCD9B4955d49D5a858AE5957B);
    Pool pool;

    bytes6 constant usdcId = 0x303200000000;
    bytes6 constant yvUsdcIlkId = 0x303900000000;
    bytes6 constant seriesId = 0x303230370000;

    constructor() {
        pool = Pool(ladle.pools(seriesId));
    }

    function setUp() public {
        yieldLever = new YieldLever(
            yvUsdcIlkId,
            yVault,
            usdc,
            ladle.joins(usdcId),
            ladle,
            ladle.joins(yvUsdcIlkId),
            cauldron
        );
        helperContract = new HelperContract();
        helperContract.grantYieldLeverAccess(address(yieldLever));
    }

    /// Test the creation of a Vault.
    function testBuildVault() public {
        uint128 collateral = 5_000_000_000;
        uint128 borrowed = 1_000_000_000;
        // Slippage, in tenths of a percent, 1 being no slippage
        uint128 slippage = 1_001;

        helperContract.buyUsdc(collateral, address(this));
        usdc.approve(address(yieldLever), collateral);

        uint128 maxFy = (pool.buyBasePreview(borrowed) * slippage) / 1000;

        bytes12 vaultId = yieldLever.invest(collateral, borrowed, maxFy, seriesId);

        // Test some parameters
        Vault memory vault = cauldron.vaults(vaultId);
        assertEq(vault.owner, address(this));
        assertEq(vault.seriesId, seriesId);
        assertEq(vault.ilkId, yvUsdcIlkId);

        Balances memory balances = cauldron.balances(vaultId);
        assertGt(balances.ink, 0);
        assertGt(balances.art, 0);
    }

    function investAndUnwind(uint128 collateral, uint128 borrowed, uint128 slippage) public {
        helperContract.buyUsdc(collateral, address(this));
        usdc.approve(address(yieldLever), collateral);
        uint128 maxFy = (pool.buyBasePreview(borrowed) * slippage) / 1000;
        bytes12 vaultId = yieldLever.invest(collateral, borrowed, maxFy, seriesId);

        // Unwind
        Balances memory balances = cauldron.balances(vaultId);
        uint128 maxAmount = (pool.buyFYTokenPreview(balances.art) * slippage) / 1000;
        yieldLever.unwind(vaultId, maxAmount, address(pool), balances.ink, balances.art, seriesId);

        // Test new balances
        Balances memory newBalances = cauldron.balances(vaultId);
        assertEq(newBalances.art, 0);
        assertEq(newBalances.ink, 0);
    }

    function testInvestAndUnwind() public {
        uint128 collateral = 5_000_000_000;
        uint128 borrowed = 2 * collateral;
        uint128 slippage = 1_001;
        this.investAndUnwind(collateral, borrowed, slippage);
    }

    function testInvestAndUnwind2() public {
        uint128 collateral = 10_000_000_000;
        uint128 borrowed = collateral;
        uint128 slippage = 1_020;
        this.investAndUnwind(collateral, borrowed, slippage);
    }

    function testInvestAndUnwindAfterMaturity() public {
        uint128 collateral = 5_000_000_000;
        uint128 borrowed = 2 * collateral;
        // Slippage, in tenths of a percent, 1 being no slippage
        uint128 slippage = 1_001;
        helperContract.buyUsdc(collateral, address(this));
        usdc.approve(address(yieldLever), collateral);
        uint128 maxFy = (pool.buyBasePreview(borrowed) * slippage) / 1000;
        bytes12 vaultId = yieldLever.invest(collateral, borrowed, maxFy, seriesId);

        // Move past maturity
        Series memory series = cauldron.series(seriesId);
        vm.warp(series.maturity);

        // Unwind
        Balances memory balances = cauldron.balances(vaultId);
        yieldLever.unwind(vaultId, 0, address(pool), balances.ink, balances.art, seriesId);

        // Test new balances
        Balances memory newBalances = cauldron.balances(vaultId);
        assertEq(newBalances.art, 0);
        assertEq(newBalances.ink, 0);
    }
}
