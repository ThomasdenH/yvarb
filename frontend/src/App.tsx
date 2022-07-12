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
import { CAULDRON, Contracts, getContract } from "./contracts";
import {
  Balances as AddressBalances,
  loadBalance,
  loadFyTokenBalance,
  SeriesId,
} from "./balances";
import { providers } from "ethers";
import { useEffect } from "react";
import { useRef } from "react";
import { MutableRefObject } from "react";
import {
  SeriesAddedEventObject,
  VaultBuiltEventObject,
  VaultGivenEventObject,
} from "./contracts/Cauldron.sol/Cauldron";
import { useAddableList, useEthereumListener, useInvalidator } from "./hooks";
import { STRATEGIES, StrategyName } from "./objects/Strategy";

const POLLING_INTERVAL = 5_000;

export const App: React.FunctionComponent = () => {
  /**
   * This pulse will update in an interval. Subscribe to it to update effects
   * periodically.
   */
  const [pulse, setPulse] = useInvalidator();
  useEffect(() => {
    const pollId = setInterval(() => setPulse(), POLLING_INTERVAL);
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
   * The currently connected address. Will be set asynchronous instead of
   * directly obtaining the provider as it requires awaiting an RPC request.
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
    if (provider === undefined || account === undefined) {
      setAddress(undefined);
    } else {
      setAddress(account);
    }
  });
  /**
   * The signer can be easily created from the address. We wrap it in a memo to
   * avoid unnecessary updates.
   */
  const signer = useMemo(
    () =>
      provider === undefined || address === undefined
        ? undefined
        : provider.getSigner(address),
    [address, provider]
  );

  /**
   * Load the series. This will do two things: start loading historical events
   * for series creation, and listen for new series that are created.
   */
  const [series, addSeries] = useAddableList<
    SeriesAddedEventObject & { seriesId: SeriesId }
  >((a, b) => a.seriesId === b.seriesId);
  useEffect(() => {
    if (signer !== undefined && provider !== undefined)
      return loadSeriesAndStartListening(
        contracts,
        signer,
        provider,
        (newSeries) => {
          addSeries(
            newSeries as SeriesAddedEventObject & { seriesId: SeriesId }
          );
        },
        STRATEGIES[selectedStrategy].baseId
      );
  }, [addSeries, signer, provider, selectedStrategy]);

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
      const strategy = STRATEGIES[selectedStrategy];
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
  const [vaultInvalidator, invalidateVaults] = useInvalidator();
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
  }, [signer, address, vaultsToMonitor, pulse, vaultInvalidator]);

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
  const strategy = STRATEGIES[selectedStrategy];
  const seriesForThisStrategy = series.filter(
    (s) => s.baseId === strategy.baseId
  );
  const elements: TabsType[] = [
    {
      component: (
        <Invest
          contracts={contracts}
          account={signer}
          strategy={STRATEGIES[selectedStrategy]}
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
          strategy={STRATEGIES[selectedStrategy]}
          account={signer}
          invalidateVaults={invalidateVaults}
        />
      ),
      label: `Vault: ${vaultId.substring(0, 8)}...`,
    })),
  ];

  return <Tabs tabs={elements} />;
};
