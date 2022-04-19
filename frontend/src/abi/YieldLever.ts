import {
  ContractTransaction,
  ContractInterface,
  BytesLike as Arrayish,
  BigNumber,
  BigNumberish,
} from 'ethers';
import { EthersContractContextV5 } from 'ethereum-abi-types-generator';

export type ContractContext = EthersContractContextV5<
  YieldLever,
  YieldLeverMethodNames,
  YieldLeverEventsContext,
  YieldLeverEvents
>;

export declare type EventFilter = {
  address?: string;
  topics?: Array<string>;
  fromBlock?: string | number;
  toBlock?: string | number;
};

export interface ContractTransactionOverrides {
  /**
   * The maximum units of gas for the transaction to use
   */
  gasLimit?: number;
  /**
   * The price (in wei) per unit of gas
   */
  gasPrice?: BigNumber | string | number | Promise<any>;
  /**
   * The nonce to use in the transaction
   */
  nonce?: number;
  /**
   * The amount to send with the transaction (i.e. msg.value)
   */
  value?: BigNumber | string | number | Promise<any>;
  /**
   * The chain ID (or network ID) to use
   */
  chainId?: number;
}

export interface ContractCallOverrides {
  /**
   * The address to execute the call as
   */
  from?: string;
  /**
   * The maximum units of gas for the transaction to use
   */
  gasLimit?: number;
}
export type YieldLeverEvents = undefined;
export interface YieldLeverEventsContext {}
export type YieldLeverMethodNames =
  | 'invest'
  | 'doInvest'
  | 'unwind'
  | 'doRepay'
  | 'doClose';
export interface YieldLever {
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param baseAmount Type: uint256, Indexed: false
   * @param borrowAmount Type: uint128, Indexed: false
   * @param maxFyAmount Type: uint128, Indexed: false
   * @param seriesId Type: bytes6, Indexed: false
   */
  invest(
    baseAmount: BigNumberish,
    borrowAmount: BigNumberish,
    maxFyAmount: BigNumberish,
    seriesId: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param investAmount Type: uint256, Indexed: false
   * @param borrowAmount Type: uint128, Indexed: false
   * @param maxFyAmount Type: uint128, Indexed: false
   * @param vaultId Type: bytes12, Indexed: false
   */
  doInvest(
    investAmount: BigNumberish,
    borrowAmount: BigNumberish,
    maxFyAmount: BigNumberish,
    vaultId: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param vaultId Type: bytes12, Indexed: false
   * @param maxAmount Type: uint256, Indexed: false
   * @param pool Type: address, Indexed: false
   * @param ink Type: uint128, Indexed: false
   * @param art Type: uint128, Indexed: false
   * @param seriesId Type: bytes6, Indexed: false
   */
  unwind(
    vaultId: Arrayish,
    maxAmount: BigNumberish,
    pool: string,
    ink: BigNumberish,
    art: BigNumberish,
    seriesId: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param owner Type: address, Indexed: false
   * @param vaultId Type: bytes12, Indexed: false
   * @param borrowAmount Type: uint256, Indexed: false
   * @param ink Type: uint128, Indexed: false
   */
  doRepay(
    owner: string,
    vaultId: Arrayish,
    borrowAmount: BigNumberish,
    ink: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param owner Type: address, Indexed: false
   * @param vaultId Type: bytes12, Indexed: false
   * @param base Type: uint128, Indexed: false
   * @param ink Type: uint128, Indexed: false
   * @param art Type: uint128, Indexed: false
   */
  doClose(
    owner: string,
    vaultId: Arrayish,
    base: BigNumberish,
    ink: BigNumberish,
    art: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
}
