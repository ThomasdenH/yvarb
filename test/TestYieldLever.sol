pragma solidity ^0.8.0;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "./Interfaces.sol";
import "../contracts/YieldLever.sol";

contract TestMetaCoin {
    uint public initialBalance = 1000 ether;

    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    uint constant usdcAmount = 250000000000;

    /** Test whether we can obtain ETH using Uniswap (V2) */
    function testBuyUsdc() public payable {
        uint startingBalance = USDC.balanceOf(address(this));

        // Swap ETH for USDC on uniswap
        uint deadline = block.timestamp + 100;
        IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        uint inputAmount = uniswapRouter.getAmountsIn(usdcAmount, path)[0];
        Assert.isAtLeast(address(this).balance, inputAmount, "Not enough funds for conversion");

        uniswapRouter.swapETHForExactTokens{value: inputAmount}(
            usdcAmount,
            path,
            address(this),
            deadline
        );

        Assert.equal(USDC.balanceOf(address(this)) - startingBalance, usdcAmount, "Expected trade to succeed");
    }

    /** Test investing */
    address constant yvUSDCJoin = address(0x403ae7384E89b086Ea2935d5fAFed07465242B38);
    yVault constant yvUSDC = yVault(0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE);
    bytes6 constant ilkId = bytes6(0x303900000000); // for yvUSDC
    YieldLadle constant Ladle = YieldLadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    function testDirectInvest() public payable {
        // Buy some USDC to test
        testBuyUsdc();
        testBuyUsdc();
        testBuyUsdc();
        testBuyUsdc();

        YieldLever lever = YieldLever(DeployedAddresses.YieldLever());

        // Deposit USDC.
        /// totalBalance >= baseAmount + borrowAmount
        USDC.approve(address(yvUSDC), 4 * usdcAmount);
        USDC.transfer(address(lever), 4 * usdcAmount);

        bytes6 seriesId = 0x303230360000;
        lever.doInvest(seriesId, uint128(3 * usdcAmount), uint128(3 * usdcAmount), address(this));
    }

    /** Test investing */
    function testInvestAndWithdraw() public payable {
        // Buy some USDC to test
        testBuyUsdc();

        bytes6 seriesId = 0x303230360000;
        YieldLever lever = YieldLever(DeployedAddresses.YieldLever());
        USDC.approve(address(lever), usdcAmount);
        lever.invest(usdcAmount, uint128(4 * usdcAmount), uint128(4 * usdcAmount), seriesId);
    }

    receive() external payable {}
}
