import { BigNumber, Signer, providers } from "ethers";
import { MutableRefObject } from "react";
import { SeriesId } from "../balances";
import {
  CAULDRON,
  Contracts,
  getContract,
  getFyTokenAddress,
} from "../contracts";
import {
  SeriesAddedEvent,
  VaultBuiltEvent,
  VaultGivenEvent,
} from "../contracts/Cauldron.sol/Cauldron";
import { TypedListener } from "../contracts/Cauldron.sol/common";
import {
  VaultBuiltEventObject,
  VaultGivenEventObject,
} from "../contracts/YieldStEthLever.sol/Cauldron";

export interface SeriesDefinition {
  poolAddress: string;
  seriesId: string;
}

export interface Vault {
  ilkId: string;
  owner: string;
  seriesId: SeriesId;
}

export interface Balance {
  art: BigNumber;
  ink: BigNumber;
}

export interface Vaults {
  [vaultId: string]: Vault;
}

export interface Balances {
  [vaultId: string]: Balance;
}

export interface VaultsAndBalances {
  vaults: Vaults;
  balances: Balances;
}

/** Don't look prior to this block number. */
const CAULDRON_CREATED_BLOCK_NUMBER = 0;
const BLOCK_STEPS = 20_000_000;

const SKIP_LOADING_FROM_CHAIN = true;

/**
 * Look for vaults that have been created on or transferred to the address.
 */
export function loadVaultsAndStartListening(
  contracts: MutableRefObject<Contracts>,
  address: string,
  signer: Signer,
  provider: providers.Provider,
  vaultDiscovered: (
    event: VaultBuiltEventObject | VaultGivenEventObject
  ) => void
): () => void {
  const cauldron = getContract(CAULDRON, contracts, signer);
  const vaultsBuiltFilter = cauldron.filters.VaultBuilt(null, address, null);
  const vaultsReceivedFilter = cauldron.filters.VaultGiven(null, address);

  const listener1: TypedListener<VaultBuiltEvent> = (_a, _b, _c, _d, e) =>
    vaultDiscovered(e.args);
  const listener2: TypedListener<VaultGivenEvent> = (_a, _b, c) =>
    vaultDiscovered(c.args);
  cauldron.on(vaultsBuiltFilter, listener1);
  cauldron.on(vaultsReceivedFilter, listener2);

  let keepLoading = true;
  void (async () => {
    const currentBlock: number = await provider.getBlockNumber();
    let end = currentBlock;
    while (
      end > CAULDRON_CREATED_BLOCK_NUMBER &&
      keepLoading &&
      !SKIP_LOADING_FROM_CHAIN
    ) {
      const start = Math.max(end - BLOCK_STEPS, CAULDRON_CREATED_BLOCK_NUMBER);
      const [vaultsBuilt, vaultsReceived] = await Promise.all([
        cauldron.queryFilter(vaultsBuiltFilter, start, end),
        cauldron.queryFilter(vaultsReceivedFilter, start, end),
      ]);
      for (const vault of vaultsBuilt) vaultDiscovered(vault.args);
      for (const vault of vaultsReceived) vaultDiscovered(vault.args);
      end = start;
    }
  })();

  // Return the destructor
  return () => {
    keepLoading = false;
    cauldron.removeListener(vaultsBuiltFilter, listener1);
    cauldron.removeListener(vaultsReceivedFilter, listener2);
  };
}

export interface SeriesObject {
  seriesId: SeriesId;
  baseId: string;
  fyToken: string;
}

/**
 * Load series and start listening for new series.
 */
export const loadSeriesAndStartListening = (
  contracts: MutableRefObject<Contracts>,
  signer: Signer,
  seriesDiscovered: (event: SeriesObject) => void
) => {
  if (SKIP_LOADING_FROM_CHAIN) {
    const seriesId = "0x303030370000" as SeriesId;
    void getFyTokenAddress(seriesId, contracts, signer).then((fyToken) =>
      seriesDiscovered({
        baseId: "0x303000000000",
        fyToken,
        seriesId,
      })
    );
  } else {
    // TODO: Load series historically
  }
  const cauldron = getContract(CAULDRON, contracts, signer);
  const seriesAddedFilter = cauldron.filters.SeriesAdded(null, null, null);
  const listener: TypedListener<SeriesAddedEvent> = (_a, _b, _c, d) =>
    seriesDiscovered({ seriesId: d.args.seriesId as SeriesId, baseId: d.args.baseId, fyToken: d.args.fyToken});
  cauldron.on(seriesAddedFilter, listener);
  return () => {
    cauldron.removeListener(seriesAddedFilter, listener);
  };
};
