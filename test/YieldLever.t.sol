// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/YieldLever.sol";

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
}

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
    IUniswapV2Router02 constant uniswap = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IERC20 constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    AccessControl constant cauldron = AccessControl(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);

    constructor() {
        vm.label(address(usdc), "USDC");
        vm.label(address(uniswap), "IUniswapV2Router02");
        vm.label(address(cauldron), "Cauldron");
    }

    function buyUsdc(uint amountOut, address receiver) external {
        uint startingBalance = usdc.balanceOf(receiver);

        address[] memory path = new address[](2);
        path[0] = uniswap.WETH();
        path[1] = address(usdc);

        uint inputAmount = 2 * uniswap.getAmountsIn(amountOut, path)[0];
        deal(address(this), inputAmount);

        console.log("before buy");

        uniswap.swapETHForExactTokens{value: inputAmount}(amountOut, path, receiver, block.timestamp);
    
        uint endBalance = usdc.balanceOf(receiver);
        require(endBalance == amountOut + startingBalance, "USDC buy failed: Incorrect end balance");
    }

    function grantYieldLeverAccess(address yieldLeverAddress) external {
        bytes4 sig = bytes4(abi.encodeWithSignature("give(bytes12,address)"));

        // Call as the Yield Admin contract
        vm.prank(0x3b870db67a45611CF4723d44487EAF398fAc51E3);
        cauldron.grantRole(sig, yieldLeverAddress);
    }

    receive() payable external {}

    function testBuyUsdc() external {
        uint amount = 100_000_000;
        this.buyUsdc(amount, address(this));
    }
}

contract YieldLeverTest is Test {
    YieldLever yieldLever;
    HelperContract helperContract;

    IERC20 constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    Cauldron constant cauldron = Cauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    YieldLadle constant ladle = YieldLadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    Pool pool;

    bytes6 constant yvUsdcIlkId = 0x303900000000;
    bytes6 constant seriesId = 0x303230360000;
    bytes6 constant ILK_ID = 0x303900000000;

    constructor() {
        pool = Pool(ladle.pools(seriesId));
        vm.label(address(ladle), "YieldLadle");
        vm.label(address(pool), "Pool");
        vm.label(address(cauldron), "Cauldron");
        vm.label(0x856Ddd1A74B6e620d043EfD6F74d81b8bf34868D, "YieldMath");
    }

    function setUp() public {
        yieldLever = new YieldLever();
        helperContract = new HelperContract();
        helperContract.grantYieldLeverAccess(address(yieldLever));
    }

    /// Test the creation of a Vault.
    function testBuildVault() public {
        uint128 collateral = 25_000_000_000;
        uint128 borrowed = 3 * collateral;
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
        uint128 collateral = 25_000_000_000;
        uint128 borrowed = 3 * collateral;
        uint128 slippage = 1_001;
        this.investAndUnwind(collateral, borrowed, slippage);
    }

    function testInvestAndUnwind2() public {
        uint128 collateral = 5_000_000_000;
        uint128 borrowed = 2 * collateral;
        uint128 slippage = 1_020;
        this.investAndUnwind(collateral, borrowed, slippage);
    }

    function testInvestAndUnwindAfterMaturity() public {
        uint128 collateral = 25_000_000_000;
        uint128 borrowed = 3 * collateral;
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
