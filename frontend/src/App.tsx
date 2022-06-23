import React, { useState } from 'react';
import "./App.css";
import { Contract, ethers } from "ethers";
import { ConnectWallet } from "./components/ConnectWallet";
import {Invest} from "./components/Invest";
import {
  emptyVaults,
  VaultsAndBalances,
} from "./objects/Vault";
// import VaultComponent from "./components/Vault";
import { Tabs } from "./components/Tabs";
import { ExternalProvider } from "@ethersproject/providers";

export interface Strategy {
  tokenAddresses: string[];
  debtTokens: string[];
  lever: string;
}

enum StrategyName {
  WSTETH = 'wstEth'
}

const strategies: { [strat: StrategyName]: Strategy; } = {
  [StrategyName.WSTETH]: {
    tokenAddresses: [
      '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', // WEth
    ],
    debtTokens: [
      '0x53358d088d835399F1E97D2a01d79fC925c7D999' // fyWeth
    ],
    lever: '0x'
  }
};

const CAULDRON_CONTRACT = "0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867";
const LADLE_CONTRACT = "0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A";

type YearnApiJson = { address: string; apy: { net_apy: number } }[];

interface State {
  selectedAddress?: string;
  networkError?: string;
  vaults: VaultsAndBalances;
}

export interface Contracts {
  [address: string]: Promise<Contract>;
}

export const App: React.FunctionComponent = () => {
  const [selectedStrategy, setSelectedStrategy] = useState<StrategyName>(StrategyName.WSTETH);
  const [provider, setProvider] = useState<ethers.providers.Web3Provider | undefined>();

  const [selectedAddress, setSelectedAddress] = useState<string>();
  const [vaults, setVaults] = useState<VaultsAndBalances>(emptyVaults());

  const [networkError, setNetworkError] = useState<string | undefined>();

  const contracts: Contracts = Object.create(null) as Contracts;

  const connectWallet = async () => {
    // This method is run when the user clicks the Connect. It connects the
    // dapp to the user's wallet, and initializes it.

    // To connect to the user's wallet, we have to run this method.
    // It returns a promise that will resolve to the user's address.
    const [selectedAddress] = await (
      window.ethereum as { request(arg: { method: string }): Promise<[string]> }
    ).request({
      method: "eth_requestAccounts",
    });

    // Once we have the address, we can initialize the application.
    // TODO: Check the network

    initialize(selectedAddress);

    // We reinitialize it whenever the user changes their account.
    (
      window.ethereum as {
        on(method: string, callback: (a: any) => void): void;
      }
    ).on("accountsChanged", ([newAddress]: [string]) => {
      stopPollingData();
      // `accountsChanged` event can be triggered with an undefined newAddress.
      // This happens when the user removes the Dapp from the "Connected
      // list of sites allowed access to your addresses" (Metamask > Settings > Connections)
      // To avoid errors, we reset the dapp state
      if (newAddress === undefined) {
        // TODO return this.resetState();
        return;
      } else {
        initialize(newAddress);
      }
    });

    // We reset the dapp state if the network is changed
    (
      window.ethereum as {
        on(method: string, callback: (a: any) => void): void;
      }
    ).on("chainChanged", ([_networkId]: [string]) => {
      stopPollingData();
      // TODO
      // this.resetState();
    });
  };

  const initializeEthers = () => {
    setProvider(new ethers.providers.Web3Provider(
      window.ethereum as any as ExternalProvider,
      "any"
    ));
  };

  const initialize = (userAddress: string) => {
      // This method initializes the dapp
  
      // We first store the user's address in the component's state
      setSelectedAddress(userAddress);
  
      // Then, we initialize ethers, fetch the token's data, and start polling
      // for the user's balance.
  
      // Fetching the token data and the user's balance are specific to this
      // sample project, but you can reuse the same initialization pattern.
      initializeEthers();
      void startPollingData();
  };

  let pollId: number | undefined = undefined;
  const startPollingData = () => {
    pollId = setInterval(
      pollData,
      1000
    ) as any as number;
  };
  const stopPollingData = () => {
    clearInterval(pollId);
    pollId = undefined;
  };

  /** Poll data that might be updated externally. */
  const pollData = () => {

  };

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
  if (selectedAddress === undefined) {
    return (
      <ConnectWallet
        connectWallet={() => void connectWallet()}
        networkError={networkError}
        dismiss={() => setNetworkError(undefined)}
      />
    );
  }

  const vaultIds = Object.keys(vaults.vaults);

  const elements = [
    <Invest
      key="invest"
      label="Invest"
      usdcBalance={this.state.usdcBalance}
      contracts={this.contracts}
      account={this.state.selectedAddress}
      yearnApi={this.state.yearn_apy}
      seriesDefinitions={this.state.series}
      seriesInfo={this.state.seriesInfo}
    />
    /*...vaultIds.map((vaultId) => (
      <VaultComponent
        key={vaultId}
        label={"Vault: " + vaultId.substring(0, 8) + "..."}
        vaultId={vaultId}
        balance={this.state.vaults.balances[vaultId]}
        vault={this.state.vaults.vaults[vaultId]}
        pollData={() => this.pollData()}
        contracts={contracts}
      />
    )),*/
  ];

  return <Tabs>{elements}</Tabs>;
};
