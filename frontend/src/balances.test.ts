/**
 * @jest-environment node
 */

import { loadBalance } from "./balances";
import * as ganache from "ganache";
import { ethers, Signer } from "ethers";
import { ExternalProvider } from "@ethersproject/providers";
import { WETH } from "./contracts";

describe("balances", () => {
  const contracts = { current: {} };
  let ganacheProvider: ganache.EthereumProvider;
  let signer: Signer;

  beforeEach(() => {
    ganacheProvider = ganache.provider({
      logging: { quiet: true },
      fork: { network: "mainnet" },
    });
    const provider = new ethers.providers.Web3Provider(
      ganacheProvider as unknown as ExternalProvider
    );
    signer = provider.getSigner();
  });

  afterEach(async () => {
    await ganacheProvider.disconnect();
  });

  it("should load balances without errors", async () => {
    await loadBalance(WETH, contracts, signer);
  });
});
