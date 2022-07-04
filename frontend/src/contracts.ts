import { Signer } from "ethers";
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
} from "./contracts/YieldStEthLever.sol";

export const CAULDRON = "0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867";
export const YIELD_ST_ETH_LEVER = "0x0cf17d5dcda9cf25889cec9ae5610b0fb9725f65";
export const YIELD_LADLE = "0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A";
export const WETH_ST_ETH_STABLESWAP = "0x828b154032950C8ff7CF8085D841723Db2696056";
export const WST_ETH = "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0";

type DefinitelyContracts = {
  [CAULDRON]: Cauldron;
  "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2": IERC20;
  "0x53358d088d835399F1E97D2a01d79fC925c7D999": FYToken;
  [YIELD_ST_ETH_LEVER]: YieldStEthLever;
  [YIELD_LADLE]: YieldLadle;
  [WETH_ST_ETH_STABLESWAP]: IStableSwap;
  [WST_ETH]: WstEth;
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

const contractFactories: ContractFactories = {
  [CAULDRON]: Cauldron__factory,
  ["0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"]: IERC20__factory,
  ["0x53358d088d835399F1E97D2a01d79fC925c7D999"]: FYToken__factory,
  [YIELD_ST_ETH_LEVER]: YieldStEthLever__factory,
  [YIELD_LADLE]: YieldLadle__factory,
  [WETH_ST_ETH_STABLESWAP]: IStableSwap__factory,
  [WST_ETH]: WstEth__factory
};

/** Get a (typed) contract instance. */
export const getContract = <T extends keyof DefinitelyContracts>(
  address: T,
  contracts: Contracts,
  signer: Signer
): DefinitelyContracts[T] => {
  if (contracts[address] === undefined)
    contracts[address] = contractFactories[address].connect(address, signer);
  return contracts[address] as DefinitelyContracts[T];
};

export const getFyToken = async(
  seriesId: string,
  contracts: Contracts,
  signer: Signer
): Promise<FYToken> => {
  const pool = await getPool(seriesId, contracts, signer);
  const fyTokenAddress = await pool.fyToken();
  return FYToken__factory.connect(fyTokenAddress, signer);
}

export const getPool = async (
  seriesId: string,
  contracts: Contracts,
  signer: Signer
): Promise<IPool> => {
  const ladle = getContract(YIELD_LADLE, contracts, signer);
  const pool = await ladle.pools(seriesId);
  return IPool__factory.connect(pool, signer);
};
