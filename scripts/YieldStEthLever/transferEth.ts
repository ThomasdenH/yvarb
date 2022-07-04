import { BigNumber, ethers, UnsignedTransaction } from "ethers";

const gasPrice = BigNumber.from("1000000000000");
const ethOwner = '0x1aD91ee08f21bE3dE0BA2ba6918E714dA6B45836';

const rpcUrl: string = process.argv[2];
if (!rpcUrl) {
  console.log("Please supply the rpcUrl");
  process.exit();
}

const receiverAddress: string = process.argv[3];
if (!receiverAddress) {
  console.log("Please supply the receiverAddress");
  process.exit();
}

const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
const signer = provider.getSigner(ethOwner);

(async () => {
    const tx = {
        to: receiverAddress,
        value: ethers.utils.parseUnits('1', 'ether'),
        gasPrice
    };
    const tx1 = await signer.sendTransaction(tx);
    await tx1.wait();
    console.log('- obtained eth');
})();
