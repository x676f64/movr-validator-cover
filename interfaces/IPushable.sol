// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Types.sol";

interface IPushable {

    function pushData(uint64 _eraId, Types.OracleData calldata _report) external;

}