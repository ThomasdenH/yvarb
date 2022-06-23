import { BigNumber } from "ethers";
import { formatNumber } from "../utils";
import "./ValueDisplay.scss";

export interface Balance {
  valueType: ValueType;
  value: BigNumber;
}

export enum ValueType {
  Usdc,
  FyUsdc,
  Literal,
}

type Value =
  | {
      valueType: ValueType.Usdc;
      value: BigNumber;
      label: string;
      className?: string;
    }
  | {
      valueType: ValueType.FyUsdc;
      value: BigNumber;
      label: string;
      className?: string;
    }
  | {
      valueType: ValueType.Literal;
      value: string;
      label: string;
      className?: string;
    };

export default function ValueDisplay(value: Value): JSX.Element {
  let val;
  if (value.valueType === ValueType.Usdc) {
    val = formatNumber(value.value, 6, 2) + " USDC";
  } else if (value.valueType === ValueType.FyUsdc) {
    val = formatNumber(value.value, 6, 2) + " FYUSDC";
  } else if (value.valueType === ValueType.Literal) {
    val = value.value;
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
