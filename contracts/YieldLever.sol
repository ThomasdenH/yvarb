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
  function give(bytes12 vaultId_, address receiver)
        external payable
        returns(Vault memory vault);
}

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function balanceOf(address owner) external view returns (uint);
  
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

// You can make this interface inherit from IERC20, and will be useful later on
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
  function give(bytes12 vaultId, address receiver)
        external
        returns(Vault memory vault);
}

contract YieldLever {
  yVault constant yvUSDC = yVault(0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE);
  bytes6 constant ilkId = bytes6(0x303900000000); // for yvUSDC
  IToken constant iUSDC = IToken(0x32E4c68B3A4a813b710595AebA7f6B7604Ab9c15); 
  // Variable names are lowerCamelCase. Acronyms are kept all in the same case. The variable below would be `usdc`
  IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  // Below would be `usdcJoin`
  address constant USDCJoin = address(0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4);
  // Below would be `ladle`
  YieldLadle constant Ladle = YieldLadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
  address constant yvUSDCJoin = address(0x403ae7384E89b086Ea2935d5fAFed07465242B38);
  Cauldron constant cauldron = Cauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);

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
    (bytes12 vaultId, ) = Ladle.build(seriesId, ilkId, 0);
    iUSDC.flashBorrow(
        borrowAmount,
        address(this),
        address(this),
        "",
        abi.encodeWithSignature("doInvest(uint128,uint128,bytes12)", borrowAmount, maxFyAmount, vaultId)
    );
    
    // Finally, give the vault to the sender
    Ladle.give(vaultId, msg.sender);
  }

  /// @notice This function is called inside the flash loan and handles the
  ///   actual investment.
  /// @param borrowAmount - The amount borrowed using a flash loan.
  /// @param maxFyAmount - The maximum amount of fyTokens to sell.
  /// @param vaultId - The vault id to invest in.
  function doInvest(
    uint128 borrowAmount,
    uint128 maxFyAmount,
    bytes12 vaultId
  ) external {
    // Deposit USDC.
    /// totalBalance >= baseAmount + borrowAmount
    // You can use `borrowBalance` and remove the line below.
    uint totalBalance = USDC.balanceOf(address(this));
    // You can approve for MAX on the constructor, and remove the line below.
    USDC.approve(address(yvUSDC), totalBalance);

    // `deposit` is overloaded. You can call `deposit(borrowAmount, yvUSDCJoin)` and remove the transfer below.
    yvUSDC.deposit(totalBalance);

    // And withdraw yvUSDC
    // The return value for `deposit` is the number of yvUSDC received. You can take it in the previous line, and remove the line below.
    uint128 yvUSDCBalance = uint128(IERC20(address(yvUSDC)).balanceOf(address(this)));
    IERC20(address(yvUSDC)).transfer(yvUSDCJoin, yvUSDCBalance);

    // Create a Yield vault
    // Add collateral and borrow enough to repay the flash loan.
    Ladle.serve(vaultId, address(this), yvUSDCBalance, borrowAmount, maxFyAmount);

    // Repay flash loan
    // You can use `address(iUSDC)` as the second parameter in `serve`, and remove the line below.
    USDC.transfer(address(iUSDC), borrowAmount); // repay
  }

  /// @notice Empty a vault.
  /// @param vaultId - The id of the vault that should be emptied.
  /// @param maxAmount - The maximum amount of USDC to borrow. If past
  ///   maturity, this parameter is unused as the amount can be determined
  ///   precisely.
  function unwind(bytes12 vaultId, uint256 maxAmount) external {
    Vault memory vault_ = cauldron.vaults(vaultId);
    Series memory series_ = cauldron.series(vault_.seriesId);
    
    // Test that the caller is the owner of the vault
    assert(vault_.owner == msg.sender);

    // Give the vault to the contract
    cauldron.give(vaultId, address(this));

    if (uint32(block.timestamp) < series_.maturity) {
      // Series is not past maturity
      iUSDC.flashBorrow(
        maxAmount,
        address(this),
        address(this),
        "",
        abi.encodeWithSignature("doRepay(address,bytes12)", msg.sender, vaultId)
      );
    } else {
      // Series is past maturity,
      uint128 art = cauldron.balances(vaultId).art;
      uint128 base = cauldron.debtToBase(vault_.seriesId, art);
      iUSDC.flashBorrow(
        base,
        address(this),
        address(this),
        "",
        abi.encodeWithSignature("doClose(address,bytes12,uint128)", msg.sender, vaultId, base)
      );
    }
  }

  /// @notice Repay a vault after having borrowed a suitable amount using a
  ///   flash loan. Will only succeed if the pool hasn't reached its expiration
  ///   date yet.
  /// @param owner - The address of the owner. This is the address that will be
  ///   used to obtain certain parameters, and it is also the destination for
  ///   the profit that was obtained.
  /// @param vaultId - The vault id to repay.
  function doRepay(address owner, bytes12 vaultId) external {
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
    USDC.transfer(owner, USDC.balanceOf(address(this)));
  }

  /// @notice Close a vault that has already reached its expiration date.
  /// @param owner - The address of the owner. This is the address that will be
  ///   used to obtain certain parameters, and it is also the destination for
  ///   the profit that was obtained.
  /// @param vaultId - The vault id to repay.
  /// @param base - The size of the debt in USDC.
  function doClose(address owner, bytes12 vaultId, uint128 base) external {
    // Approve transer of USDC
    USDC.approve(USDCJoin, base);

    // Close the vault
    uint128 ink = cauldron.balances(vaultId).ink;
    Ladle.close(vaultId, address(this), -int128(ink), -int128(base));

    // Withdraw from yvUSDC
    yvUSDC.withdraw();
    // Repay flash loan
    USDC.transfer(address(iUSDC), base);
    // Send the remainder to user
    USDC.transfer(owner, USDC.balanceOf(address(this)));
  }
}
