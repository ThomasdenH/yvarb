import {
  ContractTransaction,
  ContractInterface,
  BytesLike as Arrayish,
  BigNumber,
  BigNumberish,
} from "ethers";
import { EthersContractContextV5 } from "ethereum-abi-types-generator";

export type ContractContext = EthersContractContextV5<
  Cauldron,
  CauldronMethodNames,
  CauldronEventsContext,
  CauldronEvents
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
export type CauldronEvents =
  | "AssetAdded"
  | "DebtLimitsSet"
  | "IlkAdded"
  | "RateOracleAdded"
  | "RoleAdminChanged"
  | "RoleGranted"
  | "RoleRevoked"
  | "SeriesAdded"
  | "SeriesMatured"
  | "SpotOracleAdded"
  | "VaultBuilt"
  | "VaultDestroyed"
  | "VaultGiven"
  | "VaultPoured"
  | "VaultRolled"
  | "VaultStirred"
  | "VaultTweaked";
export interface CauldronEventsContext {
  AssetAdded(...parameters: any): EventFilter;
  DebtLimitsSet(...parameters: any): EventFilter;
  IlkAdded(...parameters: any): EventFilter;
  RateOracleAdded(...parameters: any): EventFilter;
  RoleAdminChanged(...parameters: any): EventFilter;
  RoleGranted(...parameters: any): EventFilter;
  RoleRevoked(...parameters: any): EventFilter;
  SeriesAdded(...parameters: any): EventFilter;
  SeriesMatured(...parameters: any): EventFilter;
  SpotOracleAdded(...parameters: any): EventFilter;
  VaultBuilt(...parameters: any): EventFilter;
  VaultDestroyed(...parameters: any): EventFilter;
  VaultGiven(...parameters: any): EventFilter;
  VaultPoured(...parameters: any): EventFilter;
  VaultRolled(...parameters: any): EventFilter;
  VaultStirred(...parameters: any): EventFilter;
  VaultTweaked(...parameters: any): EventFilter;
}
export type CauldronMethodNames =
  | "LOCK"
  | "LOCK8605463013"
  | "ROOT"
  | "ROOT4146650865"
  | "accrual"
  | "addAsset"
  | "addIlks"
  | "addSeries"
  | "assets"
  | "balances"
  | "build"
  | "debt"
  | "debtFromBase"
  | "debtToBase"
  | "destroy"
  | "getRoleAdmin"
  | "give"
  | "grantRole"
  | "grantRoles"
  | "hasRole"
  | "ilks"
  | "lendingOracles"
  | "level"
  | "lockRole"
  | "mature"
  | "pour"
  | "ratesAtMaturity"
  | "renounceRole"
  | "revokeRole"
  | "revokeRoles"
  | "roll"
  | "series"
  | "setDebtLimits"
  | "setLendingOracle"
  | "setRoleAdmin"
  | "setSpotOracle"
  | "slurp"
  | "spotOracles"
  | "stir"
  | "tweak"
  | "vaults";
export interface AssetAddedEventEmittedResponse {
  assetId: Arrayish;
  asset: string;
}
export interface DebtLimitsSetEventEmittedResponse {
  baseId: Arrayish;
  ilkId: Arrayish;
  max: BigNumberish;
  min: BigNumberish;
  dec: BigNumberish;
}
export interface IlkAddedEventEmittedResponse {
  seriesId: Arrayish;
  ilkId: Arrayish;
}
export interface RateOracleAddedEventEmittedResponse {
  baseId: Arrayish;
  oracle: string;
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
export interface SeriesAddedEventEmittedResponse {
  seriesId: Arrayish;
  baseId: Arrayish;
  fyToken: string;
}
export interface SeriesMaturedEventEmittedResponse {
  seriesId: Arrayish;
  rateAtMaturity: BigNumberish;
}
export interface SpotOracleAddedEventEmittedResponse {
  baseId: Arrayish;
  ilkId: Arrayish;
  oracle: string;
  ratio: BigNumberish;
}
export interface VaultBuiltEventEmittedResponse {
  vaultId: Arrayish;
  owner: string;
  seriesId: Arrayish;
  ilkId: Arrayish;
}
export interface VaultDestroyedEventEmittedResponse {
  vaultId: Arrayish;
}
export interface VaultGivenEventEmittedResponse {
  vaultId: Arrayish;
  receiver: string;
}
export interface VaultPouredEventEmittedResponse {
  vaultId: Arrayish;
  seriesId: Arrayish;
  ilkId: Arrayish;
  ink: BigNumberish;
  art: BigNumberish;
}
export interface VaultRolledEventEmittedResponse {
  vaultId: Arrayish;
  seriesId: Arrayish;
  art: BigNumberish;
}
export interface VaultStirredEventEmittedResponse {
  from: Arrayish;
  to: Arrayish;
  ink: BigNumberish;
  art: BigNumberish;
}
export interface VaultTweakedEventEmittedResponse {
  vaultId: Arrayish;
  seriesId: Arrayish;
  ilkId: Arrayish;
}
export interface BalancesResponse {
  art: BigNumber;
  0: BigNumber;
  ink: BigNumber;
  1: BigNumber;
  length: 2;
}
export interface VaultResponse {
  owner: string;
  0: string;
  seriesId: string;
  1: string;
  ilkId: string;
  2: string;
}
export interface DebtResponse {
  max: BigNumber;
  0: BigNumber;
  min: number;
  1: number;
  dec: number;
  2: number;
  sum: BigNumber;
  3: BigNumber;
  length: 4;
}
export interface SeriesResponse {
  fyToken: string;
  0: string;
  baseId: string;
  1: string;
  maturity: number;
  2: number;
  length: 3;
}
export interface SpotOraclesResponse {
  oracle: string;
  0: string;
  ratio: number;
  1: number;
  length: 2;
}
export interface VaultsResponse {
  owner: string;
  0: string;
  seriesId: string;
  1: string;
  ilkId: string;
  2: string;
  length: 3;
}
export interface Cauldron {
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
   * @param seriesId Type: bytes6, Indexed: false
   */
  accrual(
    seriesId: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param assetId Type: bytes6, Indexed: false
   * @param asset Type: address, Indexed: false
   */
  addAsset(
    assetId: Arrayish,
    asset: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param seriesId Type: bytes6, Indexed: false
   * @param ilkIds Type: bytes6[], Indexed: false
   */
  addIlks(
    seriesId: Arrayish,
    ilkIds: Arrayish[],
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param seriesId Type: bytes6, Indexed: false
   * @param baseId Type: bytes6, Indexed: false
   * @param fyToken Type: address, Indexed: false
   */
  addSeries(
    seriesId: Arrayish,
    baseId: Arrayish,
    fyToken: string,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: bytes6, Indexed: false
   */
  assets(
    parameter0: Arrayish,
    overrides?: ContractCallOverrides
  ): Promise<string>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: bytes12, Indexed: false
   */
  balances(
    parameter0: Arrayish,
    overrides?: ContractCallOverrides
  ): Promise<BalancesResponse>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param owner Type: address, Indexed: false
   * @param vaultId Type: bytes12, Indexed: false
   * @param seriesId Type: bytes6, Indexed: false
   * @param ilkId Type: bytes6, Indexed: false
   */
  build(
    owner: string,
    vaultId: Arrayish,
    seriesId: Arrayish,
    ilkId: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: bytes6, Indexed: false
   * @param parameter1 Type: bytes6, Indexed: false
   */
  debt(
    parameter0: Arrayish,
    parameter1: Arrayish,
    overrides?: ContractCallOverrides
  ): Promise<DebtResponse>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param seriesId Type: bytes6, Indexed: false
   * @param base Type: uint128, Indexed: false
   */
  debtFromBase(
    seriesId: Arrayish,
    base: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param seriesId Type: bytes6, Indexed: false
   * @param art Type: uint128, Indexed: false
   */
  debtToBase(
    seriesId: Arrayish,
    art: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param vaultId Type: bytes12, Indexed: false
   */
  destroy(
    vaultId: Arrayish,
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
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param vaultId Type: bytes12, Indexed: false
   * @param receiver Type: address, Indexed: false
   */
  give(
    vaultId: Arrayish,
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
   * @param parameter0 Type: bytes6, Indexed: false
   * @param parameter1 Type: bytes6, Indexed: false
   */
  ilks(
    parameter0: Arrayish,
    parameter1: Arrayish,
    overrides?: ContractCallOverrides
  ): Promise<boolean>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: bytes6, Indexed: false
   */
  lendingOracles(
    parameter0: Arrayish,
    overrides?: ContractCallOverrides
  ): Promise<string>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param vaultId Type: bytes12, Indexed: false
   */
  level(
    vaultId: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
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
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param seriesId Type: bytes6, Indexed: false
   */
  mature(
    seriesId: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param vaultId Type: bytes12, Indexed: false
   * @param ink Type: int128, Indexed: false
   * @param art Type: int128, Indexed: false
   */
  pour(
    vaultId: Arrayish,
    ink: BigNumberish,
    art: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: bytes6, Indexed: false
   */
  ratesAtMaturity(
    parameter0: Arrayish,
    overrides?: ContractCallOverrides
  ): Promise<BigNumber>;
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
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param vaultId Type: bytes12, Indexed: false
   * @param newSeriesId Type: bytes6, Indexed: false
   * @param art Type: int128, Indexed: false
   */
  roll(
    vaultId: Arrayish,
    newSeriesId: Arrayish,
    art: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: bytes6, Indexed: false
   */
  series(
    parameter0: Arrayish,
    overrides?: ContractCallOverrides
  ): Promise<SeriesResponse>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param baseId Type: bytes6, Indexed: false
   * @param ilkId Type: bytes6, Indexed: false
   * @param max Type: uint96, Indexed: false
   * @param min Type: uint24, Indexed: false
   * @param dec Type: uint8, Indexed: false
   */
  setDebtLimits(
    baseId: Arrayish,
    ilkId: Arrayish,
    max: BigNumberish,
    min: BigNumberish,
    dec: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param baseId Type: bytes6, Indexed: false
   * @param oracle Type: address, Indexed: false
   */
  setLendingOracle(
    baseId: Arrayish,
    oracle: string,
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
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param baseId Type: bytes6, Indexed: false
   * @param ilkId Type: bytes6, Indexed: false
   * @param oracle Type: address, Indexed: false
   * @param ratio Type: uint32, Indexed: false
   */
  setSpotOracle(
    baseId: Arrayish,
    ilkId: Arrayish,
    oracle: string,
    ratio: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param vaultId Type: bytes12, Indexed: false
   * @param ink Type: uint128, Indexed: false
   * @param art Type: uint128, Indexed: false
   */
  slurp(
    vaultId: Arrayish,
    ink: BigNumberish,
    art: BigNumberish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: bytes6, Indexed: false
   * @param parameter1 Type: bytes6, Indexed: false
   */
  spotOracles(
    parameter0: Arrayish,
    parameter1: Arrayish,
    overrides?: ContractCallOverrides
  ): Promise<SpotOraclesResponse>;
  /**
   * Payable: false
   * Constant: false
   * StateMutability: nonpayable
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
   * Constant: false
   * StateMutability: nonpayable
   * Type: function
   * @param vaultId Type: bytes12, Indexed: false
   * @param seriesId Type: bytes6, Indexed: false
   * @param ilkId Type: bytes6, Indexed: false
   */
  tweak(
    vaultId: Arrayish,
    seriesId: Arrayish,
    ilkId: Arrayish,
    overrides?: ContractTransactionOverrides
  ): Promise<ContractTransaction>;
  /**
   * Payable: false
   * Constant: true
   * StateMutability: view
   * Type: function
   * @param parameter0 Type: bytes12, Indexed: false
   */
  vaults(
    parameter0: Arrayish,
    overrides?: ContractCallOverrides
  ): Promise<VaultsResponse>;
}
