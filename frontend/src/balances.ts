import { BigNumber, Signer } from "ethers";
import { MutableRefObject } from "react";
import { Contracts, getContract } from "./contracts";

export const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
export const FY_WETH = '0x53358d088d835399F1E97D2a01d79fC925c7D999';

export type IERC20Address =
  | "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  | "0x53358d088d835399F1E97D2a01d79fC925c7D999";

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
