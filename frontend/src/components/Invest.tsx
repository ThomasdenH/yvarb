import { BigNumber, Signer, utils } from "ethers";
import React, { MutableRefObject, useMemo, useState } from "react";
import { Strategy } from "../App";
import "./Invest.scss";
import { Slippage, removeSlippage, useSlippage } from "./Slippage";
import { ValueInput } from "./ValueInput";
import ValueDisplay, { ValueType } from "./ValueDisplay";
import { Balances, FY_WETH } from "../balances";
import {
  CAULDRON,
  Contracts,
  getContract,
  getPool,
  WETH_ST_ETH_STABLESWAP,
  WST_ETH,
  YIELD_ST_ETH_LEVER,
} from "../contracts";
import { useEffect } from "react";
import { IOracle__factory } from "../contracts/IOracle.sol";
import { zeroPad } from "ethers/lib/utils";

const SERIES_ID = "0x303030370000";

interface Properties {
  /** Relevant token balances. */
  strategy: Strategy;
  account: Signer;
  label: string;
  contracts: MutableRefObject<Contracts>;
  yearnApi?: number;
  balances: Balances;
  //vaultAdded(vaultId: string): void;
}

enum ApprovalState {
  Loading,
  ApprovalRequired,
  Transactable,
  DebtTooLow,
  Undercollateralized,
  Approving,
  Transacting,
}

const gasPrice = utils.parseUnits("100", "gwei");

const UNITS_LEVERAGE = 2;

const Loading = () => (
  <div className="invest">
    <p>Loading...</p>
  </div>
);

/**
 * Compute how much collateral would be generated by investing with these
 * parameters.
 */
const computeStEthCollateral = async (
  baseAmount: BigNumber,
  toBorrow: BigNumber,
  contracts: MutableRefObject<Contracts>,
  account: Signer
): Promise<BigNumber> => {
  // - netInvestAmount = baseAmount + borrowAmount - fee
  const fyWeth = getContract(FY_WETH, contracts, account);
  const fee = await fyWeth.flashFee(fyWeth.address, toBorrow);
  const netInvestAmount = baseAmount.add(toBorrow).sub(fee);
  // - sellFyWeth: FyWEth -> WEth
  const pool = await getPool(SERIES_ID, contracts, account);
  const obtainedWEth = await pool.sellFYTokenPreview(netInvestAmount);
  // - stableSwap exchange: WEth -> StEth
  const stableswap = getContract(WETH_ST_ETH_STABLESWAP, contracts, account);
  const boughtStEth = await stableswap.get_dy(0, 1, obtainedWEth);
  // - Wrap: StEth -> WStEth
  const wStEth = getContract(WST_ETH, contracts, account);
  const wrapped = await wStEth.getWstETHByStETH(boughtStEth);
  return wrapped;
};

const cauldronDebt = async (
  contracts: MutableRefObject<Contracts>,
  account: Signer,
  strategy: Strategy
) => {
  const cauldron = getContract(CAULDRON, contracts, account);
  return await cauldron.debt(strategy.baseId, strategy.ilkId);
};

/**
 * Same functionality as the vaultlevel function in cauldron. If this returns
 * a negative number, the vault would be undercollateralized.
 */
const vaultLevel = async (
  ink: BigNumber,
  art: BigNumber,
  contracts: MutableRefObject<Contracts>,
  account: Signer,
  strategy: Strategy
): Promise<BigNumber> => {
  const cauldron = getContract(CAULDRON, contracts, account);
  const spotOracle = await cauldron.spotOracles(
    strategy.baseId,
    strategy.ilkId
  );
  const ratio = BigNumber.from(spotOracle.ratio).mul(
    BigNumber.from(10).pow(12)
  );
  const inkValue = (
    await IOracle__factory.connect(spotOracle.oracle, account).peek(
      utils.concat([strategy.ilkId, zeroPad([], 32 - 6)]),
      utils.concat([strategy.baseId, zeroPad([], 32 - 6)]),
      ink
    )
  ).value;
  console.log(
    inkValue.toString(),
    art.toString(),
    art.mul(ratio).div(BigNumber.from(10).pow(18)).toString()
  );
  return inkValue.sub(art.mul(ratio).div(BigNumber.from(10).pow(18)));
};

export const DEFAULT_LEVERAGE = BigNumber.from(300);

export const Invest = ({
  balances,
  contracts,
  strategy,
  account,
}: Readonly<Properties>) => {
  const [slippage, setSlippage] = useSlippage();
  const [leverage, setLeverage] = useState(DEFAULT_LEVERAGE);
  const [balanceInput, setBalanceInput] = useState(BigNumber.from(0));

  // Use `useMemo` here because every BigNumber will be different while having
  // the same value. That means that effects will be triggered continuously.
  const totalToInvest = useMemo(
    () => balanceInput.mul(leverage).div(100),
    [balanceInput, leverage]
  );
  const toBorrow = useMemo(
    () => totalToInvest.sub(balanceInput),
    [totalToInvest, balanceInput]
  );

  /** The resulting collateral after having invested. */
  const [stEthCollateral, setStEthCollateral] = useState<
    BigNumber | undefined
  >();
  useEffect(() => {
    if (balanceInput.eq(0)) {
      setStEthCollateral(BigNumber.from(0));
      return;
    }
    let shouldUseResult = true;
    void computeStEthCollateral(
      balanceInput,
      toBorrow,
      contracts,
      account
    ).then((v) => {
      if (shouldUseResult) setStEthCollateral(v);
    });
    return () => {
      shouldUseResult = false;
    };
  }, [account, balanceInput, contracts, toBorrow]);

  /**
   * The minimum collateral that must be obtained when invested. The result of
   */
  const stEthMinCollateral = useMemo(
    () =>
      stEthCollateral === undefined
        ? undefined
        : removeSlippage(stEthCollateral, slippage),
    [stEthCollateral, slippage]
  );

  /**
   * The approval state represents whether it is currently possible to
   * transact, whether approval is required or whether there is a reason not to
   * transact.
   */
  const [approvalState, setApprovalState] = useState<ApprovalState>(
    ApprovalState.Loading
  );
  const [approvalStateInvalidator, setApprovalStateInvalidator] = useState(0);
  useEffect(() => {
    if (stEthCollateral === undefined) return; // Not loaded. The effect will automatically rerun once defined.

    // If this effect was superceded, this will be false and the state won't be
    // updated by this instance.
    let shouldUseResult = true;
    setApprovalState(ApprovalState.Loading);

    const checkApprovalState = async (): Promise<ApprovalState> => {
      // First check if the debt is too low
      if (totalToInvest.eq(0)) return ApprovalState.DebtTooLow;

      const debt = await cauldronDebt(contracts, account, strategy);
      const minDebt = BigNumber.from(debt.min).mul(
        BigNumber.from(10).pow(debt.dec)
      );
      if (stEthCollateral.lt(minDebt)) return ApprovalState.DebtTooLow;

      // Now check collateralization ratio
      const level = await vaultLevel(
        totalToInvest,
        toBorrow,
        contracts,
        account,
        strategy
      );
      if (level.lt(0)) return ApprovalState.Undercollateralized;

      // Now check for approval
      const token = getContract(strategy.investToken[0], contracts, account);
      const approval = await token.allowance(
        account.getAddress(),
        strategy.lever
      );
      if (approval.lt(totalToInvest)) return ApprovalState.ApprovalRequired;
      return ApprovalState.Transactable;
    };
    void checkApprovalState().then((ap) => {
      if (shouldUseResult) setApprovalState(ap);
    });
    return () => {
      shouldUseResult = false;
    };
  }, [
    account,
    strategy,
    toBorrow,
    totalToInvest,
    stEthCollateral,
    contracts,
    approvalStateInvalidator,
  ]);

  const approve = async () => {
    setApprovalState(ApprovalState.Approving);
    const token = getContract(strategy.investToken[0], contracts, account);
    const gasLimit = (
      await token.estimateGas.approve(strategy.lever, totalToInvest)
    ).mul(2);
    const tx = await token.approve(strategy.lever, totalToInvest, {
      gasLimit,
      gasPrice,
    });
    await tx.wait();
    setApprovalStateInvalidator((v) => v + 1);
  };

  const transact = async () => {
    if (stEthMinCollateral === undefined) return; // Not yet loaded!
    setApprovalState(ApprovalState.Transacting);
    if (strategy.lever === YIELD_ST_ETH_LEVER) {
      const lever = getContract(strategy.lever, contracts, account);
      console.log(
        balanceInput.toString(),
        toBorrow.toString(),
        stEthMinCollateral.toString(),
        SERIES_ID
      );
      const gasLimit = (
        await lever.estimateGas.invest(
          balanceInput,
          toBorrow,
          stEthMinCollateral,
          SERIES_ID
        )
      ).mul(2);
      const invextTx = await lever.invest(
        balanceInput,
        toBorrow,
        stEthMinCollateral,
        SERIES_ID,
        { gasLimit, gasPrice }
      );
      console.log(invextTx);
      await invextTx.wait();
    }
    setApprovalStateInvalidator((v) => v + 1);
  };

  let component;
  switch (approvalState) {
    case ApprovalState.Loading:
      component = (
        <input
          key="loading"
          className="button"
          type="button"
          value="Loading..."
          disabled={true}
        />
      );
      break;
    case ApprovalState.Approving:
      component = (
        <input
          key="loading"
          className="button"
          type="button"
          value="Approving..."
          disabled={true}
        />
      );
      break;
    case ApprovalState.Transacting:
      component = (
        <input
          key="loading"
          className="button"
          type="button"
          value="Investing..."
          disabled={true}
        />
      );
      break;
    case ApprovalState.ApprovalRequired:
      component = (
        <input
          key="approve"
          className="button"
          type="button"
          value="Approve"
          onClick={() => void approve()}
        />
      );
      break;
    case ApprovalState.Transactable:
      component = (
        <input
          key="transact"
          className="button"
          type="button"
          value="Transact!"
          onClick={() => void transact()}
        />
      );
      break;
    case ApprovalState.DebtTooLow:
      component = (
        <input
          key="debttoolow"
          className="button"
          type="button"
          value="Debt too low!"
          disabled={true}
        />
      );
      break;
    case ApprovalState.Undercollateralized:
      component = (
        <input
          key="undercollateralized"
          className="button"
          type="button"
          value="Undercollateralized!"
          disabled={true}
        />
      );
      break;
  }

  // Collect all relevant balances of this strategy.
  const balancesAndDebtElements = [];
  for (const [address, valueType] of strategy.tokenAddresses.concat(
    strategy.debtTokens
  )) {
    const balance = balances[address];
    if (balance === undefined) {
      return Loading();
    }
    balancesAndDebtElements.push(
      <ValueDisplay
        key={address}
        label="Balance:"
        // TODO: Fix typing
        valueType={valueType as ValueType.Weth}
        value={balance}
      />
    );
  }

  const investTokenBalance = balances[strategy.investToken[0]];
  if (investTokenBalance === undefined) return Loading();

  return (
    <div className="invest">
      {balancesAndDebtElements}
      <label htmlFor="invest_amount">Amount to invest:</label>
      <ValueInput
        max={investTokenBalance}
        defaultValue={investTokenBalance}
        onValueChange={(v) => setBalanceInput(v)}
        decimals={18}
      />
      <label htmlFor="leverage">
        Leverage: ({utils.formatUnits(leverage, 2)}×)
      </label>
      <input
        className="leverage"
        name="leverage"
        type="range"
        min="1.01"
        max="5"
        step="0.01"
        value={utils.formatUnits(leverage, 2)}
        onChange={(el) =>
          setLeverage(utils.parseUnits(el.currentTarget.value, UNITS_LEVERAGE))
        }
      />
      <Slippage value={slippage} onChange={(val: number) => setSlippage(val)} />
      <ValueDisplay
        label="To borrow:"
        valueType={strategy.investToken[1] as ValueType.FyUsdc}
        value={toBorrow}
      />
      {component}
    </div>
  );
};

/*
export default class Invest extends React.Component<Properties, State> {

  private totalToInvest(): BigNumber {
    try {
      return this.state.usdcToInvest.mul(this.state.leverage).div(100);
    } catch (e) {
      return BigNumber.from(0);
    }
  }

  private async computeSeriesInterests() {
    for (let i = 0; i < this.props.seriesDefinitions.length; i++) {
      const series = this.props.seriesDefinitions[i];
      if (!Invest.isPastMaturity(this.props.seriesInfo[series.seriesId])) {
        console.log(series.seriesId);
        const toBorrow = BigNumber.from(100_000_000);
        const interest = await this.computeInterest(series.seriesId, toBorrow);
        this.setState({
          seriesInterest: {
            ...this.state.seriesInterest,
            [series.seriesId]: interest,
          },
        });
      }
    }
  }

  private collateralizationRatio(fyTokens: BigNumber): BigNumber {
    return this.totalToInvest().div(fyTokens.div(1_000_000));
  }

  private async approve() {
    const tx = await this.contracts.usdcContract.approve(
      this.contracts.yieldLeverContract.address,
      this.state.usdcToInvest
    );
    await tx.wait();
    await this.checkApprovalState();
  }

  /**
   * Compute the amount of fyTokens that would be drawn with the current settings.
   * @returns
   */
/*
  private async fyTokens(): Promise<BigNumber> {
    if (this.totalToInvest().eq(0) || this.state.selectedSeriesId === undefined)
      return BigNumber.from(0);
    const leverage = this.totalToInvest().sub(this.state.usdcToInvest);
    const poolContract =
      this.props.contracts.poolContracts[this.state.selectedSeriesId];
    return addSlippage(
      await poolContract.buyBasePreview(leverage),
      this.state.slippage
    );
  }

  private async transact() {
    if (this.state.selectedSeriesId === undefined) {
      return;
    }
    const leverage = this.totalToInvest().sub(this.state.usdcToInvest);
    const maxFy = await this.fyTokens();
    console.log(
      this.state.usdcToInvest.toString(),
      leverage.toString(),
      maxFy.toString(),
      this.state.selectedSeriesId
    );
    const gasLimit = (
      await this.contracts.yieldLeverContract.estimateGas.invest(
        this.state.usdcToInvest,
        leverage,
        maxFy,
        this.state.selectedSeriesId
      )
    )
      .mul(12)
      .div(10)
      .toNumber();
    const tx = await this.contracts.yieldLeverContract.invest(
      this.state.usdcToInvest,
      leverage,
      maxFy,
      this.state.selectedSeriesId,
      { gasLimit }
    );
    await tx.wait();
  }

  private async computeInterest(
    seriesId: string,
    toBorrow: BigNumber
  ): Promise<number> {
    const series = this.props.seriesInfo[seriesId];
    const poolContract = this.props.contracts.poolContracts[seriesId];
    const currentTime = Date.now() / 1000;
    const maturityTime = series.maturity;
    const fyTokens = await poolContract.buyBasePreview(toBorrow);
    const year = 356.2425 * 24 * 60 * 60;
    const result_in_period =
      toBorrow.mul(1_000_000).div(fyTokens).toNumber() / 1_000_000;
    const interest_per_year = Math.pow(
      result_in_period,
      year / (maturityTime - currentTime)
    );
    return Math.round(10000 * (1 - interest_per_year)) / 100;
  }

  private static isPastMaturity(seriesInfo: Series): boolean {
    return seriesInfo.maturity <= Date.now() / 1000;
  }
}
*/
