/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import type {
  BaseContract,
  BigNumber,
  BigNumberish,
  BytesLike,
  CallOverrides,
  ContractTransaction,
  Overrides,
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

export interface IStableSwapInterface extends utils.Interface {
  functions: {
    "exchange(int128,int128,uint256,uint256,address)": FunctionFragment;
    "get_dy(int128,int128,uint256)": FunctionFragment;
  };

  getFunction(nameOrSignatureOrTopic: "exchange" | "get_dy"): FunctionFragment;

  encodeFunctionData(
    functionFragment: "exchange",
    values: [
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<string>
    ]
  ): string;
  encodeFunctionData(
    functionFragment: "get_dy",
    values: [
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<BigNumberish>
    ]
  ): string;

  decodeFunctionResult(functionFragment: "exchange", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "get_dy", data: BytesLike): Result;

  events: {};
}

export interface IStableSwap extends BaseContract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  interface: IStableSwapInterface;

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
    exchange(
      i: PromiseOrValue<BigNumberish>,
      j: PromiseOrValue<BigNumberish>,
      dx: PromiseOrValue<BigNumberish>,
      min_dy: PromiseOrValue<BigNumberish>,
      receiver: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    get_dy(
      i: PromiseOrValue<BigNumberish>,
      j: PromiseOrValue<BigNumberish>,
      _dx: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<[BigNumber]>;
  };

  exchange(
    i: PromiseOrValue<BigNumberish>,
    j: PromiseOrValue<BigNumberish>,
    dx: PromiseOrValue<BigNumberish>,
    min_dy: PromiseOrValue<BigNumberish>,
    receiver: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  get_dy(
    i: PromiseOrValue<BigNumberish>,
    j: PromiseOrValue<BigNumberish>,
    _dx: PromiseOrValue<BigNumberish>,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  callStatic: {
    exchange(
      i: PromiseOrValue<BigNumberish>,
      j: PromiseOrValue<BigNumberish>,
      dx: PromiseOrValue<BigNumberish>,
      min_dy: PromiseOrValue<BigNumberish>,
      receiver: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    get_dy(
      i: PromiseOrValue<BigNumberish>,
      j: PromiseOrValue<BigNumberish>,
      _dx: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;
  };

  filters: {};

  estimateGas: {
    exchange(
      i: PromiseOrValue<BigNumberish>,
      j: PromiseOrValue<BigNumberish>,
      dx: PromiseOrValue<BigNumberish>,
      min_dy: PromiseOrValue<BigNumberish>,
      receiver: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    get_dy(
      i: PromiseOrValue<BigNumberish>,
      j: PromiseOrValue<BigNumberish>,
      _dx: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;
  };

  populateTransaction: {
    exchange(
      i: PromiseOrValue<BigNumberish>,
      j: PromiseOrValue<BigNumberish>,
      dx: PromiseOrValue<BigNumberish>,
      min_dy: PromiseOrValue<BigNumberish>,
      receiver: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    get_dy(
      i: PromiseOrValue<BigNumberish>,
      j: PromiseOrValue<BigNumberish>,
      _dx: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;
  };
}