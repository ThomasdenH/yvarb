import { BigNumber, utils } from "ethers";
import React, { useState } from "react";
import "./UsdcInput.scss";

interface Props {
  onValueChange(value: BigNumber): unknown;
  defaultValue: BigNumber;
  max: BigNumber;
  decimals: number;
}

export const BalanceInput: React.FunctionComponent = (props: Props) => {

  const format = (value: BigNumber, decimals: number) => utils.formatUnits(value, decimals);

  const parsedValue = (val: string): BigNumber | undefined => {
    try {
      return utils.parseUnits(val, props.decimals);
    } catch (e) {
      return undefined;
    }
  };

  const [value, setValue] = useState<string>(
    format(props.defaultValue, props.decimals)
  );
  const [prettyValue, setPrettyValue] = useState<string>(
    format(props.defaultValue, props.decimals)
  );
  const [focus, setFocus] = useState(false);

  const onChange = (value: string) => {
    if (focus) {
      const parsedValue = parsedValue(value);
      if (parsedValue !== undefined) {
        props.onValueChange(parsedValue);
      }
      setPrettyValue(
        parsedValue === undefined ? undefined : format(parsedValue, props.decimals)
      );
    }
  };

  const displayValue =
    !focus && prettyValue !== undefined ? prettyValue : value;
  const valid = prettyValue !== undefined;
  return (
    <input
      className={"usdc_input" + (valid ? "" : " invalid")}
      name="invest_amount"
      type="text"
      min="0"
      max={props.max.toNumber()}
      value={displayValue}
      onChange={(el) => onChange(el.target.value)}
      onFocus={() => setFocus(true)}
      onBlur={() => setFocus(false)}
    />
  );
};
