import { BigNumber, Signer } from "ethers";
import { MutableRefObject } from "react";
import { Contracts, FY_WETH, getContract, getFyTokenAddress } from "./contracts";

export type IERC20Address =
  | "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  | typeof FY_WETH;

/**
 * Balances! FyTokens are indexed with their seriesId, others by their address.
 */
export type Balances = {
  [address: string]: BigNumber | undefined;
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

export const loadFyTokenBalance = async(
  seriesId: string,
  contracts: MutableRefObject<Contracts>,
  signer: Signer
): Promise<BigNumber> => {
  const address = await getFyTokenAddress(seriesId, contracts, signer);
  return await loadBalance(address as IERC20Address, contracts, signer);
};
