import { BigNumber, Contract, utils } from "ethers";
import React from "react";
import { SERIES_ID } from "../App";
import { Balance, Vault as VaultI } from "../objects/Vault";
import Slippage from "./Slippage";
import ValueDisplay, { ValueType } from "./ValueDisplay";
import "./Vault.scss";

interface State {
  balance: Balance;
  vault: VaultI;
  slippage: number;
  toBorrow?: BigNumber;
}

interface Properties {
  vaultId: string;
  balance: Balance;
  vault: VaultI;
  label: string;
  cauldron: Contract;
  ladle: Contract;
  yieldLever: Contract;
  pool: Contract;
  pollData(): Promise<void>;
}

export default class Vault extends React.Component<Properties, State> {
  constructor(props: Properties) {
    super(props);
    this.state = {
      ...props,
      slippage: 1,
    };
  }

  render(): React.ReactNode {
    return (
      <div className="vault">
        <ValueDisplay
          label="Vault ID:"
          value={this.props.vaultId}
          valueType={ValueType.Literal}
        />
        <ValueDisplay
          label="Collateral:"
          valueType={ValueType.Usdc}
          value={this.props.balance.ink}
        />
        <ValueDisplay
          label="Debt:"
          valueType={ValueType.FyUsdc}
          value={this.props.balance.art}
        />
        <Slippage
          value={this.state.slippage}
          onChange={(s) => this.onSlippageChange(s)}
        />
        {this.state.toBorrow !== undefined ? (
          <ValueDisplay
            label="To borrow:"
            valueType={ValueType.Usdc}
            value={this.state.toBorrow}
          />
        ) : null}
        <input
          className="button"
          value="Unwind"
          type="button"
          onClick={() => this.unwind()}
        />
      </div>
    );
  }

  componentDidMount() {
    this.updateToBorrow();
  }

  private async onSlippageChange(slippage: number) {
    this.setState({ slippage });
    await this.updateToBorrow();
  }

  private async updateToBorrow() {
    this.setState({ toBorrow: await this.computeToBorrow() });
  }

  private async computeToBorrow(): Promise<BigNumber> {
    const balance = await this.props.cauldron.balances(this.props.vaultId);
    if (balance.art.eq(0)) return BigNumber.from(0);
    try {
      return (await this.props.pool.buyFYTokenPreview(balance.art))
        .mul(1000 + this.state.slippage)
        .div(1000);
    } catch (e) {
      // Past maturity
      console.log("Past maturity?");
      console.log(e);
      return BigNumber.from(0);
    }
  }

  private async unwind() {
    const [poolAddress, balances] = await Promise.all([
      this.props.ladle.pools(SERIES_ID),
      this.props.cauldron.balances(this.props.vaultId),
    ]);
    if (
      this.props.balance.art.eq(balances.art) &&
      this.props.balance.ink.eq(balances.ink)
    ) {
      const maxFy = await this.computeToBorrow();
      console.log("Base required: " + utils.formatUnits(maxFy, 6) + " USDC");
      const tx = await this.props.yieldLever.unwind(
        this.props.vaultId,
        maxFy,
        poolAddress,
        balances.ink,
        balances.art,
        SERIES_ID
      );
      await tx.wait();
      await Promise.all([this.props.pollData(), this.updateToBorrow()]);
    }
  }
}
