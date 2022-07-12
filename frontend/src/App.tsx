import React, { useMemo, useState } from "react";
import "./App.css";
import { ConnectWallet } from "./components/ConnectWallet";
import { Invest } from "./components/Invest";
import {
  Balance,
  loadVaultsAndStartListening,
  Vault,
  VaultsAndBalances,
  loadSeriesAndStartListening,
} from "./objects/Vault";
import { Vault as VaultComponent } from "./components/Vault";
import { Tabs, TabsType } from "./components/Tabs";
import { Token } from "./components/ValueDisplay";
import {
  CAULDRON,
  ContractAddress,
  Contracts,
  getContract,
  WETH,
  YIELD_ST_ETH_LEVER,
} from "./contracts";
import {
  Balances as AddressBalances,
  IERC20Address,
  loadBalance,
  loadFyTokenBalance,
  SeriesId,
} from "./balances";
import { providers, BytesLike } from "ethers";
import { useEffect } from "react";
import { useRef } from "react";
import { MutableRefObject } from "react";
import {
  SeriesAddedEventObject,
  VaultBuiltEventObject,
  VaultGivenEventObject,
} from "./contracts/Cauldron.sol/Cauldron";
import { useAddableList } from "./hooks";

const POLLING_INTERVAL = 5_000;

/**
 * The type of token that is invested for this strategy.
 * -  If the type is `FyToken`, the address is derived from the selected
 *    `seriesId`.
 */
export enum InvestTokenType {
  /** Use the debt token corresponding to the series. */
  FyToken,
}

/**
 * A strategy represents one particular lever to use, although it can contain
 * multiple series with different maturities.
 */
// TODO: Find the best format to be applicable for any strategy while avoiding
//  code duplication.
export interface Strategy {
  /** This is the token that is invested for this strategy. */
  investToken: InvestTokenType;
  /** The token that is obtained after unwinding. */
  outToken: [IERC20Address, Token | AssetId];
  lever: ContractAddress;
  ilkId: BytesLike;
  baseId: BytesLike;
}

enum StrategyName {
  WStEth,
}

export enum AssetId {
  WEth = "0x303000000000",
  WStEth = "0x303400000000",
  Usdc = "0x303200000000"
}

/**
 * Get the concrete invest token type from a series. I.e. get `FyWEth` instead
 * of `FyToken`.
 */
export const getInvestToken = ({investToken, baseId}: Strategy): Token | AssetId => {
  if (investToken === InvestTokenType.FyToken) {
    switch (baseId) {
      case AssetId.WEth:
        return Token.FyWeth;        
    }
  }
  throw new Error('Unimplemented');
}

const strategies: { [strat in StrategyName]: Strategy } = {
  [StrategyName.WStEth]: {
    investToken: InvestTokenType.FyToken,
    outToken: [WETH, AssetId.WEth],
    lever: YIELD_ST_ETH_LEVER,
    ilkId: AssetId.WStEth,
    baseId: AssetId.WEth,
  },
};

/**
 * Subscribe and unsubscribe to an event.
 * @param event Event, must be global constant as it does not listen to
 *  updates.
 * @param fn fn,  must be global constant as it does not listen to updates.
 */
const useEthereumListener = (event: string, fn: providers.Listener) => {
  useEffect(() => {
    window.ethereum.on(event, fn);
    return () => {
      window.ethereum.removeListener(event, fn);
    };
    // Event must be constant
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
};

export const App: React.FunctionComponent = () => {
  /**
   * This pulse will update in an interval. Subscribe to it to update effects
   * periodically.
   */
  const [pulse, setPulse] = useState(0);
  useEffect(() => {
    const pollId = setInterval(() => setPulse((c) => c + 1), POLLING_INTERVAL);
    return () => clearInterval(pollId);
  });

  /**
   * The currently selected strategy. Static, for the time being.
   */
  const selectedStrategy = StrategyName.WStEth;

  const [networkError, setNetworkError] = useState<string>();

  const contracts: MutableRefObject<Contracts> = useRef({});

  // When connecting the wallet, the provider will be set. This update in turn
  // will causes an update to the selected account.
  const [provider, setProvider] = useState<providers.Web3Provider>();

  const [chainId, setChainId] = useState<string | undefined>();
  useEthereumListener("chainChanged", setChainId);

  /**
   * The currently connected address.
   */
  const [address, setAddress] = useState<string>();
  useEffect(() => {
    if (provider === undefined) {
      setAddress(undefined);
      return;
    }
    // To connect to the user's wallet, we have to run this method.
    // It returns a promise that will resolve to the user's address.
    void provider
      .send("eth_requestAccounts", [])
      // Use the first address
      .then(([selectedAddress]: string[]) => {
        setAddress(selectedAddress);
      });
  }, [provider, chainId]);

  // We reinitialize it whenever the user changes their account.
  useEthereumListener("accountsChanged", ([account]: string[]) => {
    // `accountsChanged` event can be triggered with an undefined newAddress.
    // This happens when the user removes the Dapp from the "Connected
    // list of sites allowed access to your addresses" (Metamask > Settings > Connections)
    // To avoid errors, we reset the dapp state
    if (provider === undefined || account === undefined) {
      setAddress(undefined);
    } else {
      setAddress(account);
    }
  });
  const signer = useMemo(
    () =>
      provider === undefined || address === undefined
        ? undefined
        : provider.getSigner(address),
    [address, provider]
  );

  /** Load the series. */
  const [series, addSeries] = useAddableList<
    SeriesAddedEventObject & { seriesId: SeriesId }
  >((a, b) => a.seriesId === b.seriesId);
  useEffect(() => {
    if (signer !== undefined)
      return loadSeriesAndStartListening(contracts, signer, (newSeries) => {
        addSeries(newSeries as SeriesAddedEventObject & { seriesId: SeriesId });
      });
  }, [addSeries, signer]);

  /**
   * These are the ids to monitor. They are obtained through events but might
   * not belong to the user anymore, or maybe not exist.
   */
  const [vaultsToMonitor, addVaultToMonitor] = useAddableList<string>();
  // Listen to vault and series updates. This only loads the ids.
  useEffect(() => {
    if (address !== undefined && signer !== undefined && provider !== undefined)
      return loadVaultsAndStartListening(
        contracts,
        address,
        signer,
        provider,
        (event: VaultBuiltEventObject | VaultGivenEventObject) => {
          addVaultToMonitor(event.vaultId);
        }
      );
  }, [provider, signer, address, addVaultToMonitor]);

  /**
   * Balances for the different tokens in the app. Could easily be loaded
   * dependent on the strategy if necessary for performance.
   */
  const [balances, setBalances] = useState<AddressBalances>({});
  useEffect(() => {
    if (signer === undefined) return;
    let useResult = true;
    void (async () => {
      const strategy = strategies[selectedStrategy];
      const balances: AddressBalances = {};
      for (const [address] of [strategy.outToken])
        balances[address] = await loadBalance(address, contracts, signer);
      for (const { seriesId } of series) {
        balances[seriesId] = await loadFyTokenBalance(
          seriesId,
          contracts,
          signer
        );
      }
      if (useResult) setBalances(balances);
    })();
    return () => {
      useResult = false;
    };
  }, [pulse, signer, selectedStrategy, series]);

  // Load vaults
  const [vaults, setVaults] = useState<VaultsAndBalances>({
    vaults: {},
    balances: {},
  });
  useEffect(() => {
    if (signer === undefined) return;
    let useResult = true;
    void (async () => {
      const cauldron = getContract(CAULDRON, contracts, signer);
      const newVaults = await Promise.all(
        vaultsToMonitor.map((vaultId) =>
          cauldron
            .vaults(vaultId)
            .then((vault) =>
              cauldron
                .balances(vaultId)
                .then((balance): [string, Vault, Balance] => [
                  vaultId,
                  { ...vault, seriesId: vault.seriesId as SeriesId },
                  balance,
                ])
            )
        )
      );
      const newVaultsObj: VaultsAndBalances = { vaults: {}, balances: {} };
      for (const [vaultId, vault, balance] of newVaults) {
        newVaultsObj.vaults[vaultId] = vault;
        newVaultsObj.balances[vaultId] = balance;
      }
      if (useResult) setVaults(newVaultsObj);
    })();
    return () => {
      useResult = false;
    };
  }, [signer, address, vaultsToMonitor]);

  // Ethereum wallets inject the window.ethereum object. If it hasn't been
  // injected, we instruct the user to install MetaMask.
  if (window.ethereum === undefined) {
    return <p>No wallet detected.</p>;
  }

  // The next thing we need to do, is to ask the user to connect their wallet.
  // When the wallet gets connected, we are going to save the users's address
  // in the component's state. So, if it hasn't been saved yet, we have
  // to show the ConnectWallet component.
  //
  // Note that we pass it a callback that is going to be called when the user
  // clicks a button. This callback just calls the _connectWallet method.
  if (signer === undefined) {
    return (
      <ConnectWallet
        connectWallet={() =>
          setProvider(new providers.Web3Provider(window.ethereum))
        }
        networkError={networkError}
        dismiss={() => setNetworkError(undefined)}
      />
    );
  }

  const vaultIds = Object.keys(vaults.balances);
  const strategy = strategies[selectedStrategy];
  const seriesForThisStrategy = series.filter(
    (s) => s.baseId === strategy.baseId
  );
  const elements: TabsType[] = [
    {
      component: (
        <Invest
          contracts={contracts}
          account={signer}
          strategy={strategies[selectedStrategy]}
          balances={balances}
          series={seriesForThisStrategy}
        />
      ),
      label: "Invest",
    },
    ...vaultIds.map((vaultId) => ({
      component: (
        <VaultComponent
          vaultId={vaultId}
          balance={vaults.balances[vaultId]}
          vault={vaults.vaults[vaultId]}
          contracts={contracts}
          // TODO: Use vault strategy instead of currently selected strategy
          strategy={strategies[selectedStrategy]}
          account={signer}
        />
      ),
      label: `Vault: ${vaultId.substring(0, 8)}...`,
    })),
  ];

  return <Tabs tabs={elements} />;
};
