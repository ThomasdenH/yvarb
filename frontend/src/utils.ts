import { BigNumber } from "ethers";

export function formatNumber(
  num: BigNumber,
  decimals: number,
  defaultDecimals: number
): string {
  let s = "";

  const optionalDecimals = decimals - defaultDecimals;
  const optionalPart = 10 ** optionalDecimals;
  if (num.mod(optionalPart).eq(0)) {
    decimals = defaultDecimals;
    num = num.div(optionalPart);
  }

  // Start building the number from least significant to most significant.
  while (decimals > 0 || !num.eq(0)) {
    decimals--;
    const digit = num.mod(10).toString();
    num = num.div(10);
    s = digit + s;

    // If there are no decimals left, add a decimal point.
    if (decimals === 0) {
      s = "." + s;
      // In case there is no number left, add leading zero.
      if (num.eq(0)) s = "0" + s;
    }
    // Now, add a comma for each multiple of three
    if (decimals < 0 && decimals % 3 === 0 && !num.eq(0)) {
      s = "," + s;
    }
  }
  return s;
}
