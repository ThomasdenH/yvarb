import ganache from 'ganache';
import { BigNumber, ethers, Contract } from 'ethers';

import erc20Abi from './ERC20.json';
import uniswapAbi from './UniswapV2Router02.json';
import cauldronAbi from './Cauldron.json';
import timelockAbi from './TimeLock.json';

const provider = new ethers.providers.JsonRpcProvider();
const signer = provider.getSigner('0x098687D4e5bD35c79D02d3b4EcC32120232C8ae3');

const USDC = new Contract('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', erc20Abi, signer);
const IUniswapV2Router02 = new Contract('0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', uniswapAbi, signer);
const Cauldron = new Contract('0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867', cauldronAbi, signer);
const TimeLock = new Contract('0x3b870db67a45611CF4723d44487EAF398fAc51E3', timelockAbi, signer);

async function buyUsdc(amount: BigNumber) {
    const blockNumber = await provider.getBlockNumber();
    const deadline = (await provider.getBlock(blockNumber)).timestamp + 10000;

    const path = [
        await IUniswapV2Router02.WETH(),
        USDC.address
    ];
    const inputAmount = (await IUniswapV2Router02.getAmountsIn(amount, path))[0];
    
    const account = await signer.getAddress();

    const ethBalance = await provider.getBalance(account);

    await IUniswapV2Router02.swapETHForExactTokens(
        amount,
        path,
        account,
        deadline,
        {
            value: inputAmount.mul(2)
        }
    );

    const newBalance = await USDC.balanceOf(account);
    console.log('New balance of ' + account + ':\t' + newBalance);
}

buyUsdc(BigNumber.from(25_000_000_000));
