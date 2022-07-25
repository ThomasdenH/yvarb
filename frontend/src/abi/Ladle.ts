import {
  ContractTransaction,
  ContractInterface,
  BytesLike as Arrayish,
  BigNumber,
  BigNumberish,
} from "ethers";
import { EthersContractContextV5 } from "ethereum-abi-types-generator";

export type ContractContext = EthersContractContextV5<
  Ladle,
  LadleMethodNames,
  LadleEventsContext,
  LadleEvents
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
export type LadleEvents =
  | "FeeSet"
  | "IntegrationAdded"
  | "JoinAdded"
  | "ModuleAdded"
  | "PoolAdded"
  | "RoleAdminChanged"
  | "RoleGranted"
  | "RoleRevoked"
  | "TokenAdded";
export interface LadleEventsContext {
  FeeSet(...parameters: any): EventFilter;
  IntegrationAdded(...parameters: any): EventFilter;
  JoinAdded(...parameters: any): EventFilter;
  ModuleAdded(...parameters: any): EventFilter;
  PoolAdded(...parameters: any): EventFilter;
  RoleAdminChanged(...parameters: any): EventFilter;
  RoleGranted(...parameters: any): EventFilter;
  RoleRevoked(...parameters: any): EventFilter;
  TokenAdded(...parameters: any): EventFilter;
}
export type LadleMethodNames =
  | "new"
  | "LOCK"
  | "LOCK8605463013"
  | "ROOT"
  | "ROOT4146650865"
  | "addIntegration"
  | "addJoin"
  | "addModule"
  | "addPool"
  | "addToken"
  | "batch"
  | "borrowingFee"
  | "build"
  | "cauldron"
  | "close"
  | "closeFromLadle"
  | "destroy"
  | "exitEther"
  | "forwardDaiPermit"
  | "forwardPermit"
  | "getRoleAdmin"
  | "give"
  | "grantRole"
  | "grantRoles"
  | "hasRole"
  | "integrations"
  | "joinEther"
  | "joins"
  | "lockRole"
  | "moduleCall"
  | "modules"
  | "pools"
  | "pour"
  | "redeem"
  | "renounceRole"
  | "repay"
  | "repayFromLadle"
  | "repayVault"
  | "retrieve"
  | "revokeRole"
  | "revokeRoles"
  | "roll"
  | "route"
  | "router"
  | "serve"
  | "setFee"
  | "setRoleAdmin"
  | "stir"
  | "tokens"
  | "transfer"
  | "tweak"
  | "weth";
export interface FeeSetEventEmittedResponse {
  fee: BigNumberish;
}
export interface IntegrationAddedEventEmittedResponse {
  integration: string;
  set: boolean;
}
export interface JoinAddedEventEmittedResponse {
  assetId: Arrayish;
  join: string;
}
export interface ModuleAddedEventEmittedResponse {
  module: string;
  set: boolean;
}
export interface PoolAddedEventEmittedResponse {
  seriesId: Arrayish;
  pool: string;
}
export interface RoleAdminChangedEventEmittedResponse {
  role: Arrayish;
  newAdminRole: Arrayish;
}
export interface RoleGrantedEventEmittedResponse {
  role: Arrayish;
  account: string;
  sender: string;
}
export interface RoleRevokedEventEmittedResponse {
  role: Arrayish;
  account: string;
  sender: string;
}
export interface TokenAddedEventEmittedResponse {
  token: string;
  set: boolean;
}
export interface VaultResponse {
  owner: string;
  0: string;
  seriesId: string;
  1: string;
  ilkId: string;
  2: string;
}
export interface Ladle {
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: constructor
   * @param cauldron Type: address, Indexed: false
   * @param weth Type: address, Indexed: false
   */
  "new"(
    cauldron: string,
    weth: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  LOCK(overrides?: ContractCallOverrides): Promise<string>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  LOCK8605463013(overrides?: ContractCallOverrides): Promise<string>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  ROOT(overrides?: ContractCallOverrides): Promise<string>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  ROOT4146650865(overrides?: ContractCallOverrides): Promise<string>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param integration Type: address, Indexed: false
   * @param set Type: bool, Indexed: false
   */
  addIntegration(
    integration: string,
    set: boolean,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param assetId Type: bytes6, Indexed: false
   * @param join Type: address, Indexed: false
   */
  addJoin(
    assetId: Arrayish,
    join: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param module Type: address, Indexed: false
   * @param set Type: bool, Indexed: false
   */
  addModule(
    module: string,
    set: boolean,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param seriesId Type: bytes6, Indexed: false
   * @param pool Type: address, Indexed: false
   */
  addPool(
    seriesId: Arrayish,
    pool: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param token Type: address, Indexed: false
   * @param set Type: bool, Indexed: false
   */
  addToken(
    token: string,
    set: boolean,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param calls Type: bytes[], Indexed: false
   */
  batch(
    calls: Arrayish[],
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  borrowingFee(overrides?: ContractCallOverrides): Promise<BigNumber>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param seriesId Type: bytes6, Indexed: false
   * @param ilkId Type: bytes6, Indexed: false
   * @param salt Type: uint8, Indexed: false
   */
  build(
    seriesId: Arrayish,
    ilkId: Arrayish,
    salt: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  cauldron(overrides?: ContractCallOverrides): Promise<string>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param vaultId_ Type: bytes12, Indexed: false
   * @param to Type: address, Indexed: false
   * @param ink Type: int128, Indexed: false
   * @param art Type: int128, Indexed: false
   */
  close(
    vaultId_: Arrayish,
    to: string,
    ink: BigNumberish,
    art: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param vaultId_ Type: bytes12, Indexed: false
   * @param to Type: address, Indexed: false
   */
  closeFromLadle(
    vaultId_: Arrayish,
    to: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param vaultId_ Type: bytes12, Indexed: false
   */
  destroy(
    vaultId_: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param to Type: address, Indexed: false
   */
  exitEther(
    to: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param token Type: address, Indexed: false
   * @param spender Type: address, Indexed: false
   * @param nonce Type: uint256, Indexed: false
   * @param deadline Type: uint256, Indexed: false
   * @param allowed Type: bool, Indexed: false
   * @param v Type: uint8, Indexed: false
   * @param r Type: bytes32, Indexed: false
   * @param s Type: bytes32, Indexed: false
   */
  forwardDaiPermit(
    token: string,
    spender: string,
    nonce: BigNumberish,
    deadline: BigNumberish,
    allowed: boolean,
    v: BigNumberish,
    r: Arrayish,
    s: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param token Type: address, Indexed: false
   * @param spender Type: address, Indexed: false
   * @param amount Type: uint256, Indexed: false
   * @param deadline Type: uint256, Indexed: false
   * @param v Type: uint8, Indexed: false
   * @param r Type: bytes32, Indexed: false
   * @param s Type: bytes32, Indexed: false
   */
  forwardPermit(
    token: string,
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
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param role Type: bytes4, Indexed: false
   */
  getRoleAdmin(
    role: Arrayish,
    overrides?: ContractCallOverrides
  ): Promise<string>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param vaultId_ Type: bytes12, Indexed: false
   * @param receiver Type: address, Indexed: false
   */
  give(
    vaultId_: Arrayish,
    receiver: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param role Type: bytes4, Indexed: false
   * @param account Type: address, Indexed: false
   */
  grantRole(
    role: Arrayish,
    account: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param roles Type: bytes4[], Indexed: false
   * @param account Type: address, Indexed: false
   */
  grantRoles(
    roles: Arrayish[],
    account: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param role Type: bytes4, Indexed: false
   * @param account Type: address, Indexed: false
   */
  hasRole(
    role: Arrayish,
    account: string,
    overrides?: ContractCallOverrides
  ): Promise<boolean>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: address, Indexed: false
   */
  integrations(
    parameter0: string,
    overrides?: ContractCallOverrides
  ): Promise<boolean>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param etherId Type: bytes6, Indexed: false
   */
  joinEther(
    etherId: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: bytes6, Indexed: false
   */
  joins(
    parameter0: Arrayish,
    overrides?: ContractCallOverrides
  ): Promise<string>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param role Type: bytes4, Indexed: false
   */
  lockRole(
    role: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param module Type: address, Indexed: false
   * @param data Type: bytes, Indexed: false
   */
  moduleCall(
    module: string,
    data: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: address, Indexed: false
   */
  modules(
    parameter0: string,
    overrides?: ContractCallOverrides
  ): Promise<boolean>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: bytes6, Indexed: false
   */
  pools(
    parameter0: Arrayish,
    overrides?: ContractCallOverrides
  ): Promise<string>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param vaultId_ Type: bytes12, Indexed: false
   * @param to Type: address, Indexed: false
   * @param ink Type: int128, Indexed: false
   * @param art Type: int128, Indexed: false
   */
  pour(
    vaultId_: Arrayish,
    to: string,
    ink: BigNumberish,
    art: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param seriesId Type: bytes6, Indexed: false
   * @param to Type: address, Indexed: false
   * @param wad Type: uint256, Indexed: false
   */
  redeem(
    seriesId: Arrayish,
    to: string,
    wad: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param role Type: bytes4, Indexed: false
   * @param account Type: address, Indexed: false
   */
  renounceRole(
    role: Arrayish,
    account: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param vaultId_ Type: bytes12, Indexed: false
   * @param to Type: address, Indexed: false
   * @param ink Type: int128, Indexed: false
   * @param min Type: uint128, Indexed: false
   */
  repay(
    vaultId_: Arrayish,
    to: string,
    ink: BigNumberish,
    min: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param vaultId_ Type: bytes12, Indexed: false
   * @param to Type: address, Indexed: false
   */
  repayFromLadle(
    vaultId_: Arrayish,
    to: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param vaultId_ Type: bytes12, Indexed: false
   * @param to Type: address, Indexed: false
   * @param ink Type: int128, Indexed: false
   * @param max Type: uint128, Indexed: false
   */
  repayVault(
    vaultId_: Arrayish,
    to: string,
    ink: BigNumberish,
    max: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param token Type: address, Indexed: false
   * @param to Type: address, Indexed: false
   */
  retrieve(
    token: string,
    to: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param role Type: bytes4, Indexed: false
   * @param account Type: address, Indexed: false
   */
  revokeRole(
    role: Arrayish,
    account: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param roles Type: bytes4[], Indexed: false
   * @param account Type: address, Indexed: false
   */
  revokeRoles(
    roles: Arrayish[],
    account: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param vaultId_ Type: bytes12, Indexed: false
   * @param newSeriesId Type: bytes6, Indexed: false
   * @param loan Type: uint8, Indexed: false
   * @param max Type: uint128, Indexed: false
   */
  roll(
    vaultId_: Arrayish,
    newSeriesId: Arrayish,
    loan: BigNumberish,
    max: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param integration Type: address, Indexed: false
   * @param data Type: bytes, Indexed: false
   */
  route(
    integration: string,
    data: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  router(overrides?: ContractCallOverrides): Promise<string>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param vaultId_ Type: bytes12, Indexed: false
   * @param to Type: address, Indexed: false
   * @param ink Type: uint128, Indexed: false
   * @param base Type: uint128, Indexed: false
   * @param max Type: uint128, Indexed: false
   */
  serve(
    vaultId_: Arrayish,
    to: string,
    ink: BigNumberish,
    base: BigNumberish,
    max: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param fee Type: uint256, Indexed: false
   */
  setFee(
    fee: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param role Type: bytes4, Indexed: false
   * @param adminRole Type: bytes4, Indexed: false
   */
  setRoleAdmin(
    role: Arrayish,
    adminRole: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param from Type: bytes12, Indexed: false
   * @param to Type: bytes12, Indexed: false
   * @param ink Type: uint128, Indexed: false
   * @param art Type: uint128, Indexed: false
   */
  stir(
    from: Arrayish,
    to: Arrayish,
    ink: BigNumberish,
    art: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: address, Indexed: false
   */
  tokens(
    parameter0: string,
    overrides?: ContractCallOverrides
  ): Promise<boolean>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param token Type: address, Indexed: false
   * @param receiver Type: address, Indexed: false
   * @param wad Type: uint128, Indexed: false
   */
  transfer(
    token: string,
    receiver: string,
    wad: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: true
   * Constant: false
   * StateMutability: payable
   * Type: function
   * @param vaultId_ Type: bytes12, Indexed: false
   * @param seriesId Type: bytes6, Indexed: false
   * @param ilkId Type: bytes6, Indexed: false
   */
  tweak(
    vaultId_: Arrayish,
    seriesId: Arrayish,
    ilkId: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   */
  weth(overrides?: ContractCallOverrides): Promise<string>;
}
