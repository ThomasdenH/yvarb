const uniwapAbi = require('./ABI/UniswapV2Router02.json');
const erc20Abi = require('./ABI/ERC20.json');
const cauldronAbi = require('./ABI/Cauldron.json');
const ladleAbi = require('./ABI/Ladle.json');
const timelockAbi = require('./ABI/TimeLock.json');
const { web3 } = require('@openzeppelin/test-helpers/src/setup');

const YieldLever = artifacts.require("YieldLever");

web3.extend({
    methods: [{
        name: 'setAccountBalance',
        call: 'evm_setAccountBalance',
        params: 2,
        inputFormatter: [web3.extend.formatters.inputAddressFormatter, null]
    },
    {
        name: 'mine',
        call: 'evm_mine',
        params: 1
    }]
});

contract('YieldLever', async accounts => {
    /** The ilkId for yvUSDC. */
    const ilkId = '0x303900000000';

    const IUniswapV2Router02 = new web3.eth.Contract(uniwapAbi, '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D');
    const Cauldron = new web3.eth.Contract(cauldronAbi, '0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867');
    const Ladle = new web3.eth.Contract(ladleAbi, '0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A');
    const USDC = new web3.eth.Contract(erc20Abi, '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48');
    const TimeLock = new web3.eth.Contract(timelockAbi, '0x3b870db67a45611CF4723d44487EAF398fAc51E3');

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

    async function grantYieldLeverAccess() {
        console.log(web3.currentProvider.sendAsync);
        await web3.setAccountBalance('0x3b870db67a45611CF4723d44487EAF398fAc51E3', '0x38D7EA4C680000000');

        const sig = web3.eth.abi.encodeFunctionSignature('give(bytes12,address)');
        const yieldLever = await YieldLever.deployed();
        const grantRole = Cauldron.methods.grantRole(sig, yieldLever.address);
        const params = { from: TimeLock.options.address };
        const gas = await grantRole.estimateGas(params);
        await grantRole.send({...params, gas: 2 * gas});
    }

    before(grantYieldLeverAccess);

    async function buildVault() {
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
        
        const tx = await yieldLever.invest(USDC100, borrowed, maxFy, seriesId);

        const events = await Cauldron.getPastEvents('VaultGiven', {
            filter: { receiver: accounts[0] },
            fromBlock: tx.blockNumber,
            toBlock: tx.blockNumber
        });
        assert.equal(events.length, 1);
        const event = events[0];

        // Check whether a vault was created correctly
        const vaultId = event.returnValues.vaultId.substring(0,26);
        const vault = await Cauldron.methods.vaults(vaultId).call();
        assert.equal(vault.owner, accounts[0]);
        assert.equal(vault.seriesId, seriesId);
        assert.equal(vault.ilkId, ilkId);
        const balances = await Cauldron.methods.balances(vaultId).call();
        assert.notEqual(balances.ink, 0);
        assert.notEqual(balances.art, 0);
        return vaultId;
    }

    it('should be possible to invest', buildVault);

    it('should be possible to invest and unwind', async () => {
        const vaultId = await buildVault();

        const borrowed = '75000000000';
        const repayAmount = web3.utils.toBN(borrowed).mul(web3.utils.toBN(2));
    
        const yieldLever = await YieldLever.deployed();
        await yieldLever.unwind(vaultId, repayAmount);

        const newBalances = await Cauldron.methods.balances(vaultId).call();
        assert.equal(newBalances.ink, 0);
        assert.equal(newBalances.art, 0);
    });

    
    it('should be possible to invest and close after maturity', async () => {
        const vaultId = await buildVault();
        const seriesId = '0x303230360000';

        // Advance time past series maturity
        const { maturity } = await Cauldron.methods.series(seriesId).call();
        await web3.mine(web3.utils.numberToHex(maturity));
        
        const yieldLever = await YieldLever.deployed();
        await yieldLever.unwind(vaultId, 0);
        
        /*const newBalances = await Cauldron.methods.balances(vaultId).call();
        const ink = newBalances.ink;
        const art = newBalances.art;
        const base = await Cauldron.methods.debtToBase(seriesId, art).call();
        console.log(vaultId, accounts[0], -ink, -base);

        //await buyUsdc(base);

        //const params = { from: accounts[0] };

        /*const allow = USDC.methods.approve('0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4', base);
        const gas = await allow.estimateGas(params);
        await allow.send({...params, gas: gas * 2});*/
        /*
        const close = Ladle.methods.close(vaultId, accounts[0], -ink, -base);
        const gas2 = await close.estimateGas(params);
        await close.send({...params, gas: 2 * gas2});*/
    });
});
