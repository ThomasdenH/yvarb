import { BigNumber } from "ethers";
import { formatNumber } from "./utils";

describe("formatNumber", () => {
  it("should format numbers correctly", () => {
    expect(formatNumber(BigNumber.from(123456789), 4, 2)).toEqual(
      "12,345.6789"
    );
  });

  it("should omit zero non necessary decimals", () => {
    expect(formatNumber(BigNumber.from(10000), 4, 2)).toEqual("1.00");
  });

  it("should add a leading zero if necessary", () => {
    expect(formatNumber(BigNumber.from(120), 3, 3)).toEqual("0.120");
  });

  it("should use comma's for multiples of thousand", () => {
    expect(formatNumber(BigNumber.from(123456789), 0, 0)).toEqual("123,456,789");
  });
});
