import { BigNumber, ethers, utils } from "ethers";
import React from "react";
import { SERIES_ID } from "../App";
import { formatUSDC } from "../utils";
import "./Invest.scss";
import Slippage from "./Slippage";
import UsdcInput from "./UsdcInput";
import ValueDisplay, { ValueType } from "./ValueDisplay";

const UNITS_USDC: number = 6;
const UNITS_LEVERAGE: number = 2;

interface Properties {
  usdcBalance: BigNumber;
  usdcContract: ethers.Contract;
  account: string;
  yieldLeverContract: ethers.Contract;
  poolContract: ethers.Contract;
  label: string;
}

enum ApprovalState {
  Loading,
  ApprovalRequired,
  Transactable,
}

interface State {
  usdcBalance: BigNumber;
  usdcToInvest: BigNumber;
  leverage: BigNumber;
  approvalState: ApprovalState;
  fyTokens?: BigNumber;
  slippage: number;
}

export default class Invest extends React.Component<Properties, State> {
  private readonly usdcContract: ethers.Contract;
  private readonly yieldLeverContract: ethers.Contract;
  private readonly poolContract: ethers.Contract;
  private readonly account: string;

  constructor(props: Properties) {
    super(props);
    this.account = props.account;
    this.usdcContract = props.usdcContract;
    this.yieldLeverContract = props.yieldLeverContract;
    this.poolContract = props.poolContract;
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
        component = <p>Loading</p>;
        break;
      case ApprovalState.ApprovalRequired:
        component = (
          <input
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
            className="button"
            type="button"
            value="Transact!"
            onClick={() => this.transact()}
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
          name="leverage"
          type="range"
          min="1.01"
          max="10"
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
            label="To borrow:"
            valueType={ValueType.FyUsdc}
            value={this.state.fyTokens}
          />
        ) : (
          <></>
        )}
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
    const allowance: BigNumber = await this.usdcContract.allowance(
      this.account,
      this.yieldLeverContract.address
    );
    console.log(
      "Allowance: " +
        utils.formatUnits(allowance, UNITS_USDC) +
        ". To spend: " +
        utils.formatUnits(this.state.usdcToInvest, UNITS_USDC)
    );
    if (allowance.gte(this.state.usdcToInvest)) {
      this.setState({ approvalState: ApprovalState.Transactable });
    } else {
      this.setState({ approvalState: ApprovalState.ApprovalRequired });
    }

    // Compute the amount of Fytokens
    const fyTokens = await this.fyTokens();
    this.setState({
      fyTokens,
    });
  }

  private async approve() {
    const tx = await this.usdcContract.approve(
      this.yieldLeverContract.address,
      this.state.usdcToInvest
    );
    await tx.wait();
    await this.checkApprovalState();
  }

  private async fyTokens(): Promise<BigNumber> {
    const leverage = this.totalToInvest().sub(this.state.usdcToInvest);
    return (await this.poolContract.buyBasePreview(leverage))
      .mul(1000 + this.state.slippage)
      .div(1000);
  }

  private async transact() {
    const leverage = this.totalToInvest().sub(this.state.usdcToInvest);
    // TODO: Flexible
    const maxFy = await this.fyTokens();
    console.log(
      this.state.usdcToInvest.toString(),
      leverage.toString(),
      maxFy.toString(),
      SERIES_ID
    );
    const tx = await this.yieldLeverContract.invest(
      this.state.usdcToInvest,
      leverage,
      maxFy,
      SERIES_ID
    );
    await tx.wait();
  }
}
