# Deploy for Ganache
- Start Ganache: `ganache --fork.url https://mainnet.infura.io/v3/<INFURA_IDs> --wallet.mnemonic 'test test test test test test test test test test test junk' --fork.blockNumber 15039442 --wallet.unlockedAccounts 0x3b870db67a45611CF4723d44487EAF398fAc51E3`
- `npx ts-node .\scripts\YieldStEthLever\deployTest.ts 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 http://127.0.0.1:8545`
- `npx ts-node .\scripts\YieldStEthLever\timeLockPrank_tenderly.ts 0x677df0cb865368207999f2862ece576dc56d8df6 0x0cf17d5dcda9cf25889cec9ae5610b0fb9725f65 http://127.0.0.1:8545`
- `npx ts-node .\scripts\YieldStEthLever\obtainFyTokens_ganache.ts 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`

# Deploy for Anvil
Anvil currently hangs unpredictably:
- `forge script scripts/YieldStEthLever/DeployTest.sol -vvv --fork-url http://127.0.0.1:8545 --broadcast -i 1 --sender 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266`
- `npx ts-node .\scripts\YieldStEthLever\timeLockPrank.ts 0x677df0cb865368207999f2862ece576dc56d8df6`
- `npx ts-node .\scripts\YieldStEthLever\obtainFyTokens.ts 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266`
