// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;
pragma abicoder v2;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/IOracle.sol";
import "../interfaces/IAuthManager.sol";
import "../interfaces/ProxyInterface.sol";
import "../interfaces/StakingInterface.sol";

contract OracleMaster is Pausable, Initializable {
    using Clones for address;

    event MemberAdded(address member);
    event MemberRemoved(address member);
    event QuorumChanged(uint8 QUORUM);

    ParachainStaking public staking;
    Proxy public proxy;

    // current era id
    uint128 public eraId;

    // Oracle members
    address[] public members;

    // inactivity cover contract address
    address payable public INACTIVITY_COVER;
    // auth manager contract address
    address public AUTH_MANAGER;
    // oracle master contract
    address public ORACLE;

    // Quorum threshold
    uint8 public QUORUM;

    /// Maximum number of oracle committee members
    uint256 public constant MAX_MEMBERS = 200;

    // Missing member index
    uint256 internal constant MEMBER_N_FOUND = type(uint256).max;

    // General oracle manager role
    bytes32 internal constant ROLE_PAUSE_MANAGER =
        keccak256("ROLE_PAUSE_MANAGER");

    // Oracle members manager role
    bytes32 internal constant ROLE_ORACLE_MEMBERS_MANAGER =
        keccak256("ROLE_ORACLE_MEMBERS_MANAGER");

    // Oracle members manager role
    bytes32 internal constant ROLE_ORACLE_QUORUM_MANAGER =
        keccak256("ROLE_ORACLE_QUORUM_MANAGER");

    // Manager role
    bytes32 internal constant ROLE_MANAGER = keccak256("ROLE_MANAGER");

    // Collators to oracle representatives (each collator can have one oracle rep)
    mapping(address => address) public oreps;
    
    // Allows function calls only from member with specific role
    modifier auth(bytes32 role) {
        require(IAuthManager(AUTH_MANAGER).has(role, msg.sender), "OM: UNAUTH");
        _;
    }

    // Allows function calls only from INACTIVITY_COVER
    modifier onlyInactivityCover() {
        require(
            msg.sender == INACTIVITY_COVER,
            "OM: CALLER_N_INACTIVITY_COVER"
        );
        _;
    }

    /**
     * @notice Initialize oracle master contract, allowed to call only once
     * @param _quorum inital quorum threshold
     */
    function initialize(
        address _auth_manager,
        address _oracle,
        address payable _inactivity_cover,
        uint8 _quorum
    ) external initializer {
        require(ORACLE == address(0), "OM: ALREADY_INITIALIZED");
        require(_quorum > 0 && _quorum <= MAX_MEMBERS, "OM: INCORRECT_QUORUM");
        staking = ParachainStaking(0x0000000000000000000000000000000000000800);
        proxy = Proxy(0x000000000000000000000000000000000000080b);
        AUTH_MANAGER = _auth_manager;
        ORACLE = _oracle;
        INACTIVITY_COVER = _inactivity_cover;
        QUORUM = _quorum;
    }

    /**
    * @notice Set the number of exactly the same reports needed to finalize the era
              allowed to call only by ROLE_ORACLE_QUORUM_MANAGER
    * @param _quorum new value of quorum threshold
    */
    function setQuorum(uint8 _quorum)
        external
        auth(ROLE_ORACLE_QUORUM_MANAGER)
    {
        require(
            _quorum > 0 && _quorum < MAX_MEMBERS,
            "OM: QUORUM_WONT_BE_MADE"
        );
        uint8 oldQuorum = QUORUM;
        QUORUM = _quorum;

        // If the QUORUM value lowered, check existing reports whether it is time to push
        if (oldQuorum > _quorum) {
            IOracle(ORACLE).softenQuorum(_quorum, eraId);
        }
        emit QuorumChanged(_quorum);
    }

    /**
     * @notice Return oracle contract for the given ledger
     * @return linked oracle address
     */
    function getOracle() external view returns (address) {
        return ORACLE;
    }

    /**
     * @notice Return last reported era and oracle is already reported indicator
     * @param _oracleMember - oracle member address
     * @return lastEra - last reported era
     * @return lastPart - last reported era part
     * @return isReported - true if oracle member already reported for given stash, else false
     */
    function isReportedLastEra(address _oracleMember)
        external
        view
        returns (uint128 lastEra, uint128 lastPart, bool isReported)
    {
        lastEra = eraId;
        uint256 memberIdx = _getMemberId(_oracleMember);
        if (memberIdx == MEMBER_N_FOUND) {
            return (lastEra, lastPart, false);
        }
        return (lastEra, lastPart, IOracle(ORACLE).isReported(memberIdx));
    }

    /**
     * @notice Stop pool routine operations (reportRelay), allowed to call only by ROLE_PAUSE_MANAGER
     */
    function pause() external auth(ROLE_PAUSE_MANAGER) {
        _pause();
    }

    /**
     * @notice Resume pool routine operations (reportRelay), allowed to call only by ROLE_PAUSE_MANAGER
     */
    function resume() external auth(ROLE_PAUSE_MANAGER) {
        _unpause();
    }

    /**
     * @notice Each active collator can register one address with oracle privileges. The address must be a Governance proxy of the collator at the time of registration, to prove that it is owned by that collator.
     * @param _collator the collator that the caller represents (each collator can operate one oracle)
     */
    function registerAsOracleMember(address _collator)
        external
    {
        require(_getMemberId(msg.sender) == MEMBER_N_FOUND, "OM: MEMBER_EXISTS");
        require(members.length < MAX_MEMBERS, "OM: MEMBERS_TOO_MANY");
        require(isProxyOfSelectedCandidate(msg.sender, _collator), "OM: N_COLLATOR_PROXY");
        require(oreps[_collator] == address(0), "OM: ALREADY_REGISTERED"); // ensures that each collator can register one oracle only

        members.push(msg.sender);
        oreps[_collator] = msg.sender;
        emit MemberAdded(msg.sender);
    }

    /**
     * @notice Remove me from the oracle member committee list
     * @param _collatorRep the collator that the caller represents
     */
    function unregisterOracleMember(address _collatorRep)
        external
    {
        uint256 index = _getMemberId(msg.sender);
        require(index != MEMBER_N_FOUND, "OM: MEMBER_N_FOUND");
        require(oreps[_collatorRep] == msg.sender, "OM: N_COLLATOR");
        uint256 last = members.length - 1;
        if (index != last) members[index] = members[last];
        members.pop();

        delete oreps[_collatorRep];

        emit MemberRemoved(msg.sender);
        // delete the data for the last eraId, let remained oracles report it again
        // _clearReporting();
    }

    /**
     * @notice Add new member to the oracle member committee list, allowed to call only by ROLE_ORACLE_MEMBERS_MANAGER
     * @param _member proposed member address
     */
    function addOracleMember(address _member)
        external
        auth(ROLE_ORACLE_MEMBERS_MANAGER)
    {
        require(_member != address(0), "OM: BAD_ARGUMENT");
        require(_getMemberId(_member) == MEMBER_N_FOUND, "OM: MEMBER_EXISTS");
        require(members.length < MAX_MEMBERS, "OM: MEMBERS_TOO_MANY");

        members.push(_member);
        emit MemberAdded(_member);
    }

    /**
     * @notice Remove `_member` from the oracle member committee list, allowed to call only by ROLE_ORACLE_MEMBERS_MANAGER
     */
    function removeOracleMember(address _member)
        external
        auth(ROLE_ORACLE_MEMBERS_MANAGER)
    {
        uint256 index = _getMemberId(_member);
        require(index != MEMBER_N_FOUND, "OM: MEMBER_N_FOUND");
        uint256 last = members.length - 1;
        if (index != last) members[index] = members[last];
        members.pop();
        emit MemberRemoved(_member);

        // delete the data for the last eraId, let remained oracles report it again
        _clearReporting();
    }

    /**
     * @notice Accept oracle committee member reports from the relay side
     * @param _eraId relaychain era
     * @param _eraNonce era nonce
     * @param _report relaychain data report
     */
    function reportRelay(uint128 _eraId, uint128 _eraNonce, Types.OracleData calldata _report)
        external
        whenNotPaused
    {
        require(_isConsistent(_report), "OM: INCORRECT_REPORT");
        uint256 memberIndex = _getMemberId(msg.sender);
        require(memberIndex != MEMBER_N_FOUND, "OM: MEMBER_N_FOUND");
        require(ORACLE != address(0), "OM: ORACLE_N_FOUND");
        require(_eraId >= eraId, "OM: ERA_TOO_OLD");

        // The report will revert (InactivityCover contract) if the reported era is not the last completed era.
        // Thus, the security that the correct era is being reported is provided by InactivityCover.
        // The folllowing check is just for efficiency.
        if (_eraId > eraId) {
            eraId = _eraId;
            // _clearReporting(); // there can be multiple reports per era
        }
        IOracle(ORACLE).reportRelay(memberIndex, QUORUM, _eraId, _eraNonce,  _report, msg.sender);
    }

    function addRemovePushable(address payable _pushable, bool _toAdd)
        external
        auth(ROLE_ORACLE_MEMBERS_MANAGER)
    {
        IOracle(ORACLE).addRemovePushable(_pushable, _toAdd);
    }

    /// @notice Return true if report is consistent
    function _isConsistent(Types.OracleData memory report)
        internal
        pure
        returns (bool)
    {
        uint256 collatorsWithZeroPoints = 0;
        for (uint256 i = 0; i < report.collators.length; i++) {
            if (report.collators[i].points == 0) {
                collatorsWithZeroPoints++;
            }
        }
        return
            (report.collators.length < 5 || collatorsWithZeroPoints < (report.collators.length * 2) / 3) &&
            report.round > 0 &&
            report.totalStaked > 0 &&
            report.totalSelected > 0 &&
            report.awarded > 0 &&
            report.blockNumber > 0 &&
            report.collators.length > 0;
    }

    /**
     * @notice Return oracle instance index in the member array
     * @param _member member address
     * @return member index
     */
    function _getMemberId(address _member) internal view returns (uint256) {
        uint256 length = members.length;
        for (uint256 i = 0; i < length; ++i) {
            if (members[i] == _member) {
                return i;
            }
        }
        return MEMBER_N_FOUND;
    }

    /**
     * @notice Delete interim data for current Era, free storage memory for each oracle
     */
    function _clearReporting() internal {
        IOracle(ORACLE).clearReporting();
    }

    function isProxyOfSelectedCandidate(address _oracle, address _collator) public virtual view returns(bool) {
        bool isCollator = staking.isSelectedCandidate(_collator);
        bool isProxy = proxy.isProxy(_collator, _oracle, Proxy.ProxyType.Governance, 0);
        return isCollator && isProxy;
    }
}
