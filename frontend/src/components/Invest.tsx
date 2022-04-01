import { BigNumber, ethers, utils } from "ethers";
import React from "react";
import './Invest.scss';

const UNITS_USDC: number = 6;
const UNITS_LEVERAGE: number = 2;

const SERIES_ID: string = "0x303230360000";

interface Properties {
  usdcBalance: BigNumber;
  usdcContract: ethers.Contract;
  account: string;
  yieldLeverContract: ethers.Contract;
  poolContract: ethers.Contract;
  label: string
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
          className="button" type="button" value="Approve" onClick={() => this.approve()} />
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
      <div className='invest'>
        <p>Balance: {utils.formatUnits(this.state.usdcBalance, UNITS_USDC)} USDC</p>
        <label htmlFor='invest_amount'>Amount to invest:</label>
        <input
          name='invest_amount'
          type="number"
          min="0"
          max={this.state.usdcBalance.toNumber()}
          value={utils.formatUnits(this.state.usdcToInvest, UNITS_USDC)}
          onChange={(el) => this.onUsdcInputChange(el.target.value)}
        />
        <label htmlFor='leverage'>Leverage: ({utils.formatUnits(this.state.leverage, 2)}×)</label>
        <input
          name='leverage'
          type="range"
          min="0"
          max="10"
          step="0.01"
          value={utils.formatUnits(this.state.leverage, 2)}
          onChange={(el) => this.onLeverageChange(el.target.value)}
        />
        {component}
      </div>
    );
  }

  private onUsdcInputChange(val: string) {
    if (val === "") {
      this.setState({
        usdcToInvest: BigNumber.from(0),
        approvalState: ApprovalState.Loading,
      });
    } else {
      const usdcToInvest = utils.parseUnits(val, UNITS_USDC);
      this.setState({ usdcToInvest, approvalState: ApprovalState.Loading });
    }
    this.checkApprovalState();
  }

  private onLeverageChange(leverage: string) {
    this.setState({ leverage: utils.parseUnits(leverage, UNITS_LEVERAGE) });
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
  }

  private async approve() {
    const tx = await this.usdcContract.approve(
      this.yieldLeverContract.address,
      this.state.usdcToInvest
    );
    await tx.wait();
    await this.checkApprovalState();
  }

  private async transact() {
    const leverage = this.totalToInvest().sub(this.state.usdcToInvest);
    // TODO: Flexible
    const maxYv = (await this.poolContract.buyBasePreview(leverage)).mul(2);
    console.log(
      this.state.usdcToInvest.toString(),
      leverage.toString(),
      maxYv.toString(),
      SERIES_ID
    );
    const tx = await this.yieldLeverContract.invest(
      this.state.usdcToInvest,
      leverage,
      maxYv,
      SERIES_ID
    );
    await tx.wait();
  }
}
