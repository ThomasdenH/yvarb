// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

struct Vault {
    address owner;
    bytes6 seriesId; // Each vault is related to only one series, which also determines the underlying.
    bytes6 ilkId; // Asset accepted as collateral
}

interface IFYToken {}

struct Series {
    IFYToken fyToken; // Redeemable token for the series.
    bytes6 baseId; // Asset received on redemption.
    uint32 maturity; // Unix time at which redemption becomes possible.
}

struct Balances {
    uint128 art; // Debt amount
    uint128 ink; // Collateral amount
}

interface YieldLadle {
  function pools(bytes6 seriesId) external view returns (address);
  function build(bytes6 seriesId, bytes6 ilkId, uint8 salt)
        external payable
        returns(bytes12, Vault memory);
  function serve(bytes12 vaultId_, address to, uint128 ink, uint128 base, uint128 max)
        external payable
        returns (uint128 art);
  function repay(bytes12 vaultId_, address to, int128 ink, uint128 min)
        external payable
        returns (uint128 art);
  function repayVault(bytes12 vaultId_, address to, int128 ink, uint128 max)
        external payable
        returns (uint128 base);
  function close(bytes12 vaultId_, address to, int128 ink, int128 art)
        external payable
        returns (uint128 base);
}

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

interface yVault {
  function deposit(uint amount) external returns (uint256);
  function withdraw() external returns (uint);
}

interface IToken {
    function loanTokenAddress() external view returns (address);
    function flashBorrow(
        uint256 borrowAmount,
        address borrower,
        address target,
        string calldata signature,
        bytes calldata data
    ) external payable returns (bytes memory);
}

interface Cauldron {
  function series(bytes6 seriesId) external view returns (Series memory);
  function vaults(bytes12 vaultId) external view returns (Vault memory);
  function balances(bytes12 vaultId) external view returns (Balances memory);
  function debtToBase(bytes6 seriesId, uint128 art)
        external
        returns (uint128 base);
}

contract YieldLever {
  yVault constant yvUSDC = yVault(0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE);
  bytes6 constant ilkId = bytes6(0x303900000000); // for yvUSDC
  IToken constant iUSDC = IToken(0x32E4c68B3A4a813b710595AebA7f6B7604Ab9c15); 
  IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  address constant USDCJoin = address(0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4);
  YieldLadle constant Ladle = YieldLadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
  address constant yvUSDCJoin = address(0x403ae7384E89b086Ea2935d5fAFed07465242B38);
  Cauldron constant cauldron = Cauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);

  bytes4 private constant BUILD_SELECTOR = bytes4(keccak256("build(bytes6,bytes6,uint8)"));
  bytes4 private constant SERVE_SELECTOR = bytes4(keccak256("serve(bytes12,address,uint128,uint128,uint128)"));
  bytes4 private constant REPAY_SELECTOR = bytes4(keccak256("repayVault(bytes12,address,int128,uint128)"));
  bytes4 private constant CLOSE_SELECTOR = bytes4(keccak256("close(bytes12,address,int128,int128)"));

  mapping (address => bytes12) public addressToVaultId;

  /// @notice Invest `baseAmount` and borrow an additional `borrowAmount`.
  ///   Use this to obtain a maximum of `maxFyAmount` to repay the flash loan.
  ///   The end goal is to have a debt of `borrowAmount`, but earn interest on
  ///   the entire collateral, including the borrowed part.
  /// @param baseAmount - The amount to invest from your own funds.
  /// @param borrowAmount - The extra amount to borrow. This is immediately
  ///   repaid, so setting this to 3 times baseAmount will incur a debt of 75%
  ///   of the collateral.
  /// @param maxFyAmount - The maximum amount of fyTokens to sell. Should be
  ///   enough to cover the flash loan.
  /// @param seriesId - The series Id to invest in. For example, 0x303230360000
  ///   for FYUSDC06LP.
  function invest(
    uint256 baseAmount,
    uint128 borrowAmount,
    uint128 maxFyAmount,
    bytes6 seriesId
  ) external {
    USDC.transferFrom(msg.sender, address(this), baseAmount);
    address vaultOwner = msg.sender;
    iUSDC.flashBorrow(
        borrowAmount,
        address(this),
        address(this),
        "",
        abi.encodeWithSignature("doInvest(bytes6,uint128,uint128,address)", seriesId, borrowAmount, maxFyAmount, vaultOwner)
    );
  }

  /// @notice This function is called inside the flash loan and handles the
  ///   actual investment.
  /// @param seriesId - The series to invest in.
  /// @param borrowAmount - The amount borrowed using a flash loan.
  /// @param owner - The to-be owner of the leverage. Only this address can withdraw.
  function doInvest(
    bytes6 seriesId, 
    uint128 borrowAmount,
    uint128 maxFyAmount,
    address owner
  ) external {
    // Deposit USDC.
    /// totalBalance >= baseAmount + borrowAmount
    uint totalBalance = USDC.balanceOf(address(this));
    USDC.approve(address(yvUSDC), totalBalance);
    yvUSDC.deposit(totalBalance);

    // And withdraw yvUSDC
    uint128 yvUSDCBalance = uint128(IERC20(address(yvUSDC)).balanceOf(address(this)));
    IERC20(address(yvUSDC)).transfer(yvUSDCJoin, yvUSDCBalance);

    // Create a Yield vault
    (bytes12 vaultId, ) = Ladle.build(seriesId, ilkId, 0);
    // Add collateral and borrow enough to repay the flash loan.
    Ladle.serve(vaultId, address(this), yvUSDCBalance, borrowAmount, maxFyAmount);

    // Set the vault owner
    addressToVaultId[owner] = vaultId;

    // Repay flash loan
    USDC.transfer(address(iUSDC), borrowAmount); // repay
  }

  /// @notice Empty a vault.
  /// @param maxAmount - The amount of USDC to borrow at a maximum to repay the loan
  function unwind(uint256 maxAmount, int128 art) external {
    bytes12 vaultId = addressToVaultId[msg.sender];
    Vault memory vault_ = cauldron.vaults(vaultId);
    Series memory series_ = cauldron.series(vault_.seriesId);
    if (uint32(block.timestamp) >= series_.maturity) {
      // Series is past maturity,
      iUSDC.flashBorrow(
        uint256(uint128(art)),
        address(this),
        address(this),
        "",
        abi.encodeWithSignature("doClose(address)", msg.sender)
      );
    } else {
      // Series is not past maturity
      iUSDC.flashBorrow(
        maxAmount,
        address(this),
        address(this),
        "",
        abi.encodeWithSignature("doRepay(address)", msg.sender)
      );
    }
  }

  /// @notice Repay a vault after having borrowed a suitable amount using a
  ///   flash loan. Will only succeed if the pool hasn't reached its expiration
  ///   date yet.
  /// @param addr - The address of the owner. This is the address that will be
  ///   used to obtain certain parameters, and it is also the destination for
  ///   the profit that was obtained.
  function doRepay(address addr) external {
    bytes12 vaultId = addressToVaultId[addr];  
    // The amount borrowed in the flash loan.
    uint256 borrowAmount = USDC.balanceOf(address(this));
    // Transfer it to the pool.
    bytes6 seriesId = cauldron.vaults(vaultId).seriesId;
    address pool = Ladle.pools(seriesId);
    USDC.transfer(pool, borrowAmount);
    // Repay Yield vault debt
    uint128 ink = cauldron.balances(vaultId).ink;
    Ladle.repayVault(vaultId, address(this), -int128(ink), uint128(borrowAmount));
    // withdraw from yvUSDC
    yvUSDC.withdraw();
    // Repay the flash loan
    USDC.transfer(address(iUSDC), borrowAmount);
    // Send the remaining USDC balance to the user.
    USDC.transfer(addr, USDC.balanceOf(address(this)));
  }

  /// @notice Close a vault that has already reached its expiration date.
  /// @param addr - The address of the owner. This is the address that will be
  ///   used to obtain certain parameters, and it is also the destination for
  ///   the profit that was obtained.
  function doClose(address addr) external {
    bytes12 vaultId = addressToVaultId[addr];

    // The amount borrowed in the flash loan.
    uint256 borrowAmount = USDC.balanceOf(address(this));
    // Close the vault
    uint128 ink = cauldron.balances(vaultId).ink;
    uint128 art = cauldron.balances(vaultId).art;
    Ladle.close(vaultId, address(this), -int128(ink), int128(art));

    // Withdraw from yvUSDC
    yvUSDC.withdraw();
    // Repay flash loan
    USDC.transfer(address(iUSDC), borrowAmount);
    // Send the remainder to user
    USDC.transfer(addr, USDC.balanceOf(address(this)));
  }
}
