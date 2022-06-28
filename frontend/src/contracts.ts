import { Signer } from "ethers";
import { Cauldron, Cauldron__factory } from "./contracts/Cauldron.sol";
import {
  FYToken,
  IERC20,
  YieldStEthLever,
  FYToken__factory,
  IERC20__factory,
  YieldStEthLever__factory,
} from "./contracts/YieldStEthLever.sol";

export const CAULDRON = "0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867";
export const YIELD_ST_ETH_LEVER = "0x0cf17d5dcda9cf25889cec9ae5610b0fb9725f65";

type DefinitelyContracts = {
  [CAULDRON]: Cauldron;
  "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2": IERC20;
  "0x53358d088d835399F1E97D2a01d79fC925c7D999": FYToken;
  [YIELD_ST_ETH_LEVER]: YieldStEthLever;
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
