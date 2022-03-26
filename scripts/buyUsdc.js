const { web3 } = require('@openzeppelin/test-helpers/src/setup');
const erc20Abi = require('../test/ABI/ERC20.json');
const uniwapAbi = require('../test/ABI/UniswapV2Router02.json');

const USDC = new web3.eth.Contract(erc20Abi, '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48');
const IUniswapV2Router02 = new web3.eth.Contract(uniwapAbi, '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D');

module.exports = async function () {
    
    const accounts = await web3.eth.getAccounts();

    async function buyUsdc(amount) {
        const startingBalance = await USDC.methods.balanceOf(accounts[0]).call();
    
        const blockNumber = await web3.eth.getBlockNumber();
        const deadline = (await web3.eth.getBlock(blockNumber)).timestamp + 100;
    
        const path = [
            await IUniswapV2Router02.methods.WETH().call(),
            USDC.options.address
        ];
        const inputAmount = (await IUniswapV2Router02.methods.getAmountsIn(amount, path).call())[0];
        
        const ethBalance = await web3.eth.getBalance(accounts[0]);
    
        const swap = IUniswapV2Router02.methods.swapETHForExactTokens(
            amount,
            path,
            accounts[0],
            deadline
        );
        const params = { from: accounts[0], value: 2 * inputAmount };
        const estimatedGas = await swap.estimateGas(params);
        await swap.send({
            ...params,
            gas: 2 * estimatedGas
        });
    
        const newBalance = await USDC.methods.balanceOf(accounts[0]).call();
        console.log(accounts[0] + ':\t' + newBalance);
    }

    await buyUsdc(25000000000);
};
