import { BigNumber, Signer } from "ethers";
import React, { useEffect, useState } from "react";
import { MutableRefObject } from "react";
import { AssetId, Strategy } from "../App";
import {
  CAULDRON,
  Contracts,
  getContract,
  getFyToken,
  getPool,
  WETH,
  WETH_JOIN,
  WETH_ST_ETH_STABLESWAP,
  WST_ETH,
  YIELD_ST_ETH_LEVER,
} from "../contracts";
import { Balance, Vault as VaultI } from "../objects/Vault";
import { Slippage, removeSlippage, useSlippage } from "./Slippage";
import { ValueDisplay, ValueType } from "./ValueDisplay";
import "./Vault.scss";

interface Properties {
  vaultId: string;
  balance: Balance;
  vault: VaultI;
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
  /** The slippage will be subtracted from the expected final weth balance. */
  const [slippage, setSlippage] = useSlippage();

  /** How much weth we'll obtain, at a minimum. Includes slippage. */
  const [finalWeth, setFinalWeth] = useState<BigNumber | undefined>();
  useEffect(() => {
    if (balance.ink.eq(0)) {
      setFinalWeth(BigNumber.from(0));
      return;
    }
    let useResult = true;
    /**
     * Compute how much WEth the user has at the end of the operation.
     */
    const computeResultWeth = async () => {
      const fyToken = await getFyToken(vault.seriesId, contracts, account);
      const maturity = await fyToken.maturity();
      const blockNumber = (await account.provider?.getBlockNumber()) as number;
      const blockTime = (await account.provider?.getBlock(blockNumber))
        ?.timestamp as number;
      const wStEth = getContract(WST_ETH, contracts, account);
      const stableSwap = getContract(
        WETH_ST_ETH_STABLESWAP,
        contracts,
        account
      );
      if (BigNumber.from(blockTime).lt(maturity)) {
        // Repay!
        // Basically rerun the entire process and see how much we end up with.
        const stEthUnwrapped = await wStEth.getStETHByWstETH(balance.ink);
        const wethReceived = await stableSwap.get_dy(1, 0, stEthUnwrapped);
        const fee = await fyToken.flashFee(fyToken.address, balance.art);
        const borrowAmountPlusFee = fee.add(balance.art);
        const pool = await getPool(vault.seriesId, contracts, account);
        const wethToTran = await pool.buyFYTokenPreview(borrowAmountPlusFee);
        const wethRemaining = wethReceived.sub(wethToTran);
        return wethRemaining;
      } else {
        // Past maturity, we close.
        const cauldron = getContract(CAULDRON, contracts, account);
        // `debtToBase` is not view, so we need to compute it ourselves
        const rateAtMaturity = await cauldron.ratesAtMaturity(vault.seriesId);

        const base = BigNumber.from(0);

        const stEthUnwrapped = await wStEth.getStETHByWstETH(balance.ink);
        const weth = await stableSwap.get_dy(1, 0, stEthUnwrapped);
        const wethJoin = getContract(WETH_JOIN, contracts, account);
        const fee = await wethJoin.flashFee(WETH, base);
        return weth.sub(base).sub(fee);
      }
    };
    setFinalWeth(undefined);
    void computeResultWeth()
      .then((val) => removeSlippage(val, slippage))
      .then((val) => {
        if (useResult) setFinalWeth(val);
      });
    return () => {
      useResult = false;
    };
  }, [account, balance, contracts, strategy, vault.seriesId, slippage]);

  /** The current value of the debt. */
  const [currentDebt, setCurrentDebt] = useState<BigNumber | undefined>();
  useEffect(() => {
    let useResult = true;
    const computeCurrentDebt = async (): Promise<BigNumber> => {
      const pool = await getPool(vault.seriesId, contracts, account);
      const art = await pool.sellFYTokenPreview(balance.art);
      return art;
    };
    setCurrentDebt(undefined);
    void computeCurrentDebt().then((debt) => {
      if (useResult) setCurrentDebt(debt);
    });
    return () => {
      useResult = false;
    };
  }, [balance.art, account, contracts, vault]);

  /** Disable unwinding when loading or when empty. */
  const unwindEnabled = finalWeth !== undefined && !balance.ink.eq(0);

  const unwind = async () => {
    if (finalWeth === undefined) return; // Not yet ready for unwinding
    if (strategy.lever === YIELD_ST_ETH_LEVER) {
      const lever = getContract(strategy.lever, contracts, account);
      const gasLimit = await lever.estimateGas.unwind(
        balance.ink,
        balance.art,
        finalWeth,
        vaultId,
        vault.seriesId
      );
      const tx = await lever.unwind(
        balance.ink,
        balance.art,
        finalWeth,
        vaultId,
        vault.seriesId,
        { gasLimit }
      );
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
        valueType={ValueType.Balance}
        token={AssetId.WStEth}
        value={balance.ink}
      />
      {currentDebt === undefined ? null : (
        <ValueDisplay
          label="Current debt"
          valueType={ValueType.Balance}
          token={AssetId.WEth}
          value={currentDebt}
        />
      )}
      <ValueDisplay
        label="Debt at maturity:"
        valueType={ValueType.Balance}
        token={AssetId.WEth}
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
          valueType={ValueType.Balance}
          token={AssetId.WEth}
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
