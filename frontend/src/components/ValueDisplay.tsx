import { BigNumber } from "ethers";
import { formatNumber, formatUSDC } from "../utils";
import "./ValueDisplay.scss";

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
    }
  | {
      valueType: ValueType.FyUsdc;
      value: BigNumber;
      label: string;
    }
  | {
      valueType: ValueType.Literal;
      value: string;
      label: string;
    };

export default function ValueDisplay(value: Value): JSX.Element {
  let val;
  if (value.valueType === ValueType.Usdc) {
    val = formatUSDC(value.value);
  } else if (value.valueType === ValueType.FyUsdc) {
    val = formatNumber(value.value, 6, 2) + " FYUSDC";
  } else if (value.valueType === ValueType.Literal) {
    val = value.value;
  }
  return (
    <div className="value_display">
      <p className="value_label">{value.label}</p>
      <p className="value_value">{val}</p>
    </div>
  );
}
