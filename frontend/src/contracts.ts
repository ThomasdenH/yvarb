import { Signer } from "ethers";
import {
  FYToken__factory,
  ICauldron__factory,
  IERC20__factory,
} from "./contracts/factories";
import { FYToken } from "./contracts/FYToken";
import { ICauldron } from "./contracts/ICauldron";
import { IERC20 } from "./contracts/IERC20";

export const CAULDRON = "0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867";

type DefinitelyContracts = {
  "0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867": ICauldron;
  "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2": IERC20;
  "0x53358d088d835399F1E97D2a01d79fC925c7D999": FYToken;
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
  ["0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867"]: ICauldron__factory,
  ["0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"]: IERC20__factory,
  ["0x53358d088d835399F1E97D2a01d79fC925c7D999"]: FYToken__factory,
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
