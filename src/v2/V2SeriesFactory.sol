// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "../Utils.sol";
import {ReportRegistry} from "../ReportRegistry.sol";
import {RiskFiStakeVaultV2} from "./RiskFiStakeVaultV2.sol";

/// @notice One fresh vault and YT per published report, in either existing registry.
contract V2SeriesFactory {
    struct Series {
        address vault;
        address yt;
        address rep;
    }
    IERC20 public immutable usd;
    address public immutable originalRegistry;
    address public immutable flexibleRegistry;
    mapping(bytes32 => Series) private series;
    event SeriesPrepared(address indexed registry, uint256 indexed reportId, address vault, address yt, address rep);

    constructor(IERC20 usd_, address originalRegistry_, address flexibleRegistry_) {
        require(
            address(usd_) != address(0) && originalRegistry_ != address(0) && flexibleRegistry_ != address(0), "ADDRESS"
        );
        usd = usd_;
        originalRegistry = originalRegistry_;
        flexibleRegistry = flexibleRegistry_;
    }

    function key(address registry, uint256 reportId) public pure returns (bytes32) {
        return keccak256(abi.encode(registry, reportId));
    }

    function getSeries(address registry, uint256 reportId) external view returns (Series memory) {
        return series[key(registry, reportId)];
    }

    function prepare(address registry, uint256 reportId, address treasury)
        external
        returns (address vault, address yt)
    {
        require(registry == originalRegistry || registry == flexibleRegistry, "REGISTRY");
        require(msg.sender == ReportRegistry(registry).publisher() && treasury != address(0), "PUBLISHER");
        require(reportId != 0 && ReportRegistry(registry).getReport(reportId).lockTime > block.timestamp, "REPORT");
        bytes32 k = key(registry, reportId);
        require(series[k].vault == address(0), "PREPARED");
        RiskFiStakeVaultV2 v = new RiskFiStakeVaultV2(usd, ReportRegistry(registry), msg.sender, treasury);
        v.initializeSeries(reportId);
        vault = address(v);
        yt = address(v.yt());
        series[k] = Series(vault, yt, address(v.rep()));
        emit SeriesPrepared(registry, reportId, vault, yt, address(v.rep()));
    }
}
