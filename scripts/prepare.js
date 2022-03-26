const { web3 } = require('@openzeppelin/test-helpers/src/setup');
const erc20Abi = require('../test/ABI/ERC20.json');
const uniwapAbi = require('../test/ABI/UniswapV2Router02.json');
const cauldronAbi = require('../test/ABI/Cauldron.json');
const timelockAbi = require('../test/ABI/TimeLock.json');

const USDC = new web3.eth.Contract(erc20Abi, '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48');
const IUniswapV2Router02 = new web3.eth.Contract(uniwapAbi, '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D');
const Cauldron = new web3.eth.Contract(cauldronAbi, '0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867');
const TimeLock = new web3.eth.Contract(timelockAbi, '0x3b870db67a45611CF4723d44487EAF398fAc51E3');


web3.extend({
    methods: [{
        name: 'setAccountBalance',
        call: 'evm_setAccountBalance',
        params: 2,
        inputFormatter: [web3.extend.formatters.inputAddressFormatter, null]
    }]  
});

module.exports = async function () {
    const YieldLever = artifacts.require("YieldLever");
    
    const accounts = await web3.eth.getAccounts();

    async function buyUsdc(amount) {
        const startingBalance = await USDC.methods.balanceOf(accounts[0]).call();
    
        const blockNumber = await web3.eth.getBlockNumber();
        const deadline = (await web3.eth.getBlock(blockNumber)).timestamp + 10000;
    
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
        console.log('New balance of ' + accounts[0] + ':\t' + newBalance);
    }

    async function grantYieldLeverAccess() {
        await web3.setAccountBalance('0x3b870db67a45611CF4723d44487EAF398fAc51E3', '0x38D7EA4C680000000');

        const sig = web3.eth.abi.encodeFunctionSignature('give(bytes12,address)');
        const yieldLever = await YieldLever.deployed();
        const grantRole = Cauldron.methods.grantRole(sig, yieldLever.address);
        const params = { from: TimeLock.options.address };
        const gas = await grantRole.estimateGas(params);
        await grantRole.send({...params, gas: 2 * gas});
        console.log('Ganted the contract permission to give Vaults.')
    }

    await buyUsdc(25000000000);
    await grantYieldLeverAccess();
};
