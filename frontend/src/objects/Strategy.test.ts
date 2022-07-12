import { getInvestToken, STRATEGIES, StrategyName, Token } from "./Strategy";

describe("getInvestToken", () => {
  it("should return the correct token", () => {
    expect(getInvestToken(STRATEGIES[StrategyName.WStEth])).toBe(Token.FyWeth);
  });
});
