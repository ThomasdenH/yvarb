const uniwapAbi = require('./ABI/UniswapV2Router02.json');
const erc20Abi = require('./ABI/ERC20.json');
const cauldronAbi = require('./ABI/Cauldron.json');
const ladleAbi = require('./ABI/Ladle.json');

const YieldLever = artifacts.require("YieldLever");

contract('YieldLever', async accounts => {
    /** The ilkId for yvUSDC. */
    const ilkId = '0x303900000000';

    const IUniswapV2Router02 = new web3.eth.Contract(uniwapAbi, '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D');
    const Cauldron = new web3.eth.Contract(cauldronAbi, '0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867');
    const Ladle = new web3.eth.Contract(ladleAbi, '0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A');

    const USDC = new web3.eth.Contract(erc20Abi, '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48');

    /** Buy some USDC */
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
        assert.isOk(ethBalance >= inputAmount, 'not enough Ether to buy USDC');

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
        assert.equal(newBalance - startingBalance, amount);
    }

    it('should be possible to obtain 100 USDC', async () => {
        await buyUsdc('100' + '000000');
    });

    it('should be possible to invest in the contract', async () => {
        const USDC100 = '25000000000';
        const borrowed = '75000000000';
        const maxFy = '90000000000';
        const seriesId = '0x303230360000';

        await buyUsdc(USDC100);

        const yieldLever = await YieldLever.deployed();

        const approval = USDC.methods.approve(yieldLever.address, USDC100);
        const params = { from: accounts[0] };
        const approvalGas = await approval.estimateGas(params);
        await USDC.methods.approve(yieldLever.address, USDC100).send({
            ...params, gas: 2 * approvalGas
        });
        
        await yieldLever.invest(USDC100, borrowed, maxFy, seriesId);

        // Check whether a vault was created correctly
        const vaultId = await yieldLever.addressToVaultId(accounts[0]);
        const vault = await Cauldron.methods.vaults(vaultId).call();
        assert.equal(vault.owner, yieldLever.address);
        assert.equal(vault.seriesId, seriesId);
        assert.equal(vault.ilkId, ilkId);
        const balances = await Cauldron.methods.balances(vaultId).call();
        assert.notEqual(balances.ink, 0);
        assert.notEqual(balances.art, 0);
    });

    it('should be possible to invest and unwind', async () => {
        const USDC100 = '25000000000';
        const borrowed = '75000000000';
        const maxFy = '90000000000';
        const seriesId = '0x303230360000';

        await buyUsdc(USDC100);

        const yieldLever = await YieldLever.deployed();

        const approval = USDC.methods.approve(yieldLever.address, USDC100);
        const params = { from: accounts[0] };
        const approvalGas = await approval.estimateGas(params);
        await USDC.methods.approve(yieldLever.address, USDC100).send({
            ...params, gas: 2 * approvalGas
        });
        
        await yieldLever.invest(USDC100, borrowed, maxFy, seriesId);

        const toBorrow = borrowed;
        await yieldLever.unwind(toBorrow, 0);
    });
});
