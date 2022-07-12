// Polyfill setImmediate
import "core-js/modules/web.immediate";
import "@testing-library/jest-dom";
import * as ganache from "ganache";
import { ExternalProvider } from "@ethersproject/providers";
import { App } from "./App";
import { render, screen } from "@testing-library/react";
import { runSetup } from "../../scripts/YieldStEthLever/ganache";
import { providers } from "ethers";

describe("App", () => {
  it("should tell the user to install an provider", () => {
    render(<App ethereum={undefined} />);
    expect(screen.getByText("No wallet detected.")).toBeInTheDocument();
  });

  describe("with an Ethereum injector", () => {
    let ganacheProvider: ganache.EthereumProvider;
    beforeEach(async () => {
      ganacheProvider = ganache.provider({
        logging: { quiet: true },
        fork: { network: "mainnet", blockNumber: 15039442 },
        wallet: {
          mnemonic:
            "test test test test test test test test test test test junk",
          unlockedAccounts: ["0x3b870db67a45611CF4723d44487EAF398fAc51E3"],
        },
      });
      await runSetup(
        new providers.Web3Provider(
          ganacheProvider as unknown as ExternalProvider
        )
      );
      console.log("done with setup");
    });

    afterEach(async () => {
      await ganacheProvider.disconnect();
    });

    it("shows a connect button", async () => {
      render(<App ethereum={ganacheProvider as unknown as ExternalProvider} />);

      expect(
        screen.getByText("Please connect to your wallet.")
      ).toBeInTheDocument();

      const button = screen.getByText("Connect Wallet");
      expect(button).toBeInTheDocument();

      button.click();

      const els = await screen.findByText("Balance:");
    });
  });
});
