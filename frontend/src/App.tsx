import React, { useState } from "react";
import "./App.css";
import { ConnectWallet } from "./components/ConnectWallet";
import { Invest } from "./components/Invest";
import {
  Balance,
  emptyVaults,
  loadVaults,
  Vault,
  Vaults,
  VaultsAndBalances,
  Balances as VaultBalances,
} from "./objects/Vault";
// import VaultComponent from "./components/Vault";
import { Tabs } from "./components/Tabs";
import { ValueType } from "./components/ValueDisplay";
import {
  CAULDRON,
  ContractAddress,
  Contracts,
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
import { Signer, providers } from "ethers";
import { useEffect } from "react";

const POLLING_INTERVAL = 20_000;

export interface Strategy {
  tokenAddresses: [IERC20Address, ValueType][];
  debtTokens: [IERC20Address, ValueType][];
  investToken: [IERC20Address, ValueType];
  lever: ContractAddress;
}

enum StrategyName {
  WStEth,
}

const strategies: { [strat in StrategyName]: Strategy } = {
  [StrategyName.WStEth]: {
    tokenAddresses: [[WETH, ValueType.Weth]],
    debtTokens: [[FY_WETH, ValueType.FyWeth]],
    investToken: [FY_WETH, ValueType.FyWeth],
    lever: YIELD_ST_ETH_LEVER,
  },
};

export const App: React.FunctionComponent = () => {
  const [selectedStrategy, setSelectedStrategy] = useState<StrategyName>(
    StrategyName.WStEth
  );

  const [vaultsToMonitor, setVaultsToMonitor] = useState<string[]>([]);

  const [selectedAccount, setSelectedAccount] = useState<Signer>();
  const [vaults, setVaults] = useState<VaultsAndBalances>(emptyVaults());

  const [networkError, setNetworkError] = useState<string | undefined>();

  const contracts: Contracts = {};

  const [balances, setBalances] = useState<AddressBalances>({});

  let provider: providers.Web3Provider | undefined;

  const connectWallet = async () => {
    if (
      window.ethereum.request === undefined ||
      window.ethereum.on === undefined
    )
      throw new Error();

    provider = new providers.Web3Provider(window.ethereum);

    // This method is run when the user clicks the Connect. It connects the
    // dapp to the user's wallet, and initializes it.

    // To connect to the user's wallet, we have to run this method.
    // It returns a promise that will resolve to the user's address.
    const [selectedAddress] = (await window.ethereum.request({
      method: "eth_requestAccounts",
    })) as string[];

    // Once we have the address, we can initialize the application.
    // TODO: Check the network
    const signer = provider.getSigner(selectedAddress);
    setSelectedAccount(provider.getSigner(selectedAddress));

    // We reinitialize it whenever the user changes their account.
    window.ethereum.on("accountsChanged", ([newAddress]: [string]) => {
      // `accountsChanged` event can be triggered with an undefined newAddress.
      // This happens when the user removes the Dapp from the "Connected
      // list of sites allowed access to your addresses" (Metamask > Settings > Connections)
      // To avoid errors, we reset the dapp state
      if (newAddress === undefined) {
        setSelectedAccount(undefined);
      } else {
        setSelectedAccount(window.ethereum.getSigner(newAddress));
      }
    });

    // We reset the dapp state if the network is changed
    window.ethereum.on("chainChanged", () => {
      stopPollingData();
      setSelectedAccount(undefined);
    });

    // Start loading vaults
    void loadVaults(
      contracts,
      signer,
      provider,
      (vaultId) => setVaultsToMonitor([...vaultsToMonitor, vaultId]),
      () => { console.log(); }
    );
  };

  let pollId: number | undefined = undefined;
  const startPollingData = () => {
    pollId = window.setInterval(() => {
      void pollData();
    }, POLLING_INTERVAL);
  };
  const stopPollingData = () => {
    window.clearInterval(pollId);
    pollId = undefined;
  };
  const pollData = async () => {
    if (selectedAccount === undefined) return;
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

    // Poll for vault status
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
  };

  useEffect(() => {
    startPollingData();
    return stopPollingData;
  });

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
        connectWallet={() => void connectWallet()}
        networkError={networkError}
        dismiss={() => setNetworkError(undefined)}
      />
    );
  }

  const vaultIds = Object.keys(vaults.vaults);
  console.log(vaultIds);

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
        pollData={() => void pollData()}
        contracts={contracts}
      />
    )),
  ];

  return <Tabs>{elements}</Tabs>;
};
