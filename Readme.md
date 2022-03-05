# How to test

Run  `ganache-cli`:
```
ganache-cli --fork {NODE_ID} --wallet.defaultBalance 1000000 --wallet.unlockedAccounts 0x3b870db67a45611CF4723d44487EAF398fAc51E3
npx truffle compile
npx truffle test .\test\TestYieldLever.sol
```
