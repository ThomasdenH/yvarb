# How to test

Run  `ganache-cli`:
```
ganache-cli --fork https://mainnet.infura.io/v3/6f4f43507fa24302a651b52073c98d8a --wallet.defaultBalance 1000000 --wallet.unlockedAccounts 0x3b870db67a45611CF4723d44487EAF398fAc51E3 --wallet.mnemonic "sure submit thank indoor electric grant face swallow donkey cousin narrow master"
npx truffle compile
npx truffle test .\test\TestYieldLever.sol
```

# Forge
```
forge deploy
```
