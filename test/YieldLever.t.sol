// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "src/YieldLever.sol";

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

interface CheatCodes {
    function prank(address) external;
    // Sets an address' balance
    function deal(address who, uint256 newBalance) external;
    // Label an address in test traces
    function label(address addr, string calldata label) external;
    // Prepare an expected log with (bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData).
    // Call this function, then emit an event, then call a function. Internally after the call, we check if
    // logs were emitted in the expected order with the expected topics and data (as specified by the booleans)
    function expectEmit(bool, bool, bool, bool) external;
    // Set block.timestamp
    function warp(uint256) external;
    // When fuzzing, generate new inputs if conditional not met
    function assume(bool) external;
}

interface Pool {
    function buyBasePreview(uint128 tokenOut)
        external view
        returns(uint128);
    function buyFYTokenPreview(uint128 fyTokenOut)
        external view
        returns(uint128);
}

contract HelperContract is DSTest {
    CheatCodes constant cheats = CheatCodes(HEVM_ADDRESS);
    IUniswapV2Router02 constant uniswap = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IERC20 constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    AccessControl constant cauldron = AccessControl(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);

    constructor() {
        cheats.label(address(usdc), "USDC");
        cheats.label(address(uniswap), "IUniswapV2Router02");
        cheats.label(address(cauldron), "Cauldron");
    }

    function buyUsdc(uint amountOut, address receiver) external {
        uint startingBalance = usdc.balanceOf(receiver);

        address[] memory path = new address[](2);
        path[0] = uniswap.WETH();
        path[1] = address(usdc);

        uint inputAmount = 2 * uniswap.getAmountsIn(amountOut, path)[0];
        cheats.deal(address(this), inputAmount);

        uniswap.swapETHForExactTokens{value: inputAmount}(amountOut, path, receiver, block.timestamp);
    
        uint endBalance = usdc.balanceOf(receiver);
        require(endBalance == amountOut + startingBalance, "USDC buy failed: Incorrect end balance");
    }

    function grantYieldLeverAccess(address yieldLeverAddress) external {
        bytes4 sig = bytes4(abi.encodeWithSignature("give(bytes12,address)"));

        // Call as the Yield Admin contract
        cheats.prank(0x3b870db67a45611CF4723d44487EAF398fAc51E3);
        cauldron.grantRole(sig, yieldLeverAddress);
    }

    receive() payable external {}

    function testBuyUsdc() external {
        uint amount = 100_000_000;
        this.buyUsdc(amount, address(this));
    }
}

contract YieldLeverTest is DSTest {
    YieldLever yieldLever;
    HelperContract helperContract;

    IERC20 constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    Cauldron constant cauldron = Cauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    YieldLadle constant ladle = YieldLadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    CheatCodes constant cheats = CheatCodes(HEVM_ADDRESS);
    Pool pool;

    bytes6 constant yvUsdcIlkId = 0x303900000000;
    bytes6 constant seriesId = 0x303230360000;
    bytes6 constant ILK_ID = 0x303900000000;

    constructor() {
        pool = Pool(ladle.pools(seriesId));
        cheats.label(address(ladle), "YieldLadle");
        cheats.label(address(pool), "Pool");
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

    function testInvest(uint128 collateral, uint128 borrowed) public {
        cheats.assume(collateral >= 1_000_000);
        cheats.assume(collateral <= 100_000_000_000_000);
        cheats.assume(borrowed >= 1_000_000);
        cheats.assume(borrowed <= 100_000_000_000_000);

        // Slippage, in tenths of a percent, 1 being no slippage
        uint128 slippage = 1_001;

        helperContract.buyUsdc(collateral, address(this));
        usdc.approve(address(yieldLever), collateral);

        // Compute min debt
        Series memory series = cauldron.series(seriesId);
        uint128 maxFy = (pool.buyBasePreview(borrowed) * slippage) / 1000;
        Debt memory debt = cauldron.debt(series.baseId, ILK_ID);
        uint minDebt = debt.min * (10 ** debt.dec);
        uint maxDebt = debt.max * (10 ** debt.dec);
        cheats.assume(maxFy >= minDebt);
        cheats.assume(maxFy <= maxDebt);

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

    function testInvestAndUnwind() public {
        uint128 collateral = 25_000_000_000;
        uint128 borrowed = 3 * collateral;
        // Slippage, in tenths of a percent, 1 being no slippage
        uint128 slippage = 1_001;
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
        cheats.warp(series.maturity);

        // Unwind
        Balances memory balances = cauldron.balances(vaultId);
        yieldLever.unwind(vaultId, 0, address(pool), balances.ink, balances.art, seriesId);

        // Test new balances
        Balances memory newBalances = cauldron.balances(vaultId);
        assertEq(newBalances.art, 0);
        assertEq(newBalances.ink, 0);
    }
}
