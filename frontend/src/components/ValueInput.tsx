import { BigNumber, utils } from "ethers";
import { useEffect, useMemo, useState } from "react";
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

/** Format a BigNumber value as a decimal. */
const format = (value: BigNumber, decimals: number) =>
  utils.formatUnits(value, decimals);

/** Try to parse a value as a BigNumber, return undefined when parsing fails. */
const parseValue = (val: string, decimals: number): BigNumber | undefined => {
  try {
    return utils.parseUnits(val, decimals);
  } catch (e) {
    return undefined;
  }
};

// TODO: Use max
export const ValueInput = ({
  defaultValue,
  decimals,
  maxBigNumber,
  onValueChange,
}: Props) => {
  const defaultValueFormatted = format(defaultValue, decimals);

  /**
   * This is the "real" text content.
   */
  const [value, setValue] = useState<string>(defaultValueFormatted);
  /**
   * This is the parsed value, potentially undefined if the content could not
   * be parsed.
   */
  const parsedValue = useMemo(
    () => parseValue(value, decimals),
    [value, decimals]
  );
  // Update the listener when the value changes.
  useEffect(() => {
    if (parsedValue !== undefined) onValueChange(parsedValue);
  }, [parsedValue, onValueChange]);

  /**
   * This is the formatted value. It is defined when the parsed value is
   * defined.
   */
  const prettyValue: string | undefined =
    parsedValue === undefined ? undefined : format(parsedValue, decimals);

  const [focus, setFocus] = useState(false);

  const displayValue =
    !focus && prettyValue !== undefined ? prettyValue : value;
  const valid = prettyValue !== undefined;
  return (
    <input
      className={"usdc_input" + (valid ? "" : " invalid")}
      name="invest_amount"
      type="text"
      min="0"
      value={displayValue}
      onChange={(el) => setValue(el.target.value)}
      onFocus={() => setFocus(true)}
      onBlur={() => setFocus(false)}
    />
  );
};
