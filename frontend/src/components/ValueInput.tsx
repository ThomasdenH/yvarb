import { BigNumber, utils } from "ethers";
import { useState } from "react";
import "./ValueInput.scss";

/** A class used to let the user input a decimally interpreted BigNumber value.
 *
 */

interface Props {
  onValueChange(value: BigNumber): unknown;
  defaultValue: BigNumber;
  max: BigNumber;
  decimals: number;
}

export const ValueInput = (props: Props) => {
  /** Format a BigNumber value as a decimal. */
  const format = (value: BigNumber, decimals: number) =>
    utils.formatUnits(value, decimals);

  /** Try to parse a value as a BigNumber, return undefined when parsing fails. */
  const parseValue = (val: string): BigNumber | undefined => {
    try {
      return utils.parseUnits(val, props.decimals);
    } catch (e) {
      return undefined;
    }
  };

  const defaultValue = format(props.defaultValue, props.decimals);

  /** The value is the "real" value, the pretty value is only set if the number could be parsed. */
  const [value, setValue] = useState<string>(defaultValue);
  const [prettyValue, setPrettyValue] = useState<string | undefined>(
    defaultValue
  );
  const [focus, setFocus] = useState(false);

  const onChange = (value: string) => {
    if (focus) {
      const parsedValue = parseValue(value);
      if (parsedValue !== undefined) props.onValueChange(parsedValue);
      setValue(value);
      setPrettyValue(
        parsedValue === undefined
          ? undefined
          : format(parsedValue, props.decimals)
      );
    }
  };

  let max;
  try {
    max = props.max.div(BigNumber.from(10).pow(props.decimals)).toNumber()
  } catch (e) {
    max = undefined;
  }

  const displayValue =
    !focus && prettyValue !== undefined ? prettyValue : value;
  const valid = prettyValue !== undefined;
  return (
    <input
      className={"usdc_input" + (valid ? "" : " invalid")}
      name="invest_amount"
      type="text"
      min="0"
      max={max}
      value={displayValue}
      onChange={(el) => onChange(el.target.value)}
      onFocus={() => setFocus(true)}
      onBlur={() => setFocus(false)}
    />
  );
};
