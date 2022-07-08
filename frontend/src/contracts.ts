import { Signer } from "ethers";
import { MutableRefObject } from "react";
import { Cauldron, Cauldron__factory } from "./contracts/Cauldron.sol";
import {
  FYToken,
  IERC20,
  YieldStEthLever,
  FYToken__factory,
  IERC20__factory,
  YieldStEthLever__factory,
  YieldLadle,
  YieldLadle__factory,
  IPool,
  IPool__factory,
  IStableSwap,
  IStableSwap__factory,
  WstEth,
  WstEth__factory,
  FlashJoin,
  FlashJoin__factory,
} from "./contracts/YieldStEthLever.sol";

export const CAULDRON = "0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867";
export const YIELD_ST_ETH_LEVER = "0x0cf17d5dcda9cf25889cec9ae5610b0fb9725f65";
export const YIELD_LADLE = "0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A";
export const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
export const WETH_ST_ETH_STABLESWAP = "0x828b154032950C8ff7CF8085D841723Db2696056";
export const WST_ETH = "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0";
export const FY_WETH = "0x53358d088d835399F1E97D2a01d79fC925c7D999";
export const WETH_JOIN = "0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0";

type DefinitelyContracts = {
  [CAULDRON]: Cauldron;
  [WETH]: IERC20;
  [FY_WETH]: FYToken;
  [YIELD_ST_ETH_LEVER]: YieldStEthLever;
  [YIELD_LADLE]: YieldLadle;
  [WETH_ST_ETH_STABLESWAP]: IStableSwap;
  [WST_ETH]: WstEth;
  [WETH_JOIN]: FlashJoin;
};

export type Contracts = {
  [key in keyof DefinitelyContracts]?: DefinitelyContracts[key];
};

type ContractFactories = Readonly<{
  [address in keyof DefinitelyContracts]: {
    connect(
      address: string,
      signerOrProvider: Signer
    ): DefinitelyContracts[address];
  };
}>;

export type ContractAddress = keyof DefinitelyContracts;
export type FyTokenAddress = typeof FY_WETH; 

const contractFactories: ContractFactories = {
  [CAULDRON]: Cauldron__factory,
  [WETH]: IERC20__factory,
  [FY_WETH]: FYToken__factory,
  [YIELD_ST_ETH_LEVER]: YieldStEthLever__factory,
  [YIELD_LADLE]: YieldLadle__factory,
  [WETH_ST_ETH_STABLESWAP]: IStableSwap__factory,
  [WST_ETH]: WstEth__factory,
  [WETH_JOIN]: FlashJoin__factory
};

/** Get a (typed) contract instance. */
export const getContract = <T extends keyof DefinitelyContracts>(
  address: T,
  contracts: MutableRefObject<Contracts>,
  signer: Signer
): DefinitelyContracts[T] => {
  if (contracts.current[address] === undefined)
    contracts.current[address] = contractFactories[address].connect(address, signer);
  return contracts.current[address] as DefinitelyContracts[T];
};

export const getFyToken = async(
  seriesId: string,
  contracts: MutableRefObject<Contracts>,
  signer: Signer
): Promise<FYToken> => {
  const pool = await getPool(seriesId, contracts, signer);
  const fyTokenAddress = await pool.fyToken();
  return FYToken__factory.connect(fyTokenAddress, signer);
}

export const getPool = async (
  seriesId: string,
  contracts: MutableRefObject<Contracts>,
  signer: Signer
): Promise<IPool> => {
  const ladle = getContract(YIELD_LADLE, contracts, signer);
  const pool = await ladle.pools(seriesId);
  return IPool__factory.connect(pool, signer);
};
