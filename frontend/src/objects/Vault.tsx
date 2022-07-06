import { BigNumber, ethers, Signer } from "ethers";
import { MutableRefObject } from "react";
import { CAULDRON, Contracts, getContract } from "../contracts";
import { SeriesAddedEvent, VaultBuiltEvent } from "../contracts/Cauldron.sol/Cauldron";
import { TypedListener } from "../contracts/Cauldron.sol/common";

export interface SeriesDefinition {
  poolAddress: string;
  seriesId: string;
}

export interface Vault {
  ilkId: string;
  owner: string;
  seriesId: string;
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

/**
 * Look for vaults that have been created on or transferred to the address.
 */
export function loadVaultsAndStartListening(
  contracts: MutableRefObject<Contracts>,
  address: string,
  signer: Signer,
  vaultDiscovered: TypedListener<VaultBuiltEvent>,
  seriesDiscovered: TypedListener<SeriesAddedEvent>
): () => void {
  const cauldron = getContract(CAULDRON, contracts, signer);
  const vaultsBuiltFilter = cauldron.filters.VaultBuilt(
    null,
    address,
    null
  );
  const vaultsReceivedFilter = cauldron.filters.VaultGiven(
    null,
    address
  );
  const seriesAddedFilter = cauldron.filters.SeriesAdded(null, null, null);

  /*const currentBlock: number = await provider.getBlockNumber();
  let end = currentBlock;
  while (end > CAULDRON_CREATED_BLOCK_NUMBER) {
    const start = Math.max(end - BLOCK_STEPS, CAULDRON_CREATED_BLOCK_NUMBER);
    const [vaultsBuilt, vaultsReceived] = await Promise.all([
      cauldron.queryFilter(vaultsBuiltFilter, start, end),
      cauldron.queryFilter(vaultsReceivedFilter, start, end),
    ]);
    const series = await cauldron.queryFilter(
      seriesAddedFilter,
      start,
      end
    );
    for (const vault of vaultsBuilt)
      vaultDiscovered(vault.args[0]);
    for (const vault of vaultsReceived)
      vaultDiscovered(vault.args[0]);
      for (const serie of series)
      seriesDiscovered(serie.args[0]);
    console.log(start);
    end = start;
  }*/

  cauldron.on(vaultsBuiltFilter, vaultDiscovered);
  cauldron.on(vaultsReceivedFilter, vaultDiscovered);
  cauldron.on(seriesAddedFilter, seriesDiscovered);

  // Return the destructor
  return () => {
    cauldron.removeListener(vaultsBuiltFilter, vaultDiscovered);
    cauldron.removeListener(vaultsReceivedFilter, vaultDiscovered);
    cauldron.removeListener(seriesAddedFilter, seriesDiscovered);
  };
}

export function emptyVaults(): VaultsAndBalances {
  return {
    vaults: Object.create(null) as Vaults,
    balances: Object.create(null) as Balances,
  };
}
