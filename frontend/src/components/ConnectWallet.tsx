import React from "react";

import { NetworkErrorMessage } from "./NetworkErrorMessage";

export function ConnectWallet({
  connectWallet,
  networkError,
  dismiss,
}: {
  connectWallet: () => void;
  networkError?: string;
  dismiss: () => void;
}) {
  return (
    <div>
        <div >
          {/* Metamask network should be set to Localhost:8545. */}
          {networkError && (
            <NetworkErrorMessage message={networkError} dismiss={dismiss} />
          )}
        </div>
        <div>
          <p>Please connect to your wallet.</p>
          <button
            className="button"
            type="button"
            onClick={connectWallet}
          >
            Connect Wallet
          </button>
        </div>
    </div>
  );
}
