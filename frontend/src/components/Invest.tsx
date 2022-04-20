import { BigNumber, utils } from "ethers";
import React from "react";
import { Contracts, ILK_ID, SERIES_ID } from "../App";
import "./Invest.scss";
import Slippage from "./Slippage";
import UsdcInput from "./UsdcInput";
import ValueDisplay, { ValueType } from "./ValueDisplay";
import {
  DebtResponse as Debt,
  SeriesResponse as Series,
  ContractContext as Cauldron,
} from "../abi/Cauldron";

const UNITS_USDC: number = 6;
const UNITS_LEVERAGE: number = 2;

interface Properties {
  usdcBalance: BigNumber;
  account: string;
  label: string;
  contracts: Readonly<Contracts>;
}

enum ApprovalState {
  Loading,
  ApprovalRequired,
  Transactable,
  DebtTooLow,
  Undercollateralized
}

interface State {
  usdcBalance: BigNumber;
  usdcToInvest: BigNumber;
  leverage: BigNumber;
  approvalState: ApprovalState;
  fyTokens?: BigNumber;
  slippage: number;
  interest?: number;
}

export default class Invest extends React.Component<Properties, State> {
  private readonly contracts: Readonly<Contracts>;
  private readonly account: string;
  private series?: Promise<Series>;

  constructor(props: Properties) {
    super(props);
    this.account = props.account;
    this.contracts = props.contracts;
    this.state = {
      usdcBalance: props.usdcBalance,
      usdcToInvest: props.usdcBalance,
      leverage: BigNumber.from(300),
      approvalState: ApprovalState.Loading,
      slippage: 1,
    };
  }

  render(): React.ReactNode {
    let component;
    switch (this.state.approvalState) {
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
            onClick={() => this.approve()}
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
            onClick={() => this.transact()}
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

    return (
      <div className="invest">
        <ValueDisplay
          label="Balance:"
          valueType={ValueType.Usdc}
          value={this.state.usdcBalance}
        />
        <label htmlFor="invest_amount">Amount to invest:</label>
        <UsdcInput
          max={this.state.usdcBalance}
          defaultValue={this.state.usdcBalance}
          onValueChange={(v) => this.onUsdcInputChange(v)}
        />
        <label htmlFor="leverage">
          Leverage: ({utils.formatUnits(this.state.leverage, 2)}×)
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
          label="Total collateral:"
          valueType={ValueType.Usdc}
          value={this.totalToInvest()}
        />
        {this.state.fyTokens !== undefined ? (
          <ValueDisplay
            key="fytokens"
            label="To borrow:"
            valueType={ValueType.FyUsdc}
            value={this.state.fyTokens}
          />
        ) : null}
        {this.state.interest !== undefined ? (
          <ValueDisplay
            label="Interest:"
            value={this.state.interest + "% APR"}
            valueType={ValueType.Literal}
          />
        ) : null}
        {component}
      </div>
    );
  }

  private async onSlippageChange(slippage: number) {
    this.setState({ slippage });
    await this.checkApprovalState();
  }

  private onUsdcInputChange(usdcToInvest: BigNumber) {
    this.setState({ usdcToInvest, approvalState: ApprovalState.Loading });
    this.checkApprovalState();
  }

  private async onLeverageChange(leverage: string) {
    this.setState({ leverage: utils.parseUnits(leverage, UNITS_LEVERAGE) });
    await this.checkApprovalState();
  }

  public componentDidMount() {
    this.checkApprovalState();
  }

  private totalToInvest(): BigNumber {
    try {
      return this.state.usdcToInvest.mul(this.state.leverage).div(100);
    } catch (e) {
      return BigNumber.from(0);
    }
  }

  private async checkApprovalState() {
    // First, set to loading
    this.setState({
      approvalState: ApprovalState.Loading
    });

    const series = await this.loadSeries();
    const allowance: BigNumber = await this.contracts.usdcContract.allowance(
      this.account,
      this.contracts.yieldLeverContract.address
    );
    const cauldronDebt = await this.cauldronDebt(
      this.contracts.cauldronContract,
      series.baseId
    );
    const minDebt = BigNumber.from(cauldronDebt.min).mul(
      BigNumber.from(10).pow(cauldronDebt.dec)
    );

    console.log(
      "Allowance: " +
        utils.formatUnits(allowance, UNITS_USDC) +
        ". To spend: " +
        utils.formatUnits(this.state.usdcToInvest, UNITS_USDC)
    );

    // Compute the amount of Fytokens
    const fyTokens = await this.fyTokens();

    const { ratio } = await this.contracts.cauldronContract.spotOracles(series.baseId, ILK_ID);
    const currentCollateralizationRatio = this.collateralizationRatio(fyTokens);

    if (minDebt.gt(fyTokens)) { // Check whether the minimum debt is reached
      this.setState({
        fyTokens,
        approvalState: ApprovalState.DebtTooLow
      });
    } else if (currentCollateralizationRatio.lt(ratio)) { // Check whether the vault would be collateralized
      this.setState({
        fyTokens,
        approvalState: ApprovalState.Undercollateralized
      });
    } else {
      const interest = await this.computeInterest();
      if (allowance.lt(this.state.usdcToInvest)) {
        this.setState({
          fyTokens,
          approvalState: ApprovalState.ApprovalRequired,
          interest,
        });
      } else {
        this.setState({
          fyTokens,
          approvalState: ApprovalState.Transactable,
          interest
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
  private async fyTokens(): Promise<BigNumber> {
    if (this.totalToInvest().eq(0)) return BigNumber.from(0);
    const leverage = this.totalToInvest().sub(this.state.usdcToInvest);
    return (await this.contracts.poolContract.buyBasePreview(leverage))
      .mul(1000 + this.state.slippage)
      .div(1000);
  }

  private async transact() {
    const leverage = this.totalToInvest().sub(this.state.usdcToInvest);
    const maxFy = await this.fyTokens();
    console.log(
      this.state.usdcToInvest.toString(),
      leverage.toString(),
      maxFy.toString(),
      SERIES_ID
    );
    const tx = await this.contracts.yieldLeverContract.invest(
      this.state.usdcToInvest,
      leverage,
      maxFy,
      SERIES_ID
    );
    await tx.wait();
  }

  private async loadSeries(): Promise<Series> {
    if (this.series === undefined)
      this.series = this.contracts.cauldronContract.series(
        SERIES_ID
      ) as Promise<Series>;
    return this.series;
  }

  private async computeInterest(): Promise<number> {
    const series = await this.loadSeries();
    const currentTime = Date.now() / 1000;
    const maturityTime = series.maturity;
    const toBorrow = this.totalToInvest().sub(this.state.usdcToInvest);
    const fyTokens = await this.contracts.poolContract.buyBasePreview(toBorrow);
    const year = 356.2425 * 24 * 60 * 60;
    const result_in_period =
      toBorrow.mul(1_000_000).div(fyTokens).toNumber() / 1_000_000;
    const interest_per_year = Math.pow(
      result_in_period,
      year / (maturityTime - currentTime)
    );
    return Math.round(10000 * (1 - interest_per_year)) / 100;
  }
}