import { BigNumber } from "ethers";
import { AssetId } from "../App";
import { formatNumber } from "../utils";
import "./ValueDisplay.scss";

export interface Balance {
  valueType: ValueType;
  value: BigNumber;
}

export enum ValueType {
  Literal,
  Balance
}


export enum Token {
  FyUsdc,
  FyWeth
}

export type Value =
  | {
      valueType: ValueType.Balance;
      token: AssetId.Usdc;
      value: BigNumber;
      label: string;
      className?: string;
    }
  | {
      valueType: ValueType.Balance;
      token: Token.FyUsdc;
      value: BigNumber;
      label: string;
      className?: string;
    }
  | {
      valueType: ValueType.Literal;
      value: string;
      label: string;
      className?: string;
    }
  | {
      valueType: ValueType.Balance;
      token: AssetId.WEth;
      value: BigNumber;
      label: string;
      className?: string;
    }
  | {
      valueType: ValueType.Balance;
      token: Token.FyWeth;
      value: BigNumber;
      label: string;
      className?: string;
    } | {
      valueType: ValueType.Balance;
      token: AssetId.WStEth;
      value: BigNumber;
      label: string;
      className?: string;
    };

export const ValueDisplay = (value: Value): JSX.Element => {
  let val;
  if (value.valueType === ValueType.Literal) {
    val = value.value;
  } else if (value.token === AssetId.Usdc) {
    val = formatNumber(value.value, 6, 2) + " USDC";
  } else if (value.token === Token.FyUsdc) {
    val = formatNumber(value.value, 6, 2) + " FYUSDC";
  } else if (value.token === AssetId.WEth) {
    val = formatNumber(value.value, 18, 6) + " WETH";
  } else if (value.token === Token.FyWeth) {
    val = formatNumber(value.value, 18, 6) + " FYWETH";
  } else if (value.token === AssetId.WStEth) {
    val = formatNumber(value.value, 18, 6) + " WSTETH";
  }
  return (
    <div
      className={
        value.className === undefined
          ? "value_display"
          : "value_display " + value.className
      }
    >
      <p className="value_label">{value.label}</p>
      <p className="value_value">{val}</p>
    </div>
  );
}
