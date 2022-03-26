import React from 'react';
import './App.css';
import { BigNumber, Contract, ethers } from  'ethers';
import { ConnectWallet } from './components/ConnectWallet';
import erc20Abi from './abi/ERC20.json';
import Invest from './components/Invest';
import yieldLever from './abi/YieldLever.json';
import poolAbi from './abi/Pool.json';

const YIELD_LEVER_CONTRACT_ADDRESS: string = '0xe4e6A1CE0B36CcF0b920b6b57Df0f922915450Ee';

interface State {
  selectedAddress?: string,
  networkError?: string,
  usdcBalance?: BigNumber,
}

export class App extends React.Component {
  public state: State;
  private readonly initialState: State;

  private _provider?: ethers.providers.Web3Provider;

  private pollId?: number;

  private contracts?: Readonly<{
    usdcContract: ethers.Contract;
    yieldLeverContract: ethers.Contract;
    poolContract: ethers.Contract;
  }>;

  constructor(properties: {}) {
    super(properties);
    this.initialState = {
      selectedAddress: undefined,
      usdcBalance: undefined
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
            connectWallet={() => this._connectWallet()} 
            networkError={this.state.networkError}
            dismiss={() => this._dismissNetworkError()}
          />
        );
      }

      if (this.state.usdcBalance === undefined || this.contracts === undefined) {
        return (
          <p>Loading</p>
        );
      }

      return <Invest
        usdcBalance={this.state.usdcBalance}
        usdcContract={this.contracts.usdcContract}
        poolContract={this.contracts.poolContract}
        yieldLeverContract={this.contracts.yieldLeverContract}
        account={this.state.selectedAddress}
      />;
  }

  async _connectWallet() {
    // This method is run when the user clicks the Connect. It connects the
    // dapp to the user's wallet, and initializes it.

    // To connect to the user's wallet, we have to run this method.
    // It returns a promise that will resolve to the user's address.
    const [selectedAddress] = await window.ethereum.request({ method: 'eth_requestAccounts' });

    // Once we have the address, we can initialize the application.

    // First we check the network
    if (!this._checkNetwork()) {
      return;
    }

    this._initialize(selectedAddress);

    // We reinitialize it whenever the user changes their account.
    window.ethereum.on("accountsChanged", ([newAddress]: [string]) => {
      this._stopPollingData();
      // `accountsChanged` event can be triggered with an undefined newAddress.
      // This happens when the user removes the Dapp from the "Connected
      // list of sites allowed access to your addresses" (Metamask > Settings > Connections)
      // To avoid errors, we reset the dapp state 
      if (newAddress === undefined) {
        return this._resetState();
      }
      
      this._initialize(newAddress);
    });
    
    // We reset the dapp state if the network is changed
    window.ethereum.on("chainChanged", ([networkId]: [string]) => {
      this._stopPollingData();
      this._resetState();
    });
  }

  _initialize(userAddress: string) {
    // This method initializes the dapp

    // We first store the user's address in the component's state
    this.setState({
      selectedAddress: userAddress,
    });

    // Then, we initialize ethers, fetch the token's data, and start polling
    // for the user's balance.

    // Fetching the token data and the user's balance are specific to this
    // sample project, but you can reuse the same initialization pattern.
    this._initializeEthers();
    this._startPollingData();
  }

  async _initializeEthers() {
    // We first initialize ethers by creating a provider using window.ethereum
    this._provider = new ethers.providers.Web3Provider(window.ethereum);
    this.contracts = {
      usdcContract: new Contract('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', erc20Abi, this._provider.getSigner(0)),
      yieldLeverContract: new Contract(YIELD_LEVER_CONTRACT_ADDRESS, yieldLever.abi, this._provider.getSigner(0)),
      poolContract: new Contract('0xEf82611C6120185D3BF6e020D1993B49471E7da0', poolAbi, this._provider.getSigner(0))
    };
    await this._startPollingData();
  }

  // This is an utility method that turns an RPC error into a human readable
  // message.
  _getRpcErrorMessage(error: { data?: { message: string }, message: string }) {
    if (error.data) {
      return error.data.message;
    }

    return error.message;
  }

  // This method resets the state
  _resetState() {
    this.setState(this.initialState);
  }

  _checkNetwork() {
    // TODO: Really check network
    return true;
  }

  _dismissNetworkError() {

  }

  private async _startPollingData() {
    this.pollId = setInterval(() => this.pollData(), 1000) as any;
  }


  private async pollData() {
    if (this.contracts !== undefined) {
      const usdcBalance = await this.contracts.usdcContract.balanceOf(this.state.selectedAddress);
      this.setState({
        usdcBalance
      });
    }
  }

  private _stopPollingData() {
    clearInterval(this.pollId);
  }
}

export default App;
