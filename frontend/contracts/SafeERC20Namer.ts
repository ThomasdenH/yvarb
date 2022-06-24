/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import type {
  BaseContract,
  BigNumber,
  BytesLike,
  CallOverrides,
  PopulatedTransaction,
  Signer,
  utils,
} from "ethers";
import type { FunctionFragment, Result } from "@ethersproject/abi";
import type { Listener, Provider } from "@ethersproject/providers";
import type {
  TypedEventFilter,
  TypedEvent,
  TypedListener,
  OnEvent,
  PromiseOrValue,
} from "./common";

export interface SafeERC20NamerInterface extends utils.Interface {
  functions: {
    "tokenDecimals(address)": FunctionFragment;
    "tokenName(address)": FunctionFragment;
    "tokenSymbol(address)": FunctionFragment;
  };

  getFunction(
    nameOrSignatureOrTopic: "tokenDecimals" | "tokenName" | "tokenSymbol"
  ): FunctionFragment;

  encodeFunctionData(
    functionFragment: "tokenDecimals",
    values: [PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "tokenName",
    values: [PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "tokenSymbol",
    values: [PromiseOrValue<string>]
  ): string;

  decodeFunctionResult(
    functionFragment: "tokenDecimals",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "tokenName", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "tokenSymbol",
    data: BytesLike
  ): Result;

  events: {};
}

export interface SafeERC20Namer extends BaseContract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  interface: SafeERC20NamerInterface;

  queryFilter<TEvent extends TypedEvent>(
    event: TypedEventFilter<TEvent>,
    fromBlockOrBlockhash?: string | number | undefined,
    toBlock?: string | number | undefined
  ): Promise<Array<TEvent>>;

  listeners<TEvent extends TypedEvent>(
    eventFilter?: TypedEventFilter<TEvent>
  ): Array<TypedListener<TEvent>>;
  listeners(eventName?: string): Array<Listener>;
  removeAllListeners<TEvent extends TypedEvent>(
    eventFilter: TypedEventFilter<TEvent>
  ): this;
  removeAllListeners(eventName?: string): this;
  off: OnEvent<this>;
  on: OnEvent<this>;
  once: OnEvent<this>;
  removeListener: OnEvent<this>;

  functions: {
    tokenDecimals(
      token: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<[number]>;

    tokenName(
      token: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<[string]>;

    tokenSymbol(
      token: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<[string]>;
  };

  tokenDecimals(
    token: PromiseOrValue<string>,
    overrides?: CallOverrides
  ): Promise<number>;

  tokenName(
    token: PromiseOrValue<string>,
    overrides?: CallOverrides
  ): Promise<string>;

  tokenSymbol(
    token: PromiseOrValue<string>,
    overrides?: CallOverrides
  ): Promise<string>;

  callStatic: {
    tokenDecimals(
      token: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<number>;

    tokenName(
      token: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<string>;

    tokenSymbol(
      token: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<string>;
  };

  filters: {};

  estimateGas: {
    tokenDecimals(
      token: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    tokenName(
      token: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    tokenSymbol(
      token: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;
  };

  populateTransaction: {
    tokenDecimals(
      token: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    tokenName(
      token: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    tokenSymbol(
      token: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;
  };
}