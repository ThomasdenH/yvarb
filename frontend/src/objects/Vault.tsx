import { BigNumber, ethers } from "ethers";
import { ContractContext as Cauldron } from "../abi/Cauldron";
import { ILK_ID } from "../App";

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
const BLOCK_STEPS = 10000;

/**
 * Look for vaults that have been created on or transferred to the address.
 */
export async function loadVaults(
  cauldron: Cauldron,
  account: string,
  provider: ethers.providers.Web3Provider,
  vaultDiscseriesDiscoveredovered: (vaultId: string) => void,
  seriesDiscovered: (series: SeriesDefinition) => void
) {
  if ((await provider.getNetwork()).chainId === 1337) {
    // Ganache log fetching is so slow as to be unusable for us. Use hardcoded pools instead.
    seriesDiscovered({
      poolAddress: '0x80142add3A597b1eD1DE392A56B2cef3d8302797',
      seriesId: '0x303230350000'
    });
    seriesDiscovered({
      poolAddress: '0xEf82611C6120185D3BF6e020D1993B49471E7da0',
      seriesId: '0x303230360000'
    });
  } else {
    const currentBlock: number = await provider.getBlockNumber();
    const vaultsBuiltFilter = cauldron.filters.VaultBuilt(null, account, null);
    const vaultsReceivedFilter = cauldron.filters.VaultGiven(null, account);
    const seriesAddedFilter = cauldron.filters.SeriesAdded(null, ILK_ID, null);

    const cauldronWithFilter = cauldron as Cauldron & {
      queryFilter(a: typeof vaultsBuiltFilter, b: number, c: number): Promise<unknown[]>;
      queryFilter(a: typeof vaultsReceivedFilter, b: number, c: number): Promise<unknown[]>;
      queryFilter(a: typeof seriesAddedFilter, b: number, c: number): Promise<unknown[]>;
    };

    let end = currentBlock;
    while (end > CAULDRON_CREATED_BLOCK_NUMBER) {
      const start = Math.max(end - BLOCK_STEPS, CAULDRON_CREATED_BLOCK_NUMBER);
      const [vaultsBuilt, vaultsReceived] = await Promise.all([
        cauldronWithFilter.queryFilter(vaultsBuiltFilter, start, end),
        cauldronWithFilter.queryFilter(vaultsReceivedFilter, start, end),
      ]);
      const series = await cauldronWithFilter.queryFilter(seriesAddedFilter, start, end);
      if (vaultsBuilt.length !== 0 || vaultsReceived.length !== 0)
        // TODO: Call callback
        console.log(vaultsBuilt, vaultsReceived);
      if (series.length !== 0)
        console.log(series);
      console.log(start);
      end = start;
    }
  }
}

export function emptyVaults(): VaultsAndBalances {
  return {
    vaults: Object.create(null) as Vaults,
    balances: Object.create(null) as Balances,
  };
}
