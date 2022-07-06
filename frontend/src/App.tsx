import React, { useState } from "react";
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
import { Tabs } from "./components/Tabs";
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
import { Signer, providers, BytesLike } from "ethers";
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
    return clearInterval(pollId);
  })

  const [selectedStrategy, setSelectedStrategy] = useState<StrategyName>(
    StrategyName.WStEth
  );

  const [vaultsToMonitor, setVaultsToMonitor] = useState<string[]>([]);

  const [vaults, setVaults] = useState<VaultsAndBalances>(emptyVaults());

  const [networkError, setNetworkError] = useState<string>();

  const contracts: MutableRefObject<Contracts> = useRef({});

  const [balances, setBalances] = useState<AddressBalances>({});

  // When connecting the wallet, the provider will be set. This update in turn
  // will causes an update to the selected account.
  const [provider, setProvider] = useState<providers.Web3Provider>();

  const [chainId, setChainId] = useState<string | undefined>();
  useEthereumListener("chainChanged", setChainId);

  const [signerAddress, setSignerAddress] = useState<string>();
  const [selectedAccount, setSelectedAccount] = useState<Signer>();
  useEffect(() => {
    if (provider === undefined) {
      setSignerAddress(undefined);
    } else {
      // To connect to the user's wallet, we have to run this method.
      // It returns a promise that will resolve to the user's address.
      void provider
        .send("eth_requestAccounts", [])
        // Use the first address
        .then(([selectedAddress]: string[]) => {
          setSignerAddress(selectedAddress);
          setSelectedAccount(provider.getSigner(selectedAddress));
        });
    }
  }, [provider, chainId]);

  // We reinitialize it whenever the user changes their account.
  // TODO: Handle case without provider (No window.ethereum)

  useEthereumListener("accountsChanged", ([account]: string[]) => {
    // `accountsChanged` event can be triggered with an undefined newAddress.
    // This happens when the user removes the Dapp from the "Connected
    // list of sites allowed access to your addresses" (Metamask > Settings > Connections)
    // To avoid errors, we reset the dapp state
    if (provider === undefined || account === undefined) {
      setSelectedAccount(undefined);
    } else {
      setSelectedAccount(provider.getSigner(account));
    }
  });

  // Listen to vault and series updates. This only loads the ids.
  useEffect(() => {
    if (signerAddress !== undefined && selectedAccount !== undefined)
      return loadVaultsAndStartListening(
        contracts,
        signerAddress,
        selectedAccount,
        (vaultId) => setVaultsToMonitor([...vaultsToMonitor, vaultId]),
        (a) => {
          console.log(a);
        }
      );
  });

  // Load balances
  useEffect(() => {
    if (selectedAccount === undefined)
      return;
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
      setBalances(balances);
    })();
  }, [pulse, selectedAccount, selectedStrategy]);

  // Load vaults
  useEffect(() => {
    if (selectedAccount === undefined)
      return;
    void (async () => {
      const cauldron = getContract(CAULDRON, contracts, selectedAccount);
      const address = await selectedAccount.getAddress();
      const vaults: Vaults = {};
      const vaultbalances: VaultBalances = {};
      (
        await Promise.all(
          vaultsToMonitor.map((vaultId) =>
            cauldron
              .vaults(vaultId)
              .then((vault): [string, Vault] => [vaultId, vault])
              .then(([vaultId, vault]) =>
                cauldron
                  .balances(vaultId)
                  .then((balance): [string, Vault, Balance] => [
                    vaultId,
                    vault,
                    balance,
                  ])
              )
          )
        )
      )
        .filter(([, vault]) => vault.owner === address)
        .forEach(([vaultId, vault, balance]) => {
          vaults[vaultId] = vault;
          vaultbalances[vaultId] = balance;
        });
      setVaults({ vaults, balances: vaultbalances });
    })();
  }, [selectedAccount, vaultsToMonitor]);

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

  const vaultIds = Object.keys(vaults.vaults);
  const elements = [
    <Invest
      label="Invest"
      key="invest"
      contracts={contracts}
      account={selectedAccount}
      strategy={strategies[selectedStrategy]}
      balances={balances}
    />,
    ...vaultIds.map((vaultId) => (
      <VaultComponent
        key={vaultId}
        label={"Vault: " + vaultId.substring(0, 8) + "..."}
        vaultId={vaultId}
        balance={vaults.balances[vaultId]}
        vault={vaults.vaults[vaultId]}
        contracts={contracts}
        // TODO: Use vault strategy
        strategy={strategies[selectedStrategy]}
        account={selectedAccount}
      />
    )),
  ];

  return <Tabs>{elements}</Tabs>;
};
