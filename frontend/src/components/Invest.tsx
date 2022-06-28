import { BigNumber, Signer, utils } from "ethers";
import React, { useState } from "react";
import { App, Strategy } from "../App";
import "./Invest.scss";
import Slippage, { SLIPPAGE_OPTIONS } from "./Slippage";
import { ValueInput } from "./ValueInput";
import ValueDisplay, { ValueType } from "./ValueDisplay";
import { Balances } from "../balances";
import { Contracts, getContract, YIELD_ST_ETH_LEVER } from "../contracts";
import { useEffect } from "react";

const SERIES_ID = "0x303030370000";

interface Properties {
  /** Relevant token balances. */
  strategy: Strategy;
  account: Signer;
  label: string;
  contracts: Contracts;
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
}

const UNITS_LEVERAGE = 2;

const Loading = () => (
  <div className="invest">
    <p>Loading...</p>
  </div>
);

export const Invest = ({
  balances,
  contracts,
  strategy,
  account,
}: Readonly<Properties>) => {
  const [slippage, setSlippage] = useState<number>(SLIPPAGE_OPTIONS[1].value);
  const [leverage, setLeverage] = useState<BigNumber>(BigNumber.from(300));
  const [balanceInput, setBalanceInput] = useState<BigNumber>(
    BigNumber.from(0)
  );

  const changeInput = (v: BigNumber) => {
    setApprovalState(ApprovalState.Loading);
    setBalanceInput(v);
  };

  const onLeverageChange = (leverage: string) => {
    setLeverage(utils.parseUnits(leverage, UNITS_LEVERAGE));
    setApprovalState(ApprovalState.Loading);
  };

  const [approvalState, setApprovalState] = useState<ApprovalState>(
    ApprovalState.Loading
  );
  const checkApprovalState = async () => {
    const investable = totalToInvest();
    const token = getContract(strategy.investToken[0], contracts, account);
    const approval = await token.allowance(
      account.getAddress(),
      strategy.lever
    );
    if (approval.lt(investable)) {
      setApprovalState(ApprovalState.ApprovalRequired);
    } else {
      setApprovalState(ApprovalState.Transactable);
    }
  };

  const approve = async () => {
    const investable = totalToInvest();
    const token = getContract(strategy.investToken[0], contracts, account);
    const gasLimit = (
      await token.estimateGas.approve(strategy.lever, investable)
    ).mul(2);
    const tx = await token.approve(strategy.lever, investable, { gasLimit });
    await tx.wait();
    setApprovalState(ApprovalState.Loading);
  };

  const transact = async () => {
    if (strategy.lever === YIELD_ST_ETH_LEVER) {
      const lever = getContract(strategy.lever, contracts, account);
      console.log(
        balanceInput.toString(),
        toBorrow().toString(),
        BigNumber.from(0),
        SERIES_ID
      );
      // TODO: Minimum collateral
      const gasLimit = (
        await lever.estimateGas.invest(
          balanceInput,
          toBorrow(),
          BigNumber.from(0),
          SERIES_ID
        )
      ).mul(2);
      const invextTx = await lever.invest(
        balanceInput,
        toBorrow(),
        BigNumber.from(0),
        SERIES_ID,
        { gasLimit }
      );
      await invextTx.wait();
      setApprovalState(ApprovalState.Loading);
    }
  };

  const toBorrow = (): BigNumber => totalToInvest().sub(balanceInput);

  const totalToInvest = (): BigNumber => {
    try {
      return balanceInput.mul(leverage).div(100);
    } catch (e) {
      return BigNumber.from(0);
    }
  };

  useEffect(() => {
    if (approvalState === ApprovalState.Loading) void checkApprovalState();
  });

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
        onValueChange={(v) => changeInput(v)}
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
        onChange={(el) => onLeverageChange(el.currentTarget.value)}
      />
      <Slippage value={slippage} onChange={(val: number) => setSlippage(val)} />
      <ValueDisplay
        label="To borrow:"
        valueType={strategy.investToken[1] as ValueType.FyUsdc}
        value={toBorrow()}
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
