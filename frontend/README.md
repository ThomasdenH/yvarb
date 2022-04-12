# Run the node

```
ganache-cli --fork RPC_ENDPOINT --wallet.defaultBalance 1000000 --wallet.unlockedAccounts 0x3b870db67a45611CF4723d44487EAF398fAc51E3 --wallet.mnemonic "SEED" --miner.defaultGasPrice 0
```

# Start server

```
# Deploy contracts
npx truffle deploy

# Give contract permission, buy USDC
npx truffle exec .\scripts\prepare.js

# Start server
cd ./frontend
npm start
```
