# Deploy
To deploy:
- `forge script scripts/YieldStEthLever/DeployTest.sol -vvv --fork-url http://127.0.0.1:8545 --broadcast -i 1 --sender 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266`
- `npx ts-node .\scripts\YieldStEthLever\timeLockPrank.ts 0x677df0cb865368207999f2862ece576dc56d8df6`
- `npx ts-node .\scripts\YieldStEthLever\obtainFyTokens.ts 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266`
