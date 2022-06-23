/** Execute transactions to set the correct configuration for the StEth YieldLever contract. */
import { ethers, Contract } from "ethers";
import { abi as fyTokenAbi } from "../../out/FYToken.sol/FYToken.json";
import { abi as flashJoinAbi } from "../../out/FlashJoin.sol/FlashJoin.json";

const gasPrice = "100000000000";

(async () => {
  const provider = new ethers.providers.JsonRpcProvider();
  const timeLock = "0x3b870db67a45611CF4723d44487EAF398fAc51E3";
  await provider.send("anvil_impersonateAccount", [timeLock]);
  await provider.send("anvil_setCode", [timeLock, ""]);
  await provider.send("anvil_setBalance", [timeLock, "1000000000000000000"]);
  const signer = provider.getSigner(timeLock);

  const fyToken = new Contract(
    "0x53358d088d835399F1E97D2a01d79fC925c7D999",
    fyTokenAbi,
    signer
  );
  const flashJoin = new Contract(
    "0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0",
    flashJoinAbi,
    signer
  );

  const allowFlashLoans = async () => {
    const tx1 = await fyToken.setFlashFeeFactor(1, {
      gasPrice,
    });
    await tx1;
    const tx2 = await flashJoin.setFlashFeeFactor(1, {
      gasPrice,
    });
    await tx2;
  };

  await allowFlashLoans();
})();
