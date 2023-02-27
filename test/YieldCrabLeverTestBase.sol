// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/YieldCrabLever.sol";
import "contracts/YieldLeverBase.sol";
import "contracts/interfaces/IStableSwap.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/vault-v2/src/FYToken.sol";
import "@yield-protocol/utils-v2/src/token/IERC20.sol";
import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "./Protocol.sol";
import "@yield-protocol/vault-v2/src/utils/Giver.sol";
import "@yield-protocol/vault-v2/src/FlashJoin.sol";
import "@yield-protocol/vault-v2/src/Cauldron.sol";
import "@yield-protocol/vault-v2/src/interfaces/ICauldron.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";

interface IOpynController {
    function vaults(uint256 vaultId)
        external
        returns (
            address operator,
            uint32 nftCollateralId,
            uint96 collateralAmount,
            uint128 shortAmount
        );
}

interface IOpynQuoter {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (
            uint256 amountOut,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        );
}

abstract contract ZeroState is Test {
    address timeLock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    address ethWhale = 0xDA9dfA130Df4dE4673b89022EE50ff26f6EA73Cf;
    address wethWhale = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    address daiWhale = 0xDA9dfA130Df4dE4673b89022EE50ff26f6EA73Cf;
    address usdcWhale = 0xDA9dfA130Df4dE4673b89022EE50ff26f6EA73Cf;
    Giver giver = Giver(0xa98F3211997FDB072B6a8E2C2A26C34BC447f873);
    IQuoter uniswapQuoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ICauldron cauldron = ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    IERC20 constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ILadle constant ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
    IOpynController constant opynController =
        IOpynController(0x64187ae08781B09368e6253F9E94951243A493D5);
    IOpynQuoter constant opynQuoter =
        IOpynQuoter(0xC8d3a4e6BB4952E3658CCA5081c358e6935Efa43);

    bytes6 constant usdcIlkId = 0x303200000000;
    bytes6 constant daiIlkId = 0x303100000000;
    bytes6 constant ethIlkId = 0x303000000000;
    bytes6 constant usdcSeriesId = 0x303230380000;
    bytes6 constant daiSeriesId = 0x303130380000;
    bytes6 constant ethSeriesId = 0x303030380000;
    bytes6 public seriesId; // = 0x303230380000; //0x303130380000; //0x303030380000;
    bytes6 public ilkId; // = 0x303200000000; //0x303100000000; //0x303000000000;
    uint256 public crabVaultId = 286; //Crab VaultId from crab strategy contract

    YieldCrabLever lever;
    Protocol protocol;
    IPool public pool;
    FlashJoin flashJoin;
    FYToken public fyToken;

    uint256 public base;
    uint256 public borrow;
    uint256 public unit;
    uint256 public initialUserBalance;
    uint256 public finalUserBalance;
    uint256 public balanceAfterInvest;
    bool public isEth;
    bytes12 public vaultId;

    constructor() {
        protocol = new Protocol();
    }

    function setUp() public virtual {
        vm.createSelectFork("TENDERLY", 16075456);
        address(0).call{value: address(this).balance}("");
        DataTypes.Series memory seriesData = cauldron.series(seriesId);
        unit = 10**IERC20Metadata(cauldron.assets(ilkId)).decimals();
        pool = IPool(ladle.pools(seriesId));
        fyToken = FYToken(address(pool.fyToken()));

        vm.label(address(fyToken), fyToken.symbol());

        if (ilkId == usdcIlkId) {
            vm.prank(usdcWhale);
            usdc.transfer(address(this), base * unit);

            initialUserBalance = usdc.balanceOf(address(this));
        }
        if (ilkId == daiIlkId) {
            vm.prank(daiWhale);
            dai.transfer(address(this), base * unit);

            initialUserBalance = dai.balanceOf(address(this));
        }
        if (ilkId == ethIlkId) {
            if (isEth) {
                vm.prank(ethWhale);
                address(this).call{value: base * unit}("");
            } else {
                vm.prank(wethWhale);
                weth.transfer(address(this), base * unit);
            }
            initialUserBalance =
                address(this).balance +
                weth.balanceOf(address(this));
        }

        lever = new YieldCrabLever(giver);

        //Label
        vm.label(address(lever), "YieldLever");

        usdc.approve(address(lever), type(uint256).max);
        dai.approve(address(lever), type(uint256).max);
        weth.approve(address(lever), type(uint256).max);

        vm.startPrank(timeLock);
        AccessControl giverAccessControl = AccessControl(address(giver));
        giverAccessControl.grantRole(0xe4fd9dc5, timeLock);
        giverAccessControl.grantRole(Giver.seize.selector, address(lever));
        vm.stopPrank();
    }

    /// Return the available balance in the join.
    function availableBalance(FlashJoin join)
        public
        view
        returns (uint256 available)
    {
        IERC20 token = IERC20(join.asset());
        available = token.balanceOf(address(join)) - join.storedBalance();
    }

    /// @notice Create a vault.
    function investETH() public returns (bytes12) {
        uint256 baseAmount = base * unit;
        uint256 borrowAmount = borrow * unit;
        DataTypes.SpotOracle memory spotOracle_ = cauldron.spotOracles(
            ilkId,
            lever.crabId()
        );

        (uint256 inkValue, ) = spotOracle_.oracle.get(
            ilkId,
            lever.crabId(),
            baseAmount + borrowAmount
        ); // ink * spot

        uint256 minCollateral = 0;

        vaultId = lever.invest{value: baseAmount}(
            seriesId,
            ilkId,
            baseAmount,
            borrowAmount,
            minCollateral
        );
        balanceAfterInvest = _currentBalance();
        return vaultId;
    }

    function investRest() public returns (bytes12) {
        uint256 baseAmount = base * unit;
        uint256 borrowAmount = borrow * unit;

        uint256 minCollateral = uint256((_minCollateral() * 80) / 100);

        vaultId = lever.invest(
            seriesId,
            ilkId,
            baseAmount,
            borrowAmount,
            minCollateral
        );

        balanceAfterInvest = _currentBalance();

        return vaultId;
    }

    function _currentBalance() internal returns (uint256) {
        if (ilkId == usdcIlkId) {
            return
                usdc.balanceOf(address(this)) +
                uniswapQuoter.quoteExactInputSingle(
                    address(weth), // We are taking weth as we have eth leftover from crab deposit
                    cauldron.assets(ilkId),
                    3000,
                    address(this).balance,
                    0
                );
        }
        if (ilkId == daiIlkId) {
            return
                dai.balanceOf(address(this)) +
                uniswapQuoter.quoteExactInputSingle(
                    address(weth), // We are taking weth as we have eth leftover from crab deposit
                    cauldron.assets(ilkId),
                    3000,
                    address(this).balance,
                    0
                );
        }
        if (ilkId == ethIlkId) {
            return address(this).balance + weth.balanceOf(address(this));
        }
    }

    function _checkProfitable() internal returns (bool) {
        return _currentBalance() > initialUserBalance;
    }

    function _noTokenLeftBehind() internal {
        // No tokens should be left in the contract
        assertEq(weth.balanceOf(address(lever)), 0);
        assertEq(usdc.balanceOf(address(lever)), 0);
        assertEq(dai.balanceOf(address(lever)), 0);
        assertEq(fyToken.balanceOf(address(lever)), 0);
        assertEq(address(lever).balance, 0);
    }

    function _getValues(uint256 _ethToDeposit)
        internal
        returns (uint256 value, uint256 refund)
    {
        (, , uint96 collateralAmount, uint128 shortAmount) = opynController
            .vaults(crabVaultId);
        uint256 wSqueethToMint = (_ethToDeposit * shortAmount) /
            collateralAmount;
        (uint256 expectedEthProceeds, , , ) = opynQuoter.quoteExactInputSingle(
            IOpynQuoter.QuoteExactInputSingleParams({
                tokenIn: address(0xf1B99e3E573A1a9C5E6B2Ce818b617F0E664E86B), // oSQTH
                tokenOut: address(weth),
                fee: 3000,
                amountIn: wSqueethToMint,
                sqrtPriceLimitX96: 0
            })
        );
        value = _ethToDeposit - expectedEthProceeds;
        refund = expectedEthProceeds + value - _ethToDeposit;
    }

    function _minCollateral() internal returns (uint256 minCollateral) {
        uint256 baseAmount = base * unit;
        uint256 borrowAmount = borrow * unit;
        pool = IPool(lever.ladle().pools(seriesId));
        uint256 receivedAmount = pool.sellFYTokenPreview(uint128(borrowAmount));
        uint256 amountOut;
        if (ilkId != ethIlkId)
            amountOut = uniswapQuoter.quoteExactInputSingle(
                cauldron.assets(ilkId),
                address(weth),
                3000,
                baseAmount + receivedAmount,
                0
            );

        (uint256 value, uint256 refund) = _getValues(
            ilkId == ethIlkId ? receivedAmount + baseAmount : amountOut
        );

        DataTypes.SpotOracle memory spotOracle_ = cauldron.spotOracles(
            lever.wethId(),
            lever.crabId()
        );
        (minCollateral, ) = spotOracle_.oracle.get(
            lever.wethId(),
            lever.crabId(),
            value
        );
    }

    receive() external payable {}
}

abstract contract ZeroStateTest is ZeroState {
    function setUp() public virtual override {
        super.setUp();
    }

    function testVault() public {
        vaultId = investRest();

        DataTypes.Vault memory vault = cauldron.vaults(vaultId);

        assertEq(vault.owner, address(this));
        _noTokenLeftBehind();
    }

    /// @notice This function should fail if called externally.
    function testOnFlashLoan() public {
        vm.expectRevert(FlashLoanFailure.selector);
        lever.onFlashLoan(
            address(lever), // Lie!
            address(fyToken),
            1e18,
            1e16,
            bytes.concat(
                bytes1(0x01),
                seriesId,
                bytes12(0),
                bytes16(0),
                bytes16(0)
            )
        );
    }

    function testInvestRevertOnMinCollateral() public {
        uint256 baseAmount = base * unit;
        uint256 borrowAmount = borrow * unit;

        uint256 minCollateral = (_minCollateral() * 150) / 100;
        vm.expectRevert(SlippageFailure.selector);
        vaultId = lever.invest(
            seriesId,
            ilkId,
            baseAmount,
            borrowAmount,
            minCollateral
        );
    }
}

abstract contract VaultCreatedState is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        vaultId = investRest(); //25e6, 10e6);
    }

    function unwind() internal returns (bytes12) {
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        lever.divest(vaultId, seriesId, ilkId, balances.ink, balances.art, 0);
        return vaultId;
    }
}

abstract contract VaultCreatedStateTest is VaultCreatedState {
    function setUp() public virtual override {
        super.setUp();
    }

    function testRepay() public {
        unwind();

        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        assertEq(balances.art, 0);
        assertEq(balances.ink, 0);

        _noTokenLeftBehind();
        assertTrue(_checkProfitable(), "Not profitable!");
    }

    function testClose() public {
        DataTypes.Series memory series_ = cauldron.series(seriesId);

        vm.warp(series_.maturity + 1);
        unwind();
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        assertEq(balances.art, 0);
        assertEq(balances.ink, 0);
        _noTokenLeftBehind();
        assertTrue(_checkProfitable());
    }

    function testRepayRevertOnSlippage() public {
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        uint256 minBaseOut = (initialUserBalance * 150) / 100;

        vm.expectRevert(SlippageFailure.selector);
        lever.divest(vaultId, seriesId, ilkId, balances.ink, balances.art, minBaseOut);
    }

    function testCloseRevertOnSlippage() public {
        DataTypes.Series memory series_ = cauldron.series(seriesId);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        uint256 minBaseOut = (initialUserBalance * 150) / 100;
        vm.warp(series_.maturity + 1);

        vm.expectRevert(SlippageFailure.selector);
        lever.divest(vaultId, seriesId, ilkId, balances.ink, balances.art, minBaseOut);
    }
}
