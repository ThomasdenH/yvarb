import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom";
import { Slippage, SLIPPAGE_OPTIONS } from "./Slippage";

describe("Slippage", () => {
  it("should be collapsed by default", () => {
    const value = SLIPPAGE_OPTIONS[0].value;
    render(
      <Slippage
        value={value}
        onChange={(v) => {
          void v;
        }}
      />
    );
    expect(screen.getByText("Slippage ⯆")).toBeInTheDocument();
    for (const { label } of SLIPPAGE_OPTIONS)
      expect(screen.queryByText(label)).toBeNull();
  });

  it("should be openable and closable", () => {
    const value = SLIPPAGE_OPTIONS[0].value;
    render(
      <Slippage
        value={value}
        onChange={(v) => {
          void v;
        }}
      />
    );

    // Open
    screen.getByText("Slippage ⯆").click();
    expect(screen.getByText("Slippage ⯅")).toBeInTheDocument();
    for (const { label } of SLIPPAGE_OPTIONS)
      expect(screen.getByText(label)).toBeInTheDocument();

    // Close
    screen.getByText("Slippage ⯅").click();
    expect(screen.getByText("Slippage ⯆")).toBeInTheDocument();
    for (const { label } of SLIPPAGE_OPTIONS)
      expect(screen.queryByText(label)).toBeNull();
  });

  it('should be clickable', () => {
    let value = SLIPPAGE_OPTIONS[0].value;
    render(
      <Slippage
        value={value}
        onChange={(v) => {
          value = v;
        }}
      />
    );
    // Open
    screen.getByText("Slippage ⯆").click();

    // Change slippage
    screen.getByText(SLIPPAGE_OPTIONS[1].label).click();

    expect(value).toEqual(SLIPPAGE_OPTIONS[1].value);
  });
});