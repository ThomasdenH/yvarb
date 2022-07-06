/**
 * A selector for slippage.
 */

import { BigNumber } from "ethers";
import React, { useState } from "react";
import "./Slippage.scss";

export interface Properties {
  onChange(value: number): void;
  value: number;
}

const OPTIONS: { value: number; label: string }[] = [
  { value: 1, label: "0.1%" },
  { value: 5, label: "0.5%" },
  { value: 10, label: "1%" },
  { value: 50, label: "5%" },
];

export const SLIPPAGE_OPTIONS = OPTIONS;

export const useSlippage = () => useState(SLIPPAGE_OPTIONS[1].value);

export const addSlippage = (num: BigNumber, slippage: number) =>
  num.mul(1000 + slippage).div(1000);

export const removeSlippage = (num: BigNumber, slippage: number) =>
  num.mul(1000 - slippage).div(1000);

export const Slippage = ({ onChange, value }: Properties) => {
  const [open, setOpen] = useState(false);
  return (
    <div className="slippage">
      <p className="slippage_expand" onClick={() => setOpen(!open)}>
        {open ? "Slippage ⯅" : "Slippage ⯆"}
      </p>
      {open
        ? OPTIONS.map((option) => {
            const checked: boolean = value === option.value;
            return (
              <label
                key={option.value}
                className={
                  checked ? "slippage_option checked" : "slippage_option"
                }
              >
                <input
                  type="radio"
                  name={option.label}
                  value={option.value}
                  onChange={(val) => onChange(parseInt(val.target.value))}
                  checked={checked}
                />
                {option.label}
              </label>
            );
          })
        : null}
    </div>
  );
};
