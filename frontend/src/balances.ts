import { BigNumber, Signer } from "ethers";
import { MutableRefObject } from "react";
import { Contracts, getContract, getFyTokenAddress } from "./contracts";
import { FYToken__factory } from "./contracts/YieldStEthLever.sol";

export type IERC20Address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

export type SeriesId = string & { readonly __tag: unique symbol };

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
  seriesId: SeriesId,
  contracts: MutableRefObject<Contracts>,
  signer: Signer
): Promise<BigNumber> => {
  const address = await getFyTokenAddress(seriesId, contracts, signer);
  const fyToken = FYToken__factory.connect(address, signer);
  return await fyToken.balanceOf(await signer.getAddress());
};
