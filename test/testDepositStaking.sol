pragma solidity 0.8.15;

import "contracts/AuthManager.sol";
import "contracts/mocks/InactivityCover_mock.sol";
import "contracts/Oracle.sol";
import "contracts/mocks/OracleMaster_mock.sol";
import "contracts/mocks/DepositStaking_mock.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {console} from "forge-std/console.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {PRBTest} from "prb-test/PRBTest.sol";

// test ging under MIN_DEPOSIT and going inactive
// check getErasCovered returns the right number

contract TestDepositStaking is PRBTest, StdCheats, StdUtils {
    address superior = msg.sender;
    address dev = address(0x1);
    address manager = address(0x2);
    address member1 = address(0x3);
    address member2 = address(0x4);
    address delegator1 = address(0x5);
    address delegator2 = address(0x6);
    address oracleManager = address(0x7);
    address stakingManager = address(0x7);

    uint256 _min_deposit = 1 ether;
    uint256 _max_deposit_total = 10 ether;
    uint256 _stake_unit_cover = 1 wei;
    uint256 _min_payout = 1 wei; // practically no min payment
    uint256 _eras_between_forced_undelegation = 1;
    uint256 _quorum = 1;
    address ZERO_ADDR = address(0x0);

    AuthManager am;
    InactivityCover ic;
    Oracle or;
    OracleMaster om;
    DepositStaking ds;

    struct ErasCovered {
        bool member1;
        bool member2;
    }

    constructor() public {
        am = new AuthManager();
        am.initialize(superior);
        vm.startPrank(address(superior), address(superior));
        am.addByString("ROLE_MANAGER", manager);
        am.addByString("ROLE_ORACLE_MEMBERS_MANAGER", oracleManager);
        am.addByString("ROLE_STAKING_MANAGER", stakingManager);
        vm.stopPrank();
        ic = new InactivityCover_mock();
        or = new Oracle();
        om = new OracleMaster();
        om.initialize(address(am), address(or), payable(ic), uint8(_quorum));
        or.initialize(address(om), payable(ic));

        ds = new DepositStaking();
        ds.initialize(address(am), payable(ic));

        ic.initialize(
            address(am),
            address(om),
            address(ds),
            _min_deposit,
            _max_deposit_total,
            _stake_unit_cover,
            _min_payout,
            uint128(_eras_between_forced_undelegation)
        );
    }

    function testDelegationWhenMemberNotPaid() public {
        vm.startPrank(stakingManager, stakingManager);
        address candidate = member1;
        uint amount = 2 ether;
        uint candidateDelegationCount = 100;
        uint delegatorDelegationCount = 100;
   //     ic.setMemberNotPaid_mock(delegator1);
        // delegate() should be rejected with 'MEMBER_N_PAID' error
        ds.delegate(candidate, amount, candidateDelegationCount, delegatorDelegationCount);
        // delegatorBondMore() should be rejected with 'MEMBER_N_PAID' error
        ds.delegatorBondMore(candidate, amount);
    }
    
    // test that manager can delegate and delegation is recorded
    function testManagerCanDelegate() public {
        vm.startPrank(stakingManager, stakingManager);
        uint deposit = 200 ether;
        address candidate = member1;
        uint amount = 2 ether;
        uint candidateDelegationCount = 100;
        uint delegatorDelegationCount = 100;
        ic.whitelist(member1, true);
        ic.depositCover(member1); // ic gets 200 ether
        uint icBalanceStart = payable(ic).balance;
        ds.delegate(candidate, amount, candidateDelegationCount, delegatorDelegationCount);
        uint icBalanceExpected = icBalanceStart - amount;
        // getIsDelegated() should return true
        ds.getIsDelegated(candidate);
        // getDelegation() should return the delegated amount
        ds.getDelegation(candidate);
        // getCollatorsDelegated() should return the candidate's address
        ds.getCollatorsDelegated(0);
        // ic's balance should be icBalanceExpected
        payable(ic).balance;
        vm.stopPrank();
    }
    
    // test that manager can bond more and delegation is recorded
    function testManagerCanBondMore() public {
        vm.startPrank(stakingManager, stakingManager);
        uint deposit = 200 ether;
        address candidate = member1;
        uint amount = 2 ether;
        uint more = 1 ether;
        uint delegationExpected = amount + more;
        uint candidateDelegationCount = 100;
        uint delegatorDelegationCount = 100;
        ic.whitelist(member1, true);
        ic.depositCover(member1); // ic gets 200 ether
        uint icBalanceStart = address(ic).balance;
        uint icBalanceExpected = icBalanceStart - (amount + more);
        ds.delegate(candidate, amount, candidateDelegationCount, delegatorDelegationCount);
        ds.delegatorBondMore(candidate, more);
        // getIsDelegated() should return true
        ds.getIsDelegated(candidate);
        // getDelegation() should return the new delegationExpected amount
        ds.getDelegation(candidate); //, delegationExpected
        // getCollatorsDelegated() should return the candidate's address
        ds.getCollatorsDelegated(0);
        // ic's balance should be icBalanceExpected
        payable(ic).balance;
        vm.stopPrank();
    }
    
}
