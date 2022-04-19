// SPDX-License-Identifier: UNLICENSED

/// # Security of this contract
/// This contract owns nothing between transactions. Any funds or vaults owned
/// by it may very well be extractable. The security comes from the fact that
/// after any interaction, the user (re-)obtains ownership of their assets. In
/// `doInvest`, this happens by transferring the vault at the end. In `unwind`
/// the contract can actually take ownership of a vault, but only when called
/// by the owner of the vault in the first place.

pragma solidity ^0.8.13;

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

struct Debt {
    uint96 max; // Maximum debt accepted for a given underlying, across all series
    uint24 min; // Minimum debt accepted for a given underlying, across all series
    uint8 dec; // Multiplying factor (10**dec) for max and min
    uint128 sum; // Current debt for a given underlying, across all series
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

interface yVault is IERC20 {
  function deposit(uint amount, address to) external returns (uint256);
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
  function debt(bytes6 baseId, bytes6 ilkId) external view returns (Debt memory);
  function debtToBase(bytes6 seriesId, uint128 art)
        external
        returns (uint128 base);
  function give(bytes12 vaultId, address receiver)
        external
        returns(Vault memory vault);
  event VaultGiven(bytes12 indexed vaultId, address indexed receiver);
}

contract YieldLever {
  yVault constant yvUSDC = yVault(0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE);
  bytes6 constant ilkId = bytes6(0x303900000000); // for yvUSDC
  IToken constant iUSDC = IToken(0x32E4c68B3A4a813b710595AebA7f6B7604Ab9c15); 
  IERC20 constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  address constant usdcJoin = address(0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4);
  YieldLadle constant ladle = YieldLadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
  address constant yvUSDCJoin = address(0x403ae7384E89b086Ea2935d5fAFed07465242B38);
  Cauldron constant cauldron = Cauldron(0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867);

  bytes6 constant usdcId = bytes6(bytes32("02"));

  /// @dev YieldLever is not expected to hold any USDC
  constructor() {
    usdc.approve(address(yvUSDC), type(uint256).max);
  }

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
  /// @return vauldId - The ID of the created vault.
   function invest(
    uint256 baseAmount,
    uint128 borrowAmount,
    uint128 maxFyAmount,
    bytes6 seriesId
  ) external returns (bytes12) {
    // Check that it is a USDC series.
    require(cauldron.series(seriesId).baseId == usdcId);

    // Take USDC from the msg sender. We know USDC reverts on failure.
    // In future iterations, YieldLever can integrate with the Ladle by using
    // USDC it received previously in the same transaction, if available.
    usdc.transferFrom(msg.sender, address(this), baseAmount);
    // Build a Yield Vault
    (bytes12 vaultId, ) = ladle.build(seriesId, ilkId, 0);

    uint256 investAmount = baseAmount + borrowAmount;

    // Flash borrow USDC
    iUSDC.flashBorrow(
        borrowAmount,
        address(this),
        address(this),
        "",
        abi.encodeWithSignature(
          "doInvest(uint256,uint128,uint128,bytes12)",
          investAmount,
          borrowAmount,
          maxFyAmount,
          vaultId
        )
    );
    
    // Finally, give the vault to the sender
    cauldron.give(vaultId, msg.sender);

    return vaultId;
  }

  /// @notice This function is called inside the flash loan and handles the
  ///   actual investment.
  /// @param borrowAmount - The amount borrowed using a flash loan.
  /// @param maxFyAmount - The maximum amount of fyTokens to sell.
  /// @param vaultId - The vault id to invest in.
  /// @dev Calling this function outside a flash loan achieves nothing,
  ///   since the contract needs to have assets and own the vault it's borrowing from.
  function doInvest(
    uint256 investAmount,
    uint128 borrowAmount,
    uint128 maxFyAmount,
    bytes12 vaultId
  ) external {
    // Deposit USDC and obtain yvUSDC.
    // Send it to the yvUSDCJoin to use as collateral in the vault.
    // Returned is the amount of yvUSDC obtained.
    uint128 yvUSDCBalance = uint128(yvUSDC.deposit(investAmount, yvUSDCJoin));

    // Add collateral to the Yield vault.
    // Borrow enough to repay the flash loan.
    // Transfer it to `address(iUSDC)` to repay the loan.
    ladle.serve(vaultId, address(iUSDC), yvUSDCBalance, borrowAmount, maxFyAmount);
  }

  /// @notice Empty a vault.
  /// @param vaultId - The id of the vault that should be emptied.
  /// @param maxAmount - The maximum amount of USDC to borrow. If past
  ///   maturity, this parameter is unused as the amount can be determined
  ///   precisely.
  /// @param pool - The pool to deposit USDC into. This can be obtained via the
  ///   seriesId, and calling `address pool = ladle.pools(seriesId);`
  /// @param ink - The amount of collateral in the vault. Together with art,
  ///   this value can be obtained using `cauldron.balances(vaultId);`, which
  ///   will return an object containing both `art` and `ink`.
  /// @param art - The amount of debt taken from the vault.
  function unwind(bytes12 vaultId, uint256 maxAmount, address pool, uint128 ink, uint128 art, bytes6 seriesId) external {
    Vault memory vault_ = cauldron.vaults(vaultId);
    Series memory series_ = cauldron.series(seriesId);
    
    // Test that the caller is the owner of the vault.
    // This is important as we will take the vault from the user.
    require(vault_.owner == msg.sender);

    // Give the vault to the contract
    cauldron.give(vaultId, address(this));
  
    if (uint32(block.timestamp) < series_.maturity) {
      // Series is not past maturity
      // Borrow to repay debt, move directly to the pool.
      iUSDC.flashBorrow(
        maxAmount,
        pool,
        address(this),
        "",
        abi.encodeWithSignature("doRepay(address,bytes12,uint256,uint128)", msg.sender, vaultId, maxAmount, ink)
      );
    } else {
      // Series is past maturity, borrow and move directly to collateral pool
      uint128 base = cauldron.debtToBase(seriesId, art);
      iUSDC.flashBorrow(
        base,
        usdcJoin,
        address(this),
        "",
        abi.encodeWithSignature("doClose(address,bytes12,uint128,uint128,uint128)", msg.sender, vaultId, base, ink, art)
      );
    }

    // Give the vault back to the sender, just in case there is anything left
    cauldron.give(vaultId, msg.sender);
  }

  /// @notice Repay a vault after having borrowed a suitable amount using a
  ///   flash loan. Will only succeed if the pool hasn't reached its expiration
  ///   date yet.
  /// @param owner - The address of the owner. This is the address that will be
  ///   used to obtain certain parameters, and it is also the destination for
  ///   the profit that was obtained.
  /// @param vaultId - The vault id to repay.
  /// @dev Calling this function outside a flash loan achieves nothing, since
  ///   the contract needs to own the vault it's getting collateral from.
  function doRepay(address owner, bytes12 vaultId, uint256 borrowAmount, uint128 ink) external {
    // Repay Yield vault debt
    ladle.repayVault(vaultId, address(this), -int128(ink), uint128(borrowAmount));

    // withdraw from yvUSDC
    yvUSDC.withdraw();
    // Repay the flash loan
    usdc.transfer(address(iUSDC), borrowAmount);
    // Send the remaining USDC balance to the user.
    usdc.transfer(owner, usdc.balanceOf(address(this)));
  }

  /// @notice Close a vault that has already reached its expiration date.
  /// @param owner - The address of the owner. This is the address that will be
  ///   used to obtain certain parameters, and it is also the destination for
  ///   the profit that was obtained.
  /// @param vaultId - The vault id to repay.
  /// @param base - The size of the debt in USDC.
  /// @dev Calling this function outside a flash loan achieves nothing, since
  ///   the contract needs to own the vault it's getting collateral from.
  function doClose(address owner, bytes12 vaultId, uint128 base, uint128 ink, uint128 art) external {
    // Close the vault
    ladle.close(vaultId, address(this), -int128(ink), -int128(art));

    // Withdraw from yvUSDC
    yvUSDC.withdraw();
    // Repay flash loan
    usdc.transfer(address(iUSDC), base);
    // Send the remainder to user
    usdc.transfer(owner, usdc.balanceOf(address(this)));
  }
}
