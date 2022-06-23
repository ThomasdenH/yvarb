import { Signer } from "ethers";
import { ICauldron__factory } from "./contracts/factories";
import { ICauldron } from "./contracts/ICauldron";

export const CAULDRON = '0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867';

type DefinitelyContracts = {
  "0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867": ICauldron;
};

type Contracts = {
  [key in keyof DefinitelyContracts]?: DefinitelyContracts[key];
}

type ContractFactories = Readonly<{
  [address in keyof DefinitelyContracts]: {
    connect(address: string, signerOrProvider: Signer): DefinitelyContracts[address];
  };
}>;

const contractFactories: ContractFactories = {
  ["0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867"]: ICauldron__factory,
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
