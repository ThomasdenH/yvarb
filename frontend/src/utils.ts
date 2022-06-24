import { BigNumber, ContractTransaction } from "ethers";

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

  while (decimals > 0 || !num.eq(0)) {
    decimals--;
    const digit = num.mod(10).toString();
    num = num.div(10);
    s = digit + s;
    if (decimals === 0) {
      s = "." + s;
      if (num.eq(0)) s = "0" + s;
    }
    if (decimals < 0 && decimals % 3 === 0 && !num.eq(0)) {
      s = "," + s;
    }
  }
  return s;
}
