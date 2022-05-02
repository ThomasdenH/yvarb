import { BigNumber, utils } from "ethers";
import React from "react";
import { Contracts } from "../App";
import { Balance, Vault as VaultI } from "../objects/Vault";
import Slippage, { addSlippage, SLIPPAGE_OPTIONS } from "./Slippage";
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
  contracts: Readonly<Contracts>;
  pollData(): Promise<void>;
}

export default class Vault extends React.Component<Properties, State> {
  constructor(props: Properties) {
    super(props);
    this.state = {
      ...props,
      slippage: SLIPPAGE_OPTIONS[1].value,
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
          valueType={ValueType.Usdc}
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
          onClick={() => void this.unwind()}
        />
      </div>
    );
  }

  componentDidMount() {
    void this.updateToBorrow();
  }

  private onSlippageChange(slippage: number) {
    this.setState({ slippage, toBorrow: undefined });
    void this.updateToBorrow();
  }

  private async updateToBorrow() {
    this.setState({ toBorrow: await this.computeToBorrow() });
  }

  private async computeToBorrow(): Promise<BigNumber> {
    const balance = await this.props.contracts.cauldronContract.balances(
      this.props.vaultId
    );
    if (balance.art.eq(0)) return BigNumber.from(0);
    try {
      console.log(
        `Expected FY:\t${utils.formatUnits(
          await this.props.contracts.poolContracts[
            this.props.vault.seriesId
          ].buyFYTokenPreview(balance.art),
          6
        )} USDC`
      );
      return addSlippage(
        await this.props.contracts.poolContracts[
          this.props.vault.seriesId
        ].buyFYTokenPreview(balance.art),
        this.state.slippage
      );
    } catch (e) {
      // Past maturity
      console.log("Past maturity?");
      console.log(e);
      return BigNumber.from(0);
    }
  }

  private async unwind() {
    const [poolAddress, balances] = await Promise.all([
      this.props.contracts.ladleContract.pools(this.props.vault.seriesId),
      this.props.contracts.cauldronContract.balances(this.props.vaultId),
    ]);
    // Sanity check
    if (
      this.props.balance.art.eq(balances.art) &&
      this.props.balance.ink.eq(balances.ink)
    ) {
      while (this.state.toBorrow === undefined) {
        await this.updateToBorrow();
      }
      const maxFy = this.state.toBorrow;
      console.log(`Base required:\t${utils.formatUnits(maxFy, 6)} USDC`);
      console.log(
        this.props.vaultId,
        maxFy,
        poolAddress,
        balances.ink,
        balances.art,
        this.props.vault.seriesId
      );
      const gasLimit = (
        await this.props.contracts.yieldLeverContract.estimateGas.unwind(
          this.props.vaultId,
          maxFy,
          poolAddress,
          balances.ink,
          balances.art,
          this.props.vault.seriesId
        )
      )
        .mul(12)
        .div(10)
        .toNumber();
      const tx = await this.props.contracts.yieldLeverContract.unwind(
        this.props.vaultId,
        maxFy,
        poolAddress,
        balances.ink,
        balances.art,
        this.props.vault.seriesId,
        { gasLimit }
      );
      await tx.wait();

      await tx.wait();
      await Promise.all([this.props.pollData(), this.updateToBorrow()]);
    }
  }
}
