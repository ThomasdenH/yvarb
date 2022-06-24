/// <reference types="react-scripts" />

import { Web3Provider, ExternalProvider } from "@ethersproject/providers";

declare global {
  interface Window {
    ethereum: Web3Provider & ExternalProvider;
  }
}
