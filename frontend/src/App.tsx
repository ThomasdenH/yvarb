import React, { useMemo, useState } from "react";
import "./App.css";
import { ConnectWallet } from "./components/ConnectWallet";
import { Invest } from "./components/Invest";
import {
  Balance,
  emptyVaults,
  loadVaultsAndStartListening,
  Vault,
  Vaults,
  VaultsAndBalances,
  Balances as VaultBalances,
} from "./objects/Vault";
import { Vault as VaultComponent } from "./components/Vault";
import { Tabs, TabsType } from "./components/Tabs";
import { ValueType } from "./components/ValueDisplay";
import {
  CAULDRON,
  ContractAddress,
  Contracts,
  FyTokenAddress,
  FY_WETH_WETH_POOL,
  getContract,
  YIELD_ST_ETH_LEVER,
} from "./contracts";
import {
  Balances as AddressBalances,
  FY_WETH,
  IERC20Address,
  loadBalance,
  WETH,
} from "./balances";
import { providers, BytesLike } from "ethers";
import { useEffect } from "react";
import { useRef } from "react";
import { MutableRefObject } from "react";

const POLLING_INTERVAL = 5_000;

export interface Strategy {
  tokenAddresses: [IERC20Address, ValueType][];
  debtTokens: [FyTokenAddress, ValueType][];
  investToken: [IERC20Address, ValueType];
  lever: ContractAddress;
  ilkId: BytesLike;
  baseId: BytesLike;
  pool: ContractAddress;
}

enum StrategyName {
  WStEth,
}

const strategies: { [strat in StrategyName]: Strategy } = {
  [StrategyName.WStEth]: {
    tokenAddresses: [[WETH, ValueType.Weth]],
    // TODO: Every series has their own FYWEth...
    debtTokens: [[FY_WETH, ValueType.FyWeth]],
    investToken: [FY_WETH, ValueType.FyWeth],
    lever: YIELD_ST_ETH_LEVER,
    ilkId: "0x303400000000",
    baseId: "0x303000000000",
    pool: FY_WETH_WETH_POOL,
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

  const [selectedStrategy, setSelectedStrategy] = useState<StrategyName>(
    StrategyName.WStEth
  );

  /**
   * These are the ids to monitor. They are obtained through events but might
   * not belong to the user anymore, or maybe not exist.
   */
  const [vaultsToMonitor, setVaultsToMonitor] = useState<string[]>([]);
  // Listen to vault and series updates. This only loads the ids.
  useEffect(() => {
    if (signerAddress !== undefined && selectedAccount !== undefined)
      return loadVaultsAndStartListening(
        contracts,
        signerAddress,
        selectedAccount,
        (vaultId) => {
          console.log(vaultId);
          setVaultsToMonitor([...vaultsToMonitor, vaultId]);
        },
        (a) => {
          console.log(a);
        }
      );
  });

  const [networkError, setNetworkError] = useState<string>();

  const contracts: MutableRefObject<Contracts> = useRef({});

  // When connecting the wallet, the provider will be set. This update in turn
  // will causes an update to the selected account.
  const [provider, setProvider] = useState<providers.Web3Provider>();

  const [chainId, setChainId] = useState<string | undefined>();
  useEthereumListener("chainChanged", setChainId);

  const [signerAddress, setSignerAddress] = useState<string>();
  useEffect(() => {
    if (provider === undefined) {
      setSignerAddress(undefined);
      return;
    }
    // To connect to the user's wallet, we have to run this method.
    // It returns a promise that will resolve to the user's address.
    void provider
      .send("eth_requestAccounts", [])
      // Use the first address
      .then(([selectedAddress]: string[]) => {
        setSignerAddress(selectedAddress);
      });
  }, [provider, chainId]);

  // We reinitialize it whenever the user changes their account.
  useEthereumListener("accountsChanged", ([account]: string[]) => {
    // `accountsChanged` event can be triggered with an undefined newAddress.
    // This happens when the user removes the Dapp from the "Connected
    // list of sites allowed access to your addresses" (Metamask > Settings > Connections)
    // To avoid errors, we reset the dapp state
    if (provider === undefined || account === undefined) {
      setSignerAddress(undefined);
    } else {
      setSignerAddress(account);
    }
  });
  const selectedAccount = useMemo(
    () =>
      provider === undefined || signerAddress === undefined
        ? undefined
        : provider.getSigner(signerAddress),
    [signerAddress, provider]
  );

  const [balances, setBalances] = useState<AddressBalances>({});
  useEffect(() => {
    if (selectedAccount === undefined) return;
    let useResult = true;
    void (async () => {
      const strategy = strategies[selectedStrategy];
      const balances: AddressBalances = {};
      for (const [address] of [
        ...strategy.tokenAddresses,
        ...strategy.debtTokens,
      ])
        balances[address] = await loadBalance(
          address,
          contracts,
          selectedAccount
        );
      if (useResult) setBalances(balances);
    })();
    return () => {
      useResult = false;
    };
  }, [pulse, selectedAccount, selectedStrategy]);

  // Load vaults
  const [vaults, setVaults] = useState<VaultsAndBalances>({
    vaults: {},
    balances: {},
  });
  useEffect(() => {
    if (selectedAccount === undefined) return;
    let useResult = true;
    void (async () => {
      const cauldron = getContract(CAULDRON, contracts, selectedAccount);
      const newVaults = await Promise.all(
        vaultsToMonitor.map((vaultId) =>
          cauldron
            .vaults(vaultId)
            .then((vault) =>
              cauldron
                .balances(vaultId)
                .then((balance): [string, Vault, Balance] => [
                  vaultId,
                  vault,
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
  }, [selectedAccount, signerAddress, vaultsToMonitor]);

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
  if (selectedAccount === undefined) {
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
  const elements: TabsType[] = [
    {
      component: (
        <Invest
          key="invest"
          contracts={contracts}
          account={selectedAccount}
          strategy={strategies[selectedStrategy]}
          balances={balances}
        />
      ),
      label: "Invest",
    },
    ...vaultIds.map((vaultId) => ({
      component: (
        <VaultComponent
          key={vaultId}
          vaultId={vaultId}
          balance={vaults.balances[vaultId]}
          vault={vaults.vaults[vaultId]}
          contracts={contracts}
          // TODO: Use vault strategy instead of currently selected strategy
          strategy={strategies[selectedStrategy]}
          account={selectedAccount}
        />
      ),
      label: `Vault: ${vaultId.substring(0, 8)}...`,
    })),
  ];

  return <Tabs tabs={elements} />;
};
