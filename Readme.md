# How to test

Run  `ganache-cli`:
```
ganache-cli --fork {NODE_ID} --wallet.defaultBalance 1000000
npx truffle compile
npx truffle test .\test\TestYieldLever.sol
```
