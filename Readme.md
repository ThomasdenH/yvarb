# Forge
```sh
# Start Ganache
ganache-cli --fork https://mainnet.infura.io/v3/6f4f43507fa24302a651b52073c98d8a --wallet.defaultBalance 1000000 --wallet.unlockedAccounts 0x3b870db67a45611CF4723d44487EAF398fAc51E3 --wallet.mnemonic "sure submit thank indoor electric grant face swallow donkey cousin narrow master"

# Deploy the contract, and export the info
# --private-key: Private key belongs to mnemonic
# --gas-price: Needs to be high enough. Unfortunately Ganache can't yet suggest a gas price.
# --json: Export in JSON to extract contract info later
forge create contracts/YieldLever.sol:YieldLever --rpc-url "http://127.0.0.1:8545" --private-key 0xde7e35b0dd8b3bebebd1f793daf12659f9cf3cb7d52a3d3921fcff63808e7d05 --legacy --gas-price 182929878490 --json > ./frontend/src/generated/deployment.json

# Copy YieldLever ABI to the source folder and generate typings
cp ".\out\YieldLever.sol\YieldLever.json" ".\frontend\src\generated\abi/"
npx abi-types-generator ./frontend/src/generated/abi/YieldLever.json --provider=ethers_v5

# Do preparations
npx ts-node .\scripts\prepare-ethers.ts
```

# Testing
Run `forge test --fork-url https://mainnet.infura.io/v3/6f4f43507fa24302a651b52073c98d8a`.
