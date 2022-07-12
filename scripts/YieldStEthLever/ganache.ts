/** Combines all Ganache scripts into one. */
import {
  BigNumber,
  Contract,
  ContractFactory,
  ethers,
  providers,
  utils,
} from "ethers";
import { YieldStEthLever } from "../../frontend/src/contracts/YieldStEthLever.sol";
import giverContractJson from "../../out/Giver.sol/Giver.json";
import yieldStLeverJson from "../../out/YieldStEthLever.sol/YieldStEthLever.json";
import { abi as fyTokenAbi } from "../../out/FYToken.sol/FYToken.json";
import { abi as flashJoinAbi } from "../../out/FlashJoin.sol/FlashJoin.json";
import { abi as accessControlAbi } from "../../out/AccessControl.sol/AccessControl.json";

const gasPrice = BigNumber.from("1000000000000");
const seriesId = "0x303030370000";

const OWN_ADDRESS: string = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const DEPLOY_SENDER: string = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";

export const runSetup = async (provider: providers.JsonRpcProvider) => {
  const deploySigner = provider.getSigner(DEPLOY_SENDER);
  const cauldron = "0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867";
  const giverFactory = new ContractFactory(
    giverContractJson.abi,
    giverContractJson.bytecode,
    deploySigner
  );
  /*const giverContract = await giverFactory.deploy(cauldron, { gasPrice });
  await giverContract.deployTransaction.wait();
  console.log("- deployed Giver contract");
  console.log(`\t${giverContract.address}`);

  const yieldStLever = new ContractFactory(
    yieldStLeverJson.abi,
    yieldStLeverJson.bytecode,
    deploySigner
  );
  const yieldStEthLeverContract = await yieldStLever.deploy(
    giverContract.address,
    {
      gasPrice,
    }
  );
  await yieldStEthLeverContract.deployTransaction.wait();
  console.log("- deployed YieldStEthLever contract");
  console.log(`\t${yieldStEthLeverContract.address}`);

  const approveSeries = await (
    yieldStEthLeverContract as YieldStEthLever
  ).approveFyToken(seriesId);
  await approveSeries.wait();
  console.log(`- Approved series\n\t${seriesId}`);

  const timeLock = "0x3b870db67a45611CF4723d44487EAF398fAc51E3";
  const timeLockSigner = provider.getSigner(timeLock);
  await provider.send("evm_setAccountBalance", [
    timeLock,
    utils.parseUnits("1000", "ether").toHexString(),
  ]);

  const fyToken = new Contract(
    "0x53358d088d835399F1E97D2a01d79fC925c7D999",
    fyTokenAbi,
    timeLockSigner
  );
  const flashJoin = new Contract(
    "0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0",
    flashJoinAbi,
    timeLockSigner
  );
  const cauldronAccessControl = new Contract(
    "0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867",
    accessControlAbi,
    timeLockSigner
  );
  {
    const tx1 = await fyToken.setFlashFeeFactor(1, {
      gasPrice,
    });
    await tx1;
    const tx2 = await flashJoin.setFlashFeeFactor(1, {
      gasPrice,
    });
    await tx2;
    console.log("- configured flash loans");
  }
  {
    const tx = await cauldronAccessControl.grantRole(
      "0x798a828b",
      giverContract.address,
      { gasPrice }
    );
    await tx;
    const deployer = provider.getSigner(
      "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
    );
    const giverAccessControl = new Contract(
      giverContract.address,
      accessControlAbi,
      deployer
    );
    const tx3 = await giverAccessControl.grantRole("0xe4fd9dc5", timeLock, {
      gasPrice,
    });
    await tx3;
    const tx4 = await giverAccessControl.grantRole(
      "0x35775afb",
      yieldStEthLeverContract.address,
      { gasPrice }
    );
    await tx4;
    console.log("- granted giver-related roles");
  }

  {
    const tokenWhale = "0x1c15b746360BB8E792C6ED8cB83f272Ce1D170E0";
    await provider.send("evm_addAccount", [tokenWhale, ""]);
    await provider.send("personal_unlockAccount", [tokenWhale, ""]);
    // await provider.send("anvil_setCode", [tokenWhale, ""]);
    await provider.send("evm_setAccountBalance", [
      tokenWhale,
      utils.parseUnits("1000", "ether").toHexString(),
    ]);
    const tokenWhaleSigner = provider.getSigner(tokenWhale);

    const fyTokenTokenWhale = new Contract(
      "0x53358d088d835399F1E97D2a01d79fC925c7D999",
      fyTokenAbi,
      tokenWhaleSigner
    );

    const tx1 = await fyTokenTokenWhale.transfer(
      OWN_ADDRESS,
      BigNumber.from(2).mul(BigNumber.from(10).pow(18)),
      { gasPrice }
    );
    await tx1;
    console.log("- obtained fyWeth");
  }*/
}

{
  const provider = new ethers.providers.JsonRpcProvider();
  runSetup(provider);
}
