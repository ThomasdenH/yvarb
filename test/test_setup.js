const timeLockAbi = require('./ABI/TimeLock.json')
// Run using $ truffle exec <path>
module.exports = async () => {
    const TimeLock = new web3.eth.Contract(timeLockAbi, '0x3b870db67a45611CF4723d44487EAF398fAc51E3');
    const data = web3.eth.abi.encodeFunctionCall({
            "inputs":[
                {"internalType":"bytes6","name":"seriesId","type":"bytes6"},
                {"internalType":"bytes6","name":"baseId","type":"bytes6"},
                {"internalType":"uint32","name":"maturity","type":"uint32"},
                {"internalType":"bytes6[]","name":"ilkIds","type":"bytes6[]"},
                {"internalType":"string","name":"name","type":"string"},
                {"internalType":"string","name":"symbol","type":"string"}
            ],
            "name":"addSeries",
            "outputs":[],
            "stateMutability":"nonpayable",
            "type":"function"
        },
        [
            "0x303230399000",
            "0x303200000000", // FYUSDC
            2648177200, // Timestamp way into the future
            [
                "0x303000000000",
                "0x303100000000",
                "0x303200000000",
                "0x303300000000"
            ],
            "FYUSDC Way Into The Future",
            "FYUSDCWITF"
        ]
    );
    await TimeLock.methods
        .execute(['0x21F7794cF4e9aF58cbd0A71Fd33C73458981239f', data])
        .send({
            from: '0xa072f81fea73ca932ab2b5eda31fa29306d58708'
        });
}
