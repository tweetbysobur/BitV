// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseModule } from "./BaseModule.sol";
import { ITreasury } from "../interfaces/ITreasury.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title Treasury
/// @notice Protocol fee sink and reserve manager. See `ITreasury` for why
///         this is the single fee/reserve destination for every module.
/// @custom:storage-location erc7201:bitv.storage.Treasury
contract Treasury is BaseModule, ITreasury {
    using SafeERC20 for IERC20;

    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");
    bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR_ROLE");

    struct TreasuryStorage {
        mapping(address asset => uint256 balance) reserves;
    }

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("bitv.storage.Treasury")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0xfdb6721e8a11384a6b091cf911ae14962ff0a509e38b6567c172840818240d00;

    function _s() private pure returns (TreasuryStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address registry_, address admin) external initializer {
        __BaseModule_init(registry_, admin);
        _grantRole(TREASURER_ROLE, admin);
    }

    // ── ITreasury ────────────────────────────────────────────────────────

    /// @dev Restricted to `FEE_COLLECTOR_ROLE` — granted only to BitV's own
    ///      manager contracts (PoolManager, LendingManager, VaultManager) by
    ///      governance during deployment wiring, never to an EOA. Anyone
    ///      else calling this would be pulling tokens out of their OWN
    ///      balance into the treasury for no benefit, which is harmless but
    ///      pointless; the role restriction exists so `FeeCollected`'s
    ///      `source` field is a trustworthy audit trail of which protocol
    ///      module actually generated each fee, not spoofable by an
    ///      arbitrary caller emitting the event with a fabricated source.
    function collectFee(address asset, uint256 amount) external onlyRole(FEE_COLLECTOR_ROLE) {
        if (amount == 0) revert Errors.ZeroAmount();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        _s().reserves[asset] += amount;

        emit FeeCollected(asset, msg.sender, amount);
    }

    function notifyLiquidationProceeds(address asset, uint256 amount)
        external
        onlyRole(FEE_COLLECTOR_ROLE)
    {
        if (amount == 0) revert Errors.ZeroAmount();

        // The caller has already transferred `asset` in directly (see
        // `ITreasury.notifyLiquidationProceeds`); this only reconciles
        // internal accounting against the token contract's actual balance
        // rather than blindly trusting the caller's stated `amount`. A
        // mismatch here would mean either a bug in the caller's transfer or,
        // in the worst case, a compromised caller reporting proceeds it
        // never actually sent.
        uint256 actualBalance = IERC20(asset).balanceOf(address(this));
        uint256 accounted = _s().reserves[asset];
        uint256 unaccounted = actualBalance > accounted ? actualBalance - accounted : 0;
        uint256 credited = amount < unaccounted ? amount : unaccounted;

        _s().reserves[asset] += credited;

        emit LiquidationProceedsReceived(asset, credited);
    }

    function withdrawReserve(address asset, address to, uint256 amount)
        external
        onlyRole(TREASURER_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (to == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.ZeroAmount();

        uint256 balance = _s().reserves[asset];
        if (amount > balance) revert Errors.AmountExceedsBalance(amount, balance);

        _s().reserves[asset] = balance - amount;
        IERC20(asset).safeTransfer(to, amount);

        emit ReserveWithdrawn(asset, to, amount, msg.sender);
    }

    function reserveBalance(address asset) external view returns (uint256) {
        return _s().reserves[asset];
    }
}
