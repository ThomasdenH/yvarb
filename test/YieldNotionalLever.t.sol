// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/YieldNotionalLever.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/vault-v2/FYToken.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "./Protocol.sol";
import "@yield-protocol/vault-v2/utils/Giver.sol";
import "@yield-protocol/vault-v2/FlashJoin.sol";
import "@yield-protocol/vault-v2/interfaces/ICauldron.sol";
import "@yield-protocol/vault-v2/interfaces/IFYToken.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";
import "@yield-protocol/vault-v2/other/notional/NotionalJoin.sol";

abstract contract ZeroState is Test {
    address constant timeLock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    address constant usdcWhale = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
    address constant daiWhale = 0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8;
    address constant ethWhale = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ICauldron constant cauldron =
        ICauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);
    FlashJoin constant daiJoin =
        FlashJoin(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc); // dai
    FlashJoin constant usdcJoin =
        FlashJoin(0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4); // usdc
    ILadle constant ladle = ILadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);

    Protocol immutable protocol;
    Giver immutable giver;
    YieldNotionalLever lever;

    bytes6 constant fyusdcSeriesId = 0x303230380000;
    bytes6 constant fydaiSeriesId = 0x303130380000;
    bytes6 constant fyethSeriesId = 0x303030390000;

    bytes6 constant fusdcIlkId = 0x323400000000;
    bytes6 constant fdaiIlkId = 0x323300000000;
    bytes6 constant fethIlkId = 0x323900000000;

    bytes6 constant ethIlkId = 0x303000000000;
    bytes6 constant daiIlkId = 0x303100000000;
    bytes6 constant usdcIlkId = 0x303200000000;

    bytes12 public vaultId;
    bytes6 public fIlkId;
    bytes6 public fSeriesId;
    bytes6 public ilkId;
    uint256 public baseAmount;
    uint256 public borrowAmount;

    uint256 public initialUserBalance;
    uint256 public finalUserBalance;

    constructor() {
        protocol = new Protocol();
        giver = Giver(0xa98F3211997FDB072B6a8E2C2A26C34BC447f873);

        vm.prank(usdcWhale);
        IERC20(USDC).transfer(address(this), 2000e6);
        vm.prank(daiWhale);
        IERC20(DAI).transfer(address(this), 2000e18);
        vm.prank(ethWhale);
        payable(address(this)).transfer(2000e18);
    }

    function setUp() public virtual {
        lever = new YieldNotionalLever(giver);

        fIlkId = fethIlkId;
        fSeriesId = fyethSeriesId;
        ilkId = ethIlkId;
        baseAmount = 2000e18;
        borrowAmount = 30e18;
        USDC.approve(address(lever), type(uint256).max);
        DAI.approve(address(lever), type(uint256).max);
        WETH.approve(address(lever), type(uint256).max);

        vm.prank(timeLock);
        giver.grantRole(0x35775afb, address(lever));
        if (ilkId == usdcIlkId)
            initialUserBalance = USDC.balanceOf(address(this));
        else initialUserBalance = DAI.balanceOf(address(this));
    }

    /// @notice Create a vault.
    function leverUp(
        uint256 baseAmount,
        uint256 borrowAmount,
        bytes6 ilkId,
        bytes6 seriesId
    ) public returns (bytes12) {
        // Expect at least 80% of the value to end up as collateral
        // uint256 eulerAmount = pool.sellFYTokenPreview(baseAmount + borrowAmount);

        vaultId = lever.invest{value:baseAmount}(
            seriesId,
            ilkId, // ilkId
            baseAmount,
            borrowAmount
        );
        return vaultId;
    }

    /// Return the available balance in the join.
    function availableBalance(bytes6 ilkIdToCheck)
        public
        view
        returns (uint256 available)
    {
        // INotionalJoin notionalJoin = INotionalJoin(address(ladle.joins(ilkIdToCheck)));
        // IERC20 token = IERC20(notionalJoin.asset());
        // available = token.balanceOf(address(notionalJoin)) - notionalJoin.storedBalance();
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}
}

contract VaultTest is ZeroState {
    function testVault() public {
        uint256 availableAtStart = availableBalance(fIlkId);
        vaultId = leverUp(baseAmount, borrowAmount, fIlkId, fSeriesId);
        DataTypes.Vault memory vault = cauldron.vaults(vaultId);
        assertEq(vault.owner, address(this));
        assertGt(cauldron.balances(vaultId).art, borrowAmount);
        assertGt(cauldron.balances(vaultId).ink, baseAmount + borrowAmount);
        // Test that we left the join as we encountered it
        // assertEq(availableBalance(fIlkId), availableAtStart);
        // Assert that the balances are empty
        assertEq(IERC20(USDC).balanceOf(address(lever)), 0);
        assertEq(IERC20(DAI).balanceOf(address(lever)), 0);
        assertEq(
            IPool(ladle.pools(fSeriesId)).fyToken().balanceOf(address(lever)),
            0
        );
    }
}

contract DivestTest is ZeroState {
    function setUp() public override {
        super.setUp();
        vaultId = leverUp(baseAmount, borrowAmount, fIlkId, fSeriesId);
    }

    function testRepay() public {
        uint256 availableAtStart = availableBalance(fIlkId);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);

        lever.divest(vaultId, fSeriesId, fIlkId, balances.ink, balances.art, 0);

        // Test that we left the join as we encountered it
        assertEq(availableBalance(fIlkId), availableAtStart);

        // Assert that the balances are empty
        assertEq(USDC.balanceOf(address(lever)), 0);
        assertEq(DAI.balanceOf(address(lever)), 0);
        assertEq(
            IPool(ladle.pools(fSeriesId)).fyToken().balanceOf(address(lever)),
            0
        );

        if (ilkId == usdcIlkId)
            finalUserBalance = USDC.balanceOf(address(this));
        else finalUserBalance = DAI.balanceOf(address(this));
        // assertGt(finalUserBalance, initialUserBalance);
    }

    function testDoClose() public {
        uint256 availableAtStart = availableBalance(fIlkId);
        DataTypes.Series memory series_ = cauldron.series(fSeriesId);
        vm.warp(series_.maturity);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);

        NotionalJoin tempJoin = new NotionalJoin(0x1344A36A1B56144C3Bc62E7757377D288fDE0369,0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0,1679616000,1);
        vm.etch(address(0xC4cb2489a845384277564613A0906f50dD66e482), address(tempJoin).code);

        lever.divest(vaultId, fSeriesId, fIlkId, balances.ink, balances.art, 0);

        // Test that we left the join as we encountered it
        // assertEq(availableBalance(fIlkId), availableAtStart);

        // Assert that the balances are empty
        assertEq(USDC.balanceOf(address(lever)), 0);
        assertEq(DAI.balanceOf(address(lever)), 0);
        assertEq(
            IPool(ladle.pools(fSeriesId)).fyToken().balanceOf(address(lever)),
            0
        );
        if (ilkId == usdcIlkId)
            finalUserBalance = USDC.balanceOf(address(this));
        else finalUserBalance = DAI.balanceOf(address(this));
        assertGt(finalUserBalance, initialUserBalance);
    }
}
