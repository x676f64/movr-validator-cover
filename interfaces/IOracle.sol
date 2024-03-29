// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Types.sol";

interface IOracle {
    function initialize(address oracleMaster, address payable _pushable, uint128 _eraId) external;

    function reportPara(uint256 index, uint256 quorum, uint128 eraId, uint128 _eraNonce, Types.OracleData calldata staking, address oracle) external;

    function softenQuorum(uint8 quorum, uint128 _eraId) external;

    function clearReporting() external;

    function isReported(uint256 index) external view returns (bool);

    function setInactivityCover(address _inactivity_cover) external;

    function addRemovePushable(address payable _pushable, bool _toAdd) external;
}