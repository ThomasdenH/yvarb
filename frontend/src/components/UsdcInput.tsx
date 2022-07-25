import { BigNumber, utils } from "ethers";
import React from "react";
import { formatUSDC } from "../utils";
import "./UsdcInput.scss";

interface Props {
  onValueChange(value: BigNumber): unknown;
  defaultValue: BigNumber;
  max: BigNumber;
}

interface State {
  value: string;
  prettyValue?: string;
  focus: boolean;
}

export default class UsdcInput extends React.Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = {
      value: utils.formatUnits(props.defaultValue, 6),
      focus: false,
      prettyValue: formatUSDC(props.defaultValue),
    };
  }

  render(): React.ReactNode {
    const value =
      !this.state.focus && this.state.prettyValue !== undefined
        ? this.state.prettyValue
        : this.state.value;
    const valid = this.state.prettyValue !== undefined;
    return (
      <input
        className={"usdc_input" + (valid ? "" : " invalid")}
        name="invest_amount"
        type="text"
        min="0"
        max={this.props.max.toNumber()}
        value={value}
        onChange={(el) => this.onChange(el.target.value)}
        onFocus={() => this.setState({ focus: true })}
        onBlur={() => this.setState({ focus: false })}
      />
    );
  }

  private onChange(value: string) {
    if (this.state.focus) {
      const parsedValue = UsdcInput.parsedValue(value);
      if (parsedValue !== undefined) {
        this.props.onValueChange(parsedValue);
      }
      const prettyValue =
        parsedValue === undefined ? undefined : formatUSDC(parsedValue);
      this.setState({ prettyValue, value });
    }
  }

  private static parsedValue(val: string): BigNumber | undefined {
    try {
      return utils.parseUnits(val, 6);
    } catch (e) {
      return undefined;
    }
  }
}
