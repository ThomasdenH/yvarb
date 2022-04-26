import { BigNumber, Contract, ethers } from "ethers";

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
  [vaultId: string]: Vault
}

export interface Balances {
  [vaultId: string]: Balance
}

export interface VaultsAndBalances {
  vaults: Vaults;
  balances: Balances;
}

const CAULDRON_CREATED_BLOCK_NUMBER = 13461506;
const BLOCK_STEPS = 10;

export async function loadVaults(
  cauldron: Contract,
  account: string,
  provider: ethers.providers.Web3Provider
) {
  const currentBlock: number = await provider.getBlockNumber();
  const vaultsBuiltFilter = cauldron.filters.VaultBuilt(null, account, null);
  const vaultsReceivedFilter = cauldron.filters.VaultGiven(null, account);
  for (
    let start = CAULDRON_CREATED_BLOCK_NUMBER;
    start < currentBlock;
    start += BLOCK_STEPS
  ) {
    const end = Math.min(start + BLOCK_STEPS, currentBlock);
    console.log(start, end);
    console.log(
      (start - CAULDRON_CREATED_BLOCK_NUMBER) /
        (currentBlock - CAULDRON_CREATED_BLOCK_NUMBER)
    );
    const [vaultsBuilt, vaultsReceived] = await Promise.all([
      cauldron.queryFilter(vaultsBuiltFilter, start, end),
      cauldron.queryFilter(vaultsReceivedFilter, start, end),
    ]);
    console.log(vaultsBuilt, vaultsReceived);
  }
}

export function emptyVaults(): VaultsAndBalances {
  return {
    vaults: Object.create(null) as Vaults,
    balances: Object.create(null) as Balances,
  };
}
