import { BigNumber, ContractFactory, ethers, Wallet } from "ethers";
import giverContractJson from "../../out/Giver.sol/Giver.json";
import yieldStLeverJson from "../../out/YieldStEthLever.sol/YieldStEthLever.json";

const gasPrice = BigNumber.from("1000000000000");

const sender: string = process.argv[2];
if (!sender) {
  console.log("Please supply the sender address");
  process.exit();
}

const rpcUrl: string = process.argv[3];
if (!rpcUrl) {
  console.log("Please supply the rpc url");
  process.exit();
}

const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
const signer = provider.getSigner(sender);

(async () => {
  const cauldron = "0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867";
  const giverFactory = new ContractFactory(
    giverContractJson.abi,
    giverContractJson.bytecode,
    signer
  );
  const giverContract = await giverFactory.deploy(cauldron, { gasPrice });
  await giverContract.deployTransaction.wait();
  console.log("- deployed Giver contract");
  console.log(`\t${giverContract.address}`);

  const yieldStLever = new ContractFactory(
    yieldStLeverJson.abi,
    yieldStLeverJson.bytecode,
    signer
  );
  const contract2 = await yieldStLever.deploy(giverContract.address, {
    gasPrice,
  });
  await contract2.deployTransaction.wait();
  console.log("- deployed YieldStEthLever contract");
  console.log(`\t${contract2.address}`);
})();
