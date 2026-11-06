// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IERC20, SafeToken, Guard} from "../Utils.sol";
import {YieldToken} from "../yield/YieldToken.sol";
import {YieldLPShare} from "./YieldLPShare.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

// One hook-owned YT/USDC constant-product market. The v4 PoolManager is the
// swap entry point and flash-accounting engine; this hook owns reserves and
// YT accrual. Pools with ordinary v4 liquidity are explicitly rejected.
contract YieldMarketHook is Guard {
    using SafeToken for IERC20;
    uint160 public constant REQUIRED_FLAGS =
        Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG;
    uint256 private constant FEE_DENOMINATOR = 1_000_000;
    IPoolManager public immutable manager;
    IERC20 public immutable usdc;
    YieldToken public immutable yt;
    YieldLPShare public shares;
    address public immutable owner;
    uint64 public immutable maturity;
    uint24 public immutable feePips;
    bytes32 public poolKeyHash;
    uint256 public usdcReserve;
    uint256 public ytReserve;
    uint256 public lpYieldPerShare;
    uint256 public lpYieldReserved;
    mapping(address => uint256) public paidLPIndex;
    mapping(address => uint256) public unclaimedLPYield;
    event PoolConfigured(bytes32 keyHash);
    event LiquidityAdded(address indexed provider, uint256 usdcAmount, uint256 ytAmount, uint256 shares);
    event LiquidityRemoved(address indexed provider, uint256 usdcAmount, uint256 ytAmount, uint256 shares);
    event Swapped(bool usdcIn, uint256 amountIn, uint256 amountOut);

    constructor(IPoolManager manager_, IERC20 usdc_, YieldToken yt_, uint64 maturity_, uint24 feePips_) {
        require(
            address(manager_) != address(0) && address(usdc_) != address(0) && address(yt_) != address(0), "ADDRESS"
        );
        require(address(yt_.usdc()) == address(usdc_) && maturity_ > block.timestamp && feePips_ <= 10_000, "SERIES");
        manager = manager_;
        usdc = usdc_;
        yt = yt_;
        maturity = maturity_;
        feePips = feePips_;
        owner = msg.sender;
    }

    function configurePool(PoolKey calldata key) external {
        require(msg.sender == owner && poolKeyHash == 0, "CONFIGURED");
        require(uint160(address(this)) & Hooks.ALL_HOOK_MASK == REQUIRED_FLAGS, "HOOK_FLAGS");
        require(address(key.hooks) == address(this) && key.fee == 0 && key.tickSpacing == 1, "POOL_KEY");
        address c0 = Currency.unwrap(key.currency0);
        address c1 = Currency.unwrap(key.currency1);
        require(
            c0 < c1 && ((c0 == address(usdc) && c1 == address(yt)) || (c0 == address(yt) && c1 == address(usdc))),
            "TOKENS"
        );
        poolKeyHash = keccak256(abi.encode(key));
        shares = new YieldLPShare(address(this));
        emit PoolConfigured(poolKeyHash);
    }

    function _checkpointGlobal() internal {
        uint256 earned = yt.claimYield();
        if (earned == 0) return;
        uint256 supply = shares.totalSupply();
        require(supply > 0, "UNOWNED_YIELD");
        lpYieldReserved += earned;
        lpYieldPerShare += earned * 1e18 / supply;
    }

    function _checkpointAccount(address account) internal {
        if (account == address(0)) return;
        uint256 delta = lpYieldPerShare - paidLPIndex[account];
        if (delta > 0) unclaimedLPYield[account] += shares.balanceOf(account) * delta / 1e18;
        paidLPIndex[account] = lpYieldPerShare;
    }

    function beforeShareTransfer(address from, address to) external {
        require(msg.sender == address(shares), "SHARES");
        _checkpointGlobal();
        _checkpointAccount(from);
        _checkpointAccount(to);
    }

    function addLiquidity(uint256 usdcAmount, uint256 ytAmount, uint256 minShares)
        external
        nonReentrant
        returns (uint256 minted)
    {
        require(poolKeyHash != 0 && block.timestamp < maturity && usdcAmount > 0 && ytAmount > 0, "LIQUIDITY");
        _checkpointGlobal();
        _checkpointAccount(msg.sender);
        uint256 supply = shares.totalSupply();
        if (supply == 0) {
            minted = _sqrt(usdcAmount * ytAmount);
        } else {
            uint256 byUSDC = usdcAmount * supply / usdcReserve;
            uint256 byYT = ytAmount * supply / ytReserve;
            require(byUSDC == byYT, "RATIO");
            minted = byUSDC;
        }
        require(minted >= minShares && minted > 0, "MIN_SHARES");
        uint256 beforeUSDC = usdc.balanceOf(address(this));
        uint256 beforeYT = yt.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        require(usdc.balanceOf(address(this)) - beforeUSDC == usdcAmount, "USDC_DELTA");
        require(yt.transferFrom(msg.sender, address(this), ytAmount), "YT_TRANSFER");
        require(yt.balanceOf(address(this)) - beforeYT == ytAmount, "YT_DELTA");
        usdcReserve += usdcAmount;
        ytReserve += ytAmount;
        shares.mint(msg.sender, minted);
        emit LiquidityAdded(msg.sender, usdcAmount, ytAmount, minted);
    }

    function removeLiquidity(uint256 shareAmount, uint256 minUSDC, uint256 minYT)
        external
        nonReentrant
        returns (uint256 usdcOut, uint256 ytOut)
    {
        require(shareAmount > 0, "SHARES");
        _checkpointGlobal();
        _checkpointAccount(msg.sender);
        uint256 supply = shares.totalSupply();
        usdcOut = usdcReserve * shareAmount / supply;
        ytOut = ytReserve * shareAmount / supply;
        require(usdcOut >= minUSDC && ytOut >= minYT, "MIN_OUT");
        shares.burn(msg.sender, shareAmount);
        usdcReserve -= usdcOut;
        ytReserve -= ytOut;
        usdc.safeTransfer(msg.sender, usdcOut);
        require(yt.transfer(msg.sender, ytOut), "YT_TRANSFER");
        emit LiquidityRemoved(msg.sender, usdcOut, ytOut, shareAmount);
    }

    function claimLPYield() external nonReentrant returns (uint256 amount) {
        _checkpointGlobal();
        _checkpointAccount(msg.sender);
        amount = unclaimedLPYield[msg.sender];
        unclaimedLPYield[msg.sender] = 0;
        lpYieldReserved -= amount;
        if (amount > 0) usdc.safeTransfer(msg.sender, amount);
    }

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        nonReentrant
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        require(msg.sender == address(manager) && poolKeyHash != 0 && keccak256(abi.encode(key)) == poolKeyHash, "POOL");
        require(block.timestamp < maturity && params.amountSpecified < 0, "EXACT_INPUT_OR_MATURED");
        require(hookData.length == 64, "HOOK_DATA");
        (uint256 minOut, uint64 deadline) = abi.decode(hookData, (uint256, uint64));
        require(block.timestamp <= deadline, "DEADLINE");
        uint256 amountIn = uint256(-params.amountSpecified);
        require(amountIn > 0 && amountIn <= uint256(uint128(type(int128).max)), "AMOUNT");
        _checkpointGlobal();
        bool usdcIn = Currency.unwrap(params.zeroForOne ? key.currency0 : key.currency1) == address(usdc);
        uint256 reserveIn = usdcIn ? usdcReserve : ytReserve;
        uint256 reserveOut = usdcIn ? ytReserve : usdcReserve;
        uint256 netIn = amountIn * (FEE_DENOMINATOR - feePips) / FEE_DENOMINATOR;
        uint256 amountOut = reserveOut * netIn / (reserveIn + netIn);
        require(
            amountOut >= minOut && amountOut > 0 && amountOut < reserveOut
                && amountOut <= uint256(uint128(type(int128).max)),
            "SWAP_LIMIT"
        );
        if (usdcIn) {
            usdcReserve += amountIn;
            ytReserve -= amountOut;
        } else {
            ytReserve += amountIn;
            usdcReserve -= amountOut;
        }
        Currency input = usdcIn ? Currency.wrap(address(usdc)) : Currency.wrap(address(yt));
        Currency output = usdcIn ? Currency.wrap(address(yt)) : Currency.wrap(address(usdc));
        manager.take(input, address(this), amountIn);
        manager.sync(output);
        if (usdcIn) require(yt.transfer(address(manager), amountOut), "YT_TRANSFER");
        else usdc.safeTransfer(address(manager), amountOut);
        manager.settle();
        emit Swapped(usdcIn, amountIn, amountOut);
        return (this.beforeSwap.selector, toBeforeSwapDelta(int128(uint128(amountIn)), -int128(uint128(amountOut))), 0);
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external view returns (bytes4, BalanceDelta) {
        require(msg.sender == address(manager), "MANAGER");
        revert("HOOK_OWNED_LIQUIDITY");
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
