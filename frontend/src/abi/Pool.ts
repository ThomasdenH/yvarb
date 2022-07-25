import {
  ContractTransaction,
  ContractInterface,
  BytesLike as Arrayish,
  BigNumber,
  BigNumberish,
} from "ethers";
import { EthersContractContextV5 } from "ethereum-abi-types-generator";

export type ContractContext = EthersContractContextV5<
  Pool,
  PoolMethodNames,
  PoolEventsContext,
  PoolEvents
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
export type PoolEvents =
  | "Approval"
  | "Liquidity"
  | "Sync"
  | "Trade"
  | "Transfer";
export interface PoolEventsContext {
  Approval(...parameters: any): EventFilter;
  Liquidity(...parameters: any): EventFilter;
  Sync(...parameters: any): EventFilter;
  Trade(...parameters: any): EventFilter;
  Transfer(...parameters: any): EventFilter;
}
export type PoolMethodNames =
  | "new"
  | "DOMAIN_SEPARATOR"
  | "PERMIT_TYPEHASH"
  | "allowance"
  | "approve"
  | "balanceOf"
  | "base"
  | "burn"
  | "burnForBase"
  | "buyBase"
  | "buyBasePreview"
  | "buyFYToken"
  | "buyFYTokenPreview"
  | "cumulativeBalancesRatio"
  | "decimals"
  | "deploymentChainId"
  | "fyToken"
  | "g1"
  | "g2"
  | "getBaseBalance"
  | "getCache"
  | "getFYTokenBalance"
  | "maturity"
  | "mint"
  | "mintWithBase"
  | "name"
  | "nonces"
  | "permit"
  | "retrieveBase"
  | "retrieveFYToken"
  | "scaleFactor"
  | "sellBase"
  | "sellBasePreview"
  | "sellFYToken"
  | "sellFYTokenPreview"
  | "symbol"
  | "sync"
  | "totalSupply"
  | "transfer"
  | "transferFrom"
  | "ts"
  | "version";
export interface ApprovalEventEmittedResponse {
  owner: string;
  spender: string;
  value: BigNumberish;
}
export interface LiquidityEventEmittedResponse {
  maturity: BigNumberish;
  from: string;
  to: string;
  fyTokenTo: string;
  bases: BigNumberish;
  fyTokens: BigNumberish;
  poolTokens: BigNumberish;
}
export interface SyncEventEmittedResponse {
  baseCached: BigNumberish;
  fyTokenCached: BigNumberish;
  cumulativeBalancesRatio: BigNumberish;
}
export interface TradeEventEmittedResponse {
  maturity: BigNumberish;
  from: string;
  to: string;
  bases: BigNumberish;
  fyTokens: BigNumberish;
}
export interface TransferEventEmittedResponse {
  from: string;
  to: string;
  value: BigNumberish;
}
export interface GetCacheResponse {
  result0: BigNumber;
  0: BigNumber;
  result1: BigNumber;
  1: BigNumber;
  result2: number;
  2: number;
  length: 3;
}
export interface Pool {
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: constructor
   */
  "new"(overrides?: ContractTransactionOverrides): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  DOMAIN_SEPARATOR(overrides?: ContractCallOverrides): Promise<string>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  PERMIT_TYPEHASH(overrides?: ContractCallOverrides): Promise<string>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param owner Type: address, Indexed: false
   * @param spender Type: address, Indexed: false
   */
  allowance(
    owner: string,
    spender: string,
    overrides?: ContractCallOverrides
  ): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param spender Type: address, Indexed: false
   * @param wad Type: uint256, Indexed: false
   */
  approve(
    spender: string,
    wad: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param guy Type: address, Indexed: false
   */
  balanceOf(guy: string, overrides?: ContractCallOverrides): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  base(overrides?: ContractCallOverrides): Promise<string>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param baseTo Type: address, Indexed: false
   * @param fyTokenTo Type: address, Indexed: false
   * @param minRatio Type: uint256, Indexed: false
   * @param maxRatio Type: uint256, Indexed: false
   */
  burn(
    baseTo: string,
    fyTokenTo: string,
    minRatio: BigNumberish,
    maxRatio: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param to Type: address, Indexed: false
   * @param minRatio Type: uint256, Indexed: false
   * @param maxRatio Type: uint256, Indexed: false
   */
  burnForBase(
    to: string,
    minRatio: BigNumberish,
    maxRatio: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param to Type: address, Indexed: false
   * @param tokenOut Type: uint128, Indexed: false
   * @param max Type: uint128, Indexed: false
   */
  buyBase(
    to: string,
    tokenOut: BigNumberish,
    max: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param tokenOut Type: uint128, Indexed: false
   */
  buyBasePreview(
    tokenOut: BigNumberish,
    overrides?: ContractCallOverrides
  ): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param to Type: address, Indexed: false
   * @param fyTokenOut Type: uint128, Indexed: false
   * @param max Type: uint128, Indexed: false
   */
  buyFYToken(
    to: string,
    fyTokenOut: BigNumberish,
    max: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param fyTokenOut Type: uint128, Indexed: false
   */
  buyFYTokenPreview(
    fyTokenOut: BigNumberish,
    overrides?: ContractCallOverrides
  ): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  cumulativeBalancesRatio(
    overrides?: ContractCallOverrides
  ): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  decimals(overrides?: ContractCallOverrides): Promise<number>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  deploymentChainId(overrides?: ContractCallOverrides): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  fyToken(overrides?: ContractCallOverrides): Promise<string>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  g1(overrides?: ContractCallOverrides): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  g2(overrides?: ContractCallOverrides): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  getBaseBalance(overrides?: ContractCallOverrides): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  getCache(overrides?: ContractCallOverrides): Promise<GetCacheResponse>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  getFYTokenBalance(overrides?: ContractCallOverrides): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  maturity(overrides?: ContractCallOverrides): Promise<number>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param to Type: address, Indexed: false
   * @param remainder Type: address, Indexed: false
   * @param minRatio Type: uint256, Indexed: false
   * @param maxRatio Type: uint256, Indexed: false
   */
  mint(
    to: string,
    remainder: string,
    minRatio: BigNumberish,
    maxRatio: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param to Type: address, Indexed: false
   * @param remainder Type: address, Indexed: false
   * @param fyTokenToBuy Type: uint256, Indexed: false
   * @param minRatio Type: uint256, Indexed: false
   * @param maxRatio Type: uint256, Indexed: false
   */
  mintWithBase(
    to: string,
    remainder: string,
    fyTokenToBuy: BigNumberish,
    minRatio: BigNumberish,
    maxRatio: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  name(overrides?: ContractCallOverrides): Promise<string>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: address, Indexed: false
   */
  nonces(
    parameter0: string,
    overrides?: ContractCallOverrides
  ): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param owner Type: address, Indexed: false
   * @param spender Type: address, Indexed: false
   * @param amount Type: uint256, Indexed: false
   * @param deadline Type: uint256, Indexed: false
   * @param v Type: uint8, Indexed: false
   * @param r Type: bytes32, Indexed: false
   * @param s Type: bytes32, Indexed: false
   */
  permit(
    owner: string,
    spender: string,
    amount: BigNumberish,
    deadline: BigNumberish,
    v: BigNumberish,
    r: Arrayish,
    s: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param to Type: address, Indexed: false
   */
  retrieveBase(
    to: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param to Type: address, Indexed: false
   */
  retrieveFYToken(
    to: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  scaleFactor(overrides?: ContractCallOverrides): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param to Type: address, Indexed: false
   * @param min Type: uint128, Indexed: false
   */
  sellBase(
    to: string,
    min: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param baseIn Type: uint128, Indexed: false
   */
  sellBasePreview(
    baseIn: BigNumberish,
    overrides?: ContractCallOverrides
  ): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param to Type: address, Indexed: false
   * @param min Type: uint128, Indexed: false
   */
  sellFYToken(
    to: string,
    min: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param fyTokenIn Type: uint128, Indexed: false
   */
  sellFYTokenPreview(
    fyTokenIn: BigNumberish,
    overrides?: ContractCallOverrides
  ): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  symbol(overrides?: ContractCallOverrides): Promise<string>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   */
  sync(overrides?: ContractTransactionOverrides): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  totalSupply(overrides?: ContractCallOverrides): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param dst Type: address, Indexed: false
   * @param wad Type: uint256, Indexed: false
   */
  transfer(
    dst: string,
    wad: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param src Type: address, Indexed: false
   * @param dst Type: address, Indexed: false
   * @param wad Type: uint256, Indexed: false
   */
  transferFrom(
    src: string,
    dst: string,
    wad: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  ts(overrides?: ContractCallOverrides): Promise<BigNumber>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: pure
   * Type: function
   */
  version(overrides?: ContractCallOverrides): Promise<string>;
}
