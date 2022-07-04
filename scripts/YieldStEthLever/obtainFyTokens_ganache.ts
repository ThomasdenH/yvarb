/** Execute transactions to set the correct configuration for the StEth YieldLever contract. */
import { ethers, Contract, BigNumber, utils } from "ethers";
import { abi as fyTokenAbi } from "../../out/FYToken.sol/FYToken.json";

const gasPrice = "1000000000000";
const tokenWhale = "0x1c15b746360BB8E792C6ED8cB83f272Ce1D170E0";

const destination: string = process.argv[2];
if (!destination) {
  console.log('Please supply the destination address');
  process.exit();
}

(async () => {
  const provider = new ethers.providers.JsonRpcProvider();
  await provider.send("evm_addAccount", [tokenWhale, '']);
  await provider.send("personal_unlockAccount", [tokenWhale, '']);
  // await provider.send("anvil_setCode", [tokenWhale, ""]);
  await provider.send('evm_setAccountBalance', [tokenWhale, utils.parseUnits('1000', 'ether').toHexString()]);
  const signer = provider.getSigner(tokenWhale);

  const fyToken = new Contract(
    "0x53358d088d835399F1E97D2a01d79fC925c7D999",
    fyTokenAbi,
    signer
  );

  const transferToAccount = async () => {
    const tx1 = await fyToken.transfer(destination, BigNumber.from(2).mul(BigNumber.from(10).pow(18)), {gasPrice});
    await tx1;
    console.log("- obtained fyWeth");
  };

  await transferToAccount();
})();
