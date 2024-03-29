// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../interfaces/Types.sol";
import "../interfaces/IOracleMaster.sol";
import "../interfaces/IPushable.sol";
import "./utils/ReportUtils.sol";

contract Oracle is Initializable {
    using ReportUtils for uint256;

    event Completed(uint256);

    // Current era report  hashes
    uint256[] internal currentReportVariants;

    // Current era reports
    Types.OracleData[] private currentReports;

    // Then oracle member push report, its bit is set
    uint256 internal currentReportBitmask;

    // inactivity cover contract address
    address payable[] public PUSHABLES;
    // oracle master contract address
    address public ORACLE_MASTER;

    // current part of the current era
    uint128 public eraNonce;

    // Allows function calls only from OracleMaster
    modifier onlyOracleMaster() {
        require(msg.sender == ORACLE_MASTER);
        _;
    }

    /**
     * @notice Initialize oracle contract
     * @param _oracleMaster oracle master address
     */
    function initialize(address _oracleMaster, address payable _pushable)
        external
        initializer
    {
        require(ORACLE_MASTER == address(0), "OR: ALREADY_INITIALIZED");
        ORACLE_MASTER = _oracleMaster;
        PUSHABLES.push(_pushable);
    }

    /**
     * @notice Returns true if member is already reported
     * @param _index oracle member index
     * @return is reported indicator
     */
    function isReported(uint256 _index) external view returns (bool) {
        return (currentReportBitmask & (1 << _index)) != 0;
    }

    /**
     * @notice Accept oracle report data, allowed to call only by oracle master contract
     * @param _index oracle member index
     * @param _quorum the minimum number of voted oracle members to accept a variant
     * @param _eraId current era id
     * @param _staking report data
     */
    function reportPara(
        uint256 _index,
        uint256 _quorum,
        uint128 _eraId,
        uint128 _eraNonce,
        Types.OracleData calldata _staking,
        address oracle
    ) external onlyOracleMaster {
        {
            uint256 mask = 1 << _index;
            uint256 reportBitmask = currentReportBitmask;
            require(reportBitmask & mask == 0, "OR: ALREADY_SUBMITTED");
            currentReportBitmask = (reportBitmask | mask);
            require(_eraNonce == eraNonce, "OR: INV_NONCE");
        }

        // convert staking report into 31 byte hash. The last byte is used for vote counting
        uint256 variant = uint256(keccak256(abi.encode(_staking))) &
            ReportUtils.COUNT_OUTMASK;

        uint256 i = 0;
        uint256 _length = currentReportVariants.length;
        // iterate on all report variants we already have, limited by the oracle members maximum
        while (i < _length && currentReportVariants[i].isDifferent(variant))
            ++i;
        if (i < _length) {
            if (currentReportVariants[i].getCount() + 1 >= _quorum) {
                _push(_eraId, _staking, oracle);
            } else {
                ++currentReportVariants[i];
                // increment variant counter, see ReportUtils for details
            }
        } else {
            if (_quorum == 1) {
                _push(_eraId, _staking, oracle);
            } else {
                currentReportVariants.push(variant + 1);
                currentReports.push(_staking);
            }
        }
    }

    /**
    * @notice Change quorum threshold, allowed to call only by oracle master contract
    * @dev Method can trigger to pushing data to ledger if quorum threshold decreased and
           now for contract already reached new threshold.
    * @param _quorum new quorum threshold
    * @param _eraId current era id
    */
    function softenQuorum(uint8 _quorum, uint128 _eraId)
        external
        onlyOracleMaster
    {
        (bool isQuorum, uint256 reportIndex) = _getQuorumReport(_quorum);
        if (isQuorum) {
            Types.OracleData memory report = _getStakeReport(reportIndex);
            _push(_eraId, report, address(0)); // pushing the zero address will deactivate gas cost refund
        }
    }

    /**
     * @notice Clear data about current reporting, allowed to call only by oracle master contract
     */
    function clearReporting() external onlyOracleMaster {
        _clearReporting();
    }

    function addRemovePushable(address payable _pushable, bool _toAdd)
        external
        onlyOracleMaster
    {
        if (_toAdd) {
            PUSHABLES.push(_pushable);
        } else {
            for (uint256 i = 0; i < PUSHABLES.length; i++) {
                if (PUSHABLES[i] == _pushable) {
                    delete PUSHABLES[i];
                }
            }
        }
    }

    /**
     * @notice Returns report by given index
     * @param _index oracle member index
     * @return staking report data
     */
    function _getStakeReport(uint256 _index)
        internal
        view
        returns (Types.OracleData storage staking)
    {
        assert(_index < currentReports.length);
        return currentReports[_index];
    }

    /**
     * @notice Clear data about current reporting
     */
    function _clearReporting() internal {
        currentReportBitmask = 0;
        delete currentReportVariants;
        delete currentReports;
        eraNonce++;
    }

    /**
     * @notice Push data to all pushable contracts
     */
    function _push(uint128 _eraId, Types.OracleData memory report, address oracle) internal {
        for (uint256 i = 0; i < PUSHABLES.length; i++) {
            if (PUSHABLES[i] == address(0)) {
                continue;
            }
            IPushable(PUSHABLES[i]).pushData(_eraId, report, oracle);
        }
        _clearReporting();
    }

    /**
     * @notice Return whether the `_quorum` is reached and the final report can be pushed
     */
    function _getQuorumReport(uint256 _quorum)
        internal
        view
        returns (bool, uint256)
    {
        // check most frequent cases first: all reports are the same or no reports yet
        uint256 _length = currentReportVariants.length;
        if (_length == 1) {
            return (currentReportVariants[0].getCount() >= _quorum, 0);
        } else if (_length == 0) {
            return (false, type(uint256).max);
        }

        // if more than 2 kind of reports exist, choose the most frequent
        uint256 maxind = 0;
        uint256 repeat = 0;
        uint16 maxval = 0;
        uint16 cur = 0;
        for (uint256 i = 0; i < _length; ++i) {
            cur = currentReportVariants[i].getCount();
            if (cur >= maxval) {
                if (cur == maxval) {
                    ++repeat;
                } else {
                    maxind = i;
                    maxval = cur;
                    repeat = 0;
                }
            }
        }
        return (maxval >= _quorum && repeat == 0, maxind);
    }
}
