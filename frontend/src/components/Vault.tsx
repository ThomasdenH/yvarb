import { BigNumber, ethers, Signer } from "ethers";
import React, { useEffect, useState } from "react";
import { MutableRefObject } from "react";
import { Strategy } from "../App";
import {
  Contracts,
  getContract,
  getPool,
  WETH_ST_ETH_STABLESWAP,
  WST_ETH,
  YIELD_ST_ETH_LEVER,
} from "../contracts";
import { Balance, Vault as VaultI } from "../objects/Vault";
import {
  Slippage,
  removeSlippage,
  useSlippage,
} from "./Slippage";
import ValueDisplay, { ValueType } from "./ValueDisplay";
import "./Vault.scss";

interface Properties {
  vaultId: string;
  balance: Balance;
  vault: VaultI;
  label: string;
  contracts: MutableRefObject<Contracts>;
  strategy: Strategy;
  account: Signer;
}

export const Vault = ({
  strategy,
  contracts,
  account,
  balance,
  vault,
  vaultId,
}: Properties) => {
  const [slippage, setSlippage] = useSlippage();

  /** How much weth we'll obtain, at a minimum. Includes slippage. */
  const [finalWeth, setFinalWeth] = useState<BigNumber | undefined>();
  useEffect(() => {
    if (balance.ink.eq(0)) {
      setFinalWeth(BigNumber.from(0));
      return;
    }
    /**
     * Compute how much WEth the user has at the end of the operation.
     */
    const computeResultWeth = async () => {
      const fyToken = getContract(
        strategy.debtTokens[0][0],
        contracts,
        account
      );
      const maturity = await fyToken.maturity();
      const blockNumber = (await account.provider?.getBlockNumber()) as number;
      const blockTime = (await account.provider?.getBlock(blockNumber))
        ?.timestamp as number;
      if (BigNumber.from(blockTime).lt(maturity)) {
        // Repay!
        // Basically rerun the entire process and see how much we end up with.
        const wStEth = getContract(WST_ETH, contracts, account);
        const stEthUnwrapped = await wStEth.getStETHByWstETH(balance.ink);
        const stableSwap = getContract(
          WETH_ST_ETH_STABLESWAP,
          contracts,
          account
        );
        const wethReceived = await stableSwap.get_dy(1, 0, stEthUnwrapped);
        const fee = await fyToken.flashFee(fyToken.address, balance.art);
        const borrowAmountPlusFee = fee.add(balance.art);
        const pool = await getPool(vault.seriesId, contracts, account);
        const wethToTran = await pool.buyFYTokenPreview(borrowAmountPlusFee);
        const wethRemaining = wethReceived.sub(wethToTran);
        return wethRemaining;
      } else {
        throw new Error("Unimplemented");
      }
    };
    setFinalWeth(undefined);
    void computeResultWeth()
      .then((val) => removeSlippage(val, slippage))
      .then((val) => setFinalWeth(val));
  }, [account, balance, contracts, strategy, vault.seriesId, slippage]);

  /** The current value of the debt. */
  const [currentDebt, setCurrentDebt] = useState<BigNumber | undefined>();
  useEffect(() => {
    const computeCurrentDebt = async (): Promise<BigNumber> => {
      const pool = await getPool(vault.seriesId, contracts, account);
      const art = await pool.sellFYTokenPreview(balance.art);
      return art;
    };
    setCurrentDebt(undefined);
    void computeCurrentDebt().then((debt) => setCurrentDebt(debt));
  }, [balance.art, account, contracts, vault]);

  const [unwindEnabled, setUnwindEnabled] = useState(false);
  useEffect(() => {
    setUnwindEnabled(finalWeth !== undefined);
  }, [finalWeth]);

  const unwind = async () => {
    if (finalWeth === undefined)
      return; // Not yet ready for unwinding
    if (strategy.lever === YIELD_ST_ETH_LEVER) {
      const lever = getContract(strategy.lever, contracts, account);
      const gasLimit = await lever.estimateGas.unwind(balance.ink, balance.art, finalWeth, vaultId, vault.seriesId);
      const tx = await lever.unwind(balance.ink, balance.art, finalWeth, vaultId, vault.seriesId, { gasLimit });
      await tx.wait();
    }
  };

  return (
    <div className="vault">
      <ValueDisplay
        label="Vault ID:"
        value={vaultId}
        valueType={ValueType.Literal}
      />
      <ValueDisplay
        label="Collateral:"
        valueType={ValueType.WStEth}
        value={balance.ink}
      />
      {currentDebt === undefined ? null : (
        <ValueDisplay
          label="Current debt"
          valueType={ValueType.Weth}
          value={currentDebt}
        />
      )}
      <ValueDisplay
        label="Debt at maturity:"
        valueType={ValueType.Weth}
        value={balance.art}
      />
      <Slippage
        value={slippage}
        onChange={(s) => {
          setSlippage(s);
        }}
      />
      {finalWeth !== undefined ? (
        <ValueDisplay
          label="Final WETH:"
          valueType={ValueType.Weth}
          value={finalWeth}
        />
      ) : null}
      <input
        className="button"
        value="Unwind"
        type="button"
        disabled={!unwindEnabled}
        onClick={() => void unwind()}
      />
    </div>
  );
};
/*xport default class Vault extends React.Component<Properties, State> {
 

  render(): React.ReactNode {
    
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
  }*/
