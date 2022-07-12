import { ethers, VoidSigner } from "ethers";
import { MutableRefObject } from "react";
import { Contracts } from "../contracts";
import { AssetId } from "./Strategy";
import { loadSeriesAndStartListening, loadVaultsAndStartListening } from "./Vault";

const {INFURA_PROJECT_ID} = process.env;

describe('loadVaultsAndStartListening', () => {
    const vaultOwner = "0xefd67615d66e3819539021d40e155e1a6107f283";
    let provider: ethers.providers.Provider;
    let signer: ethers.Signer;
    beforeAll(() => {
        if (INFURA_PROJECT_ID === undefined) {
            throw new Error('To run this test, the INFURA_PROJECT_ID environment variable need to be set');
        }
        provider = new ethers.providers.InfuraProvider('mainnet', INFURA_PROJECT_ID);
        signer = new VoidSigner(vaultOwner).connect(provider);
    });

    it('should load vaults', async () => {
        const contracts: MutableRefObject<Contracts> = { current: {}};
        const resolved = new Promise((resolve) => {
            // Expect to load at least one built vault
            loadVaultsAndStartListening(contracts, vaultOwner, signer, provider, (ev) => {
                expect(ev.vaultId).toBeDefined();
                resolve(undefined);
            });
        });
        await resolved;
    });
});

describe('loadSeriesAndStartListening', () => {
    const address = "0xefd67615d66e3819539021d40e155e1a6107f283";
    let provider: ethers.providers.Provider;
    let signer: ethers.Signer;
    beforeAll(() => {
        if (INFURA_PROJECT_ID === undefined) {
            throw new Error('To run this test, the INFURA_PROJECT_ID environment variable need to be set');
        }
        provider = new ethers.providers.InfuraProvider('mainnet', INFURA_PROJECT_ID);
        signer = new VoidSigner(address).connect(provider);
    });

    it('should load vaults', async () => {
        const contracts: MutableRefObject<Contracts> = { current: {}};
        const resolved = new Promise((resolve) => {
            // Expect to load at least one built vault
            loadSeriesAndStartListening(contracts, signer, provider, (ev) => {
                expect(ev.seriesId).toBeDefined();
                expect(ev.baseId).toBeDefined();
                expect(ev.fyToken).toBeDefined();
                resolve(undefined);
            }, AssetId.WEth);
        });
        await resolved;
    });
});
