import { fireEvent, render, screen } from "@testing-library/react";
import "@testing-library/jest-dom";
import { BigNumber } from "ethers";
import { ValueInput } from "./ValueInput";
import { act } from "react-dom/test-utils";

describe("ValueInput", () => {
  it("should be initialized correctly", () => {
    render(
      <ValueInput
        defaultValue={BigNumber.from(1000)}
        decimals={2}
        onValueChange={(val) => {
          void val;
        }}
        max={BigNumber.from(10000)}
      />
    );
    expect(screen.getByDisplayValue("10.0")).toBeInTheDocument();
  });

  it("should update with valid input", () => {
    render(
      <ValueInput
        defaultValue={BigNumber.from(20)}
        decimals={2}
        onValueChange={(val) => {
          void val;
        }}
        max={BigNumber.from(10000)}
      />
    );
    const element = screen.getByDisplayValue("0.2");
    expect(element).toBeInTheDocument();
    act(() => {
      fireEvent.change(element, { target: { value: "0.35000" } });
    });
    // This value has been parsed: trailing zeros have been removed
    expect((element as HTMLInputElement).value).toEqual("0.35");

    // Focus: display real value
    act(() => {
      element.focus();
    });
    expect((element as HTMLInputElement).value).toEqual("0.35000");
  });

  it("should display real value if not parsable", () => {
    render(
      <ValueInput
        defaultValue={BigNumber.from(20)}
        decimals={2}
        onValueChange={(val) => {
          void val;
        }}
        max={BigNumber.from(10000)}
      />
    );
    const element = screen.getByDisplayValue("0.2");
    expect(element).toBeInTheDocument();

    const notParsableValue = "Not Parsable";
    act(() => {
      fireEvent.change(element, { target: { value: notParsableValue } });
    });
    // This value has been parsed: trailing zeros have been removed
    expect((element as HTMLInputElement).value).toEqual(notParsableValue);
  });
});
