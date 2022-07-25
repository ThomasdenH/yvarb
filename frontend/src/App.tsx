import React from "react";
import "./App.css";
import { BigNumber, ethers } from "ethers";
import { ConnectWallet } from "./components/ConnectWallet";
import erc20Abi from "./abi/ERC20.json";
import Invest from "./components/Invest";
import poolAbi from "./abi/Pool.json";
import cauldronAbi from "./abi/Cauldron.json";
import ladleAbi from "./abi/Ladle.json";
import {
  Balances,
  emptyVaults,
  loadVaults,
  SeriesDefinition,
  Vaults,
  VaultsAndBalances,
} from "./objects/Vault";
import VaultComponent from "./components/Vault";
import { Tabs } from "./components/Tabs";
import { ContractContext as ERC20 } from "./abi/ERC20";
import { ContractContext as YieldLever } from "./generated/abi/YieldLever";
import { ContractContext as Pool } from "./abi/Pool";
import { ContractContext as Cauldron } from "./abi/Cauldron";
import { ContractContext as Ladle } from "./abi/Ladle";
import yieldLeverAbi from "./generated/abi/YieldLever.json";
import yieldLeverDeployed from "./generated/deployment.json";
import { ExternalProvider } from "@ethersproject/providers";
import { SeriesResponse as Series } from "./abi/Cauldron";

const YIELD_LEVER_CONTRACT_ADDRESS: string = yieldLeverDeployed.deployedTo;
const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const CAULDRON_CONTRACT = "0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867";
const LADLE_CONTRACT = "0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A";

const YEARN_STRATEGY = "0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE";

export const ILK_ID = "0x303900000000";

type YearnApiJson = { address: string; apy: { net_apy: number } }[];

interface State {
  selectedAddress?: string;
  networkError?: string;
  usdcBalance?: BigNumber;
  vaults: VaultsAndBalances;
  yearn_apy?: number;
  series: SeriesDefinition[];
  seriesInfo: { [seriesId: string]: Series };
}

export interface Contracts {
  usdcContract: ERC20;
  yieldLeverContract: YieldLever;
  poolContracts: { [poolAddress: string]: Pool };
  cauldronContract: Cauldron;
  ladleContract: Ladle;
}

export class App extends React.Component<Record<string, never>, State> {
  private readonly initialState: State;

  private _provider?: ethers.providers.Web3Provider;

  private pollId?: number;

  private contracts?: Contracts;

  private vaultsToMonitor: string[] = [];

  constructor(properties: Record<string, never>) {
    super(properties);
    this.initialState = {
      selectedAddress: undefined,
      usdcBalance: undefined,
      vaults: emptyVaults(),
      series: [],
      seriesInfo: {},
    };
    this.state = this.initialState;
  }

  render() {
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
    if (!this.state.selectedAddress) {
      return (
        <ConnectWallet
          connectWallet={() => void this.connectWallet()}
          networkError={this.state.networkError}
          dismiss={() => this.dismissNetworkError()}
        />
      );
    }

    if (this.state.usdcBalance === undefined || this.contracts === undefined) {
      return <p>Loading</p>;
    }

    const contracts = this.contracts;

    const vaultIds = Object.keys(this.state.vaults.vaults);

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
      />,
      ...vaultIds.map((vaultId) => (
        <VaultComponent
          key={vaultId}
          label={"Vault: " + vaultId.substring(0, 8) + "..."}
          vaultId={vaultId}
          balance={this.state.vaults.balances[vaultId]}
          vault={this.state.vaults.vaults[vaultId]}
          pollData={() => this.pollData()}
          contracts={contracts}
        />
      )),
    ];

    return <Tabs>{elements}</Tabs>;
  }
  dismissNetworkError(): void {
    throw new Error("Method not implemented.");
  }

  private async connectWallet() {
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

    // First we check the network
    if (!this.checkNetwork()) {
      return;
    }

    this.initialize(selectedAddress);

    // We reinitialize it whenever the user changes their account.
    (
      window.ethereum as {
        on(method: string, callback: (a: any) => void): void;
      }
    ).on("accountsChanged", ([newAddress]: [string]) => {
      this.stopPollingData();
      // `accountsChanged` event can be triggered with an undefined newAddress.
      // This happens when the user removes the Dapp from the "Connected
      // list of sites allowed access to your addresses" (Metamask > Settings > Connections)
      // To avoid errors, we reset the dapp state
      if (newAddress === undefined) {
        return this.resetState();
      }

      this.initialize(newAddress);
    });

    // We reset the dapp state if the network is changed
    (
      window.ethereum as {
        on(method: string, callback: (a: any) => void): void;
      }
    ).on("chainChanged", ([_networkId]: [string]) => {
      this.stopPollingData();
      this.resetState();
    });
  }

  private initialize(userAddress: string) {
    // This method initializes the dapp

    // We first store the user's address in the component's state
    this.setState({
      selectedAddress: userAddress,
    });

    // Then, we initialize ethers, fetch the token's data, and start polling
    // for the user's balance.

    // Fetching the token data and the user's balance are specific to this
    // sample project, but you can reuse the same initialization pattern.
    void this.initializeEthers();
    void this.startPollingData();
  }

  private initializeEthers() {
    // We first initialize ethers by creating a provider using window.ethereum
    this._provider = new ethers.providers.Web3Provider(
      window.ethereum as any as ExternalProvider,
      "any"
    );
    this.contracts = {
      usdcContract: new ethers.Contract(
        USDC_ADDRESS,
        erc20Abi,
        this._provider.getSigner(0)
      ) as any as ERC20,
      yieldLeverContract: new ethers.Contract(
        YIELD_LEVER_CONTRACT_ADDRESS,
        yieldLeverAbi.abi,
        this._provider.getSigner(0)
      ) as any as YieldLever,
      poolContracts: Object.create(null) as { [poolAddress: string]: Pool },
      cauldronContract: new ethers.Contract(
        CAULDRON_CONTRACT,
        cauldronAbi,
        this._provider
      ) as any as Cauldron,
      ladleContract: new ethers.Contract(
        LADLE_CONTRACT,
        ladleAbi,
        this._provider
      ) as any as Ladle,
    };

    if (this.state.selectedAddress !== undefined)
      void loadVaults(
        this.contracts.cauldronContract,
        this.state.selectedAddress,
        this._provider,
        (vaultId) => void this.addVault(vaultId),
        (series) => void this.addSeries(series)
      );

    const vaultsBuiltFilter =
      this.contracts.cauldronContract.filters.VaultBuilt(
        null,
        this.state.selectedAddress,
        null
      );
    const vaultsReceivedFilter =
      this.contracts.cauldronContract.filters.VaultGiven(
        null,
        this.state.selectedAddress
      );
    this.contracts.cauldronContract.on(
      vaultsBuiltFilter,
      (vaultId: string) => void this.addVault(vaultId)
    );
    this.contracts.cauldronContract.on(
      vaultsReceivedFilter,
      (vaultId: string) => void this.addVault(vaultId)
    );

    this.startPollingData();
  }

  // This is an utility method that turns an RPC error into a human readable
  // message.
  getRpcErrorMessage(error: { data?: { message: string }; message: string }) {
    if (error.data) {
      return error.data.message;
    }

    return error.message;
  }

  private async addSeries(series: SeriesDefinition) {
    if (this.contracts === undefined || this._provider === undefined)
      throw new Error("Race condition");
    const seriesInfo = await this.contracts.cauldronContract.series(
      series.seriesId
    );
    this.contracts.poolContracts[series.seriesId] = new ethers.Contract(
      series.poolAddress,
      poolAbi,
      this._provider.getSigner(0)
    ) as any as Pool;
    this.setState({
      series: [...this.state.series, series],
      seriesInfo: { ...this.state.seriesInfo, [series.seriesId]: seriesInfo },
    });
  }

  // This method resets the state
  resetState() {
    this.setState(this.initialState);
  }

  checkNetwork() {
    // TODO: Really check network
    return true;
  }

  private startPollingData() {
    this.pollId = setInterval(
      () => void this.pollData(),
      1000
    ) as any as number;
  }

  private async pollData() {
    if (
      this.contracts !== undefined &&
      this._provider !== undefined &&
      this.state.selectedAddress !== undefined
    ) {
      const { cauldronContract } = this.contracts;
      const [usdcBalance, ...vaultAndBalances] = await Promise.all([
        this.contracts.usdcContract.balanceOf(this.state.selectedAddress),
        ...this.vaultsToMonitor.map((vaultId: string) =>
          Promise.all([
            cauldronContract.vaults(vaultId),
            cauldronContract.balances(vaultId),
          ])
        ),
      ]);
      const vaults = Object.create(null) as Vaults;
      const balances = Object.create(null) as Balances;
      this.vaultsToMonitor.forEach((vaultId, i) => {
        if (vaultAndBalances[i] !== undefined) {
          vaults[vaultId] = vaultAndBalances[i][0];
          balances[vaultId] = vaultAndBalances[i][1];
        }
      });

      const yearnResponse = await fetch(
        "https://api.yearn.finance/v1/chains/1/vaults/all"
      );
      const yearnStrategies = (await yearnResponse.json()) as YearnApiJson;
      const strategy = yearnStrategies.find(
        (strat) => strat.address === YEARN_STRATEGY
      );
      const yearn_apy = strategy?.apy.net_apy;

      this.setState({
        usdcBalance,
        vaults: {
          vaults,
          balances,
        },
        yearn_apy,
      });
    }
  }

  private stopPollingData() {
    clearInterval(this.pollId);
  }

  private async addVault(vaultId: string) {
    if (!this.vaultsToMonitor.includes(vaultId))
      this.vaultsToMonitor.push(vaultId);
    await this.pollData();
  }
}

export default App;
