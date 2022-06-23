import { BigNumber, utils } from "ethers";
import React, { useState, useEffect } from "react";
import { Contracts, ILK_ID, Strategy } from "../App";
import "./Invest.scss";
import Slippage, { addSlippage, SLIPPAGE_OPTIONS } from "./Slippage";
import UsdcInput, { BalanceInput } from "./UsdcInput";
import ValueDisplay, { Balance, ValueType } from "./ValueDisplay";
import {
  DebtResponse as Debt,
  SeriesResponse as Series,
  ContractContext as Cauldron,
} from "../abi/Cauldron";
import { SeriesDefinition } from "../objects/Vault";

const UNITS_USDC = 6;
const UNITS_LEVERAGE = 2;

interface Properties {
  /** Relevant token balances. */
  strategy: Strategy;
  balances: Balance[];
  account: string;
  label: string;
  contracts: Readonly<Contracts>;
  yearnApi?: number;
  seriesDefinitions: SeriesDefinition[];
  seriesInfo: { [seriesId: string]: Series };
}

enum ApprovalState {
  Loading,
  ApprovalRequired,
  Transactable,
  DebtTooLow,
  Undercollateralized,
}

interface State {
  usdcToInvest: BigNumber;
  leverage: BigNumber;
  approvalState: ApprovalState;
  fyTokens?: BigNumber;
  slippage: number;
  selectedSeriesId?: string;
  interest?: number;
  seriesInterest: { [seriesId: string]: number };
}

export const Invest = () => {
  const [slippage, setSlippage] = useState<number>(SLIPPAGE_OPTIONS[1].value);
  const [leverage, setLeverage] = useState<BigNumber>(BigNumber.from(300));
  const [balances, setBalances] = useState<BigNumber[] | undefined>(undefined);
  const [balanceInput, setBalanceInput] = useState<BigNumber>(BigNumber.from(0));

  const onLeverageChange = (leverage: string) => {
    setLeverage(utils.parseUnits(leverage, UNITS_LEVERAGE));
    setApprovalState(ApprovalState.Loading);
  };

  const [approvalState, setApprovalState] = useState<ApprovalState>(
    ApprovalState.Loading
  );
  
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
    case ApprovalState.ApprovalRequired:
      component = (
        <input
          key="approve"
          className="button"
          type="button"
          value="Approve"
          onClick={() => void this.approve()}
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
          onClick={() => void this.transact()}
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

  if (balances === undefined)
    return <></>;

  return (
    <div className="invest">
      {
        balances.map((balance: BigNumber) => <ValueDisplay
          label="Balance:"
          valueType={ValueType.Usdc}
          value={balance}
        />)
      }
      <label htmlFor="invest_amount">Amount to invest:</label>
      <BalanceInput
        max={balances[0]}
        defaultValue={balances[0]}
        onValueChange={(v) => setBalanceInput(v)}
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
        value={utils.formatUnits(this.state.leverage, 2)}
        onChange={(el) => this.onLeverageChange(el.target.value)}
      />
      <Slippage
        value={this.state.slippage}
        onChange={(val: number) => this.onSlippageChange(val)}
      />
      <ValueDisplay
        label="To borrow:"
        valueType={ValueType.Usdc}
        value={this.toBorrow()}
      />
      {this.state.fyTokens === undefined ? (
        <></>
      ) : (
        <>
          <ValueDisplay
            label="Total interest:"
            valueType={ValueType.Usdc}
            value={this.state.fyTokens.sub(this.toBorrow())}
          />
          <ValueDisplay
            className="value_sum"
            key="fytokens"
            label="Debt on maturity:"
            valueType={ValueType.Usdc}
            value={this.state.fyTokens}
          />
        </>
      )}
      {this.state.selectedSeriesId !== undefined &&
      this.state.seriesInterest[this.state.selectedSeriesId] !== undefined ? (
        <ValueDisplay
          label="Yield interest:"
          value={`${
            this.state.seriesInterest[this.state.selectedSeriesId]
          } % APY`}
          valueType={ValueType.Literal}
        />
      ) : null}
      {this.props.yearnApi !== undefined ? (
        <ValueDisplay
          label="Yearn interest (after fees):"
          value={`${Math.round(this.props.yearnApi * 1000) / 10} % APY`}
          valueType={ValueType.Literal}
        />
      ) : null}
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

  private toBorrow(): BigNumber {
    return this.totalToInvest().sub(this.state.usdcToInvest);
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

  private async cauldronDebt(
    cauldronContract: Cauldron,
    baseId: string
  ): Promise<Debt> {
    return await cauldronContract.debt(baseId, ILK_ID);
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
