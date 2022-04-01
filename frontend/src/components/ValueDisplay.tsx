import { BigNumber } from "ethers";
import { formatNumber, formatUSDC } from "../utils";
import "./ValueDisplay.scss";

export enum ValueType {
  Usdc,
  FyUsdc,
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
    };

export default function ValueDisplay(value: Value): JSX.Element {
  let val;
  if (value.valueType === ValueType.Usdc) {
    val = formatUSDC(value.value);
  } else if (value.valueType === ValueType.FyUsdc) {
    val = formatNumber(value.value, 6, 2) + " FYUSDC";
  }
  return (
    <div className="value_display">
      <p className="value_label">{value.label}</p>
      <p className="value_value">{val}</p>
    </div>
  );
}
