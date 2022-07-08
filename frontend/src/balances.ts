import { BigNumber, Signer } from "ethers";
import { MutableRefObject } from "react";
import { Contracts, FY_WETH, getContract } from "./contracts";

export type IERC20Address =
  | "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  | typeof FY_WETH;

export type Balances = {
  [address in keyof Contracts]: BigNumber | undefined;
};

/** Load a balance for a token, return a new balance object. */
export const loadBalance = async (
  tokenAddress: IERC20Address,
  contracts: MutableRefObject<Contracts>,
  signer: Signer
): Promise<BigNumber> => {
  const contract = getContract(tokenAddress, contracts, signer);
  const balance = await contract.balanceOf(await signer.getAddress());
  return balance;
};
