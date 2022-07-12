import { IERC20Address } from "../balances";
import { ContractAddress, WETH, YIELD_ST_ETH_LEVER } from "../contracts";

export enum AssetId {
  WEth = "0x303000000000",
  WStEth = "0x303400000000",
  Usdc = "0x303200000000",
}

// TODO: Idea: create this from AssetId. I.e., represent FyUsdc as
// 'fy' + AssetId.Usdc
export enum Token {
    FyUsdc,
    FyWeth
}

export enum StrategyName {
  WStEth,
}

/**
 * The type of token that is invested for this strategy.
 * -  If the type is `FyToken`, the address is derived from the selected
 *    `seriesId`.
 */
export enum InvestTokenType {
  /** Use the debt token corresponding to the series. */
  FyToken,
}

/**
 * A strategy represents one particular lever to use, although it can contain
 * multiple series with different maturities.
 */
// TODO: Find the best format to be applicable for any strategy while avoiding
//  code duplication.
export interface Strategy {
  /** This is the token that is invested for this strategy. */
  investToken: InvestTokenType;
  /** The token that is obtained after unwinding. */
  outToken: [IERC20Address, Token | AssetId];
  lever: ContractAddress;
  ilkId: AssetId;
  baseId: AssetId;
}

/**
 * Get the concrete invest token type from a series. I.e. get `FyWEth` instead
 * of `FyToken`.
 */
export const getInvestToken = ({
  investToken,
  baseId,
}: Strategy): Token | AssetId => {
  if (investToken === InvestTokenType.FyToken) {
    switch (baseId) {
      case AssetId.WEth:
        return Token.FyWeth;
    }
  }
  throw new Error("Unimplemented");
};

export const STRATEGIES: { [strat in StrategyName]: Strategy } = {
  [StrategyName.WStEth]: {
    investToken: InvestTokenType.FyToken,
    outToken: [WETH, AssetId.WEth],
    lever: YIELD_ST_ETH_LEVER,
    ilkId: AssetId.WStEth,
    baseId: AssetId.WEth,
  },
};
