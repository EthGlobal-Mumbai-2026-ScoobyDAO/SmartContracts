// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IERC20, SafeToken, Guard} from "../Utils.sol";
import {ReportRegistry} from "../ReportRegistry.sol";
import {YieldVaultAdapter} from "./YieldVaultAdapter.sol";
import {PrincipalToken} from "./PrincipalToken.sol";
import {YieldToken} from "./YieldToken.sol";

contract YieldSplitter is Guard {
    using SafeToken for IERC20;
    IERC20 public immutable usdc;
    ReportRegistry public immutable registry;
    address public immutable market;
    address public immutable settlement;
    address public immutable treasury;
    address public immutable owner;
    YieldVaultAdapter public vault;
    PrincipalToken public immutable principalToken;
    mapping(uint256 => YieldToken) public yieldToken;
    mapping(uint256 => uint256) public notional;
    mapping(uint256 => uint256) public principalAvailable;
    mapping(uint256 => bool) public prepared;
    uint256 public activeReportId;
    event Locked(uint256 indexed reportId, uint256 principal, address yieldToken);
    event YieldCheckpoint(uint256 indexed reportId, uint256 amount);
    event PrincipalPrepared(uint256 indexed reportId, uint256 available);
    constructor(IERC20 usdc_, ReportRegistry registry_, address market_, address settlement_, address treasury_) {
        require(address(usdc_) != address(0) && market_ != address(0) && settlement_ != address(0) && treasury_ != address(0));
        owner = msg.sender; usdc = usdc_; registry = registry_; market = market_; settlement = settlement_; treasury = treasury_;
        principalToken = new PrincipalToken(address(this));
    }
    function configureVault(YieldVaultAdapter vault_) external {
        require(msg.sender == owner && address(vault) == address(0), "CONFIGURED");
        require(address(vault_.asset()) == address(usdc) && vault_.splitter() == address(this), "VAULT");
        vault = vault_;
    }
    function lock(uint256 id, uint256 amount) external nonReentrant {
        require(msg.sender == market && address(vault) != address(0), "MARKET_OR_VAULT");
        ReportRegistry.Report memory r = registry.getReport(id);
        require(r.lockTime != 0 && block.timestamp >= r.lockTime && block.timestamp < uint256(r.lockTime) + 30 days, "LOCK_TIME");
        require(activeReportId == 0 && notional[id] == 0 && amount > 0, "ONE_SERIES_ONLY");
        uint256 beforeBalance = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        require(usdc.balanceOf(address(this)) - beforeBalance == amount, "TOKEN_DELTA");
        notional[id] = amount;
        activeReportId = id;
        YieldToken yt = new YieldToken(usdc, address(this), "RiskFi Yield Token", "RF-YT");
        yieldToken[id] = yt;
        principalToken.mint(settlement, id, amount);
        yt.mint(treasury, amount);
        usdc.safeApprove(address(vault), amount);
        vault.deposit(amount);
        emit Locked(id, amount, address(yt));
    }
    function checkpointYield(uint256 id) public nonReentrant returns (uint256 amount) {
        require(notional[id] != 0 && !prepared[id], "SERIES");
        amount = vault.positiveYield();
        if (amount > 0) {
            YieldToken yt = yieldToken[id];
            vault.withdraw(address(yt), amount, false);
            yt.notifyYield(amount);
            emit YieldCheckpoint(id, amount);
        }
    }
    function preparePrincipal(uint256 id) external nonReentrant returns (uint256 available) {
        require(msg.sender == market && notional[id] != 0 && !prepared[id], "PREPARE");
        require(block.timestamp >= registry.maturity(id), "MATURITY");
        uint256 surplus = vault.positiveYield();
        if (surplus > 0) {
            YieldToken yt = yieldToken[id];
            vault.withdraw(address(yt), surplus, false);
            yt.notifyYield(surplus);
            emit YieldCheckpoint(id, surplus);
        }
        yieldToken[id].mature();
        available = vault.totalAssets();
        if (available > notional[id]) available = notional[id];
        prepared[id] = true;
        principalAvailable[id] = available;
        principalToken.burn(settlement, id, notional[id]);
        if (available > 0) vault.withdraw(market, available, true);
        if (notional[id] > available) vault.closePrincipal(notional[id] - available);
        emit PrincipalPrepared(id, available);
    }
}
