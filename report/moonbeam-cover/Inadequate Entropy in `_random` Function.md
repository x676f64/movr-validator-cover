
### Description

The `_random` function in the contract is using block timestamp and difficulty as the source of randomness, which is inadequate. This can potentially be exploited by an attacker to predict the output of the function and gain an unfair advantage.

https://github.com/ioannist/moonriver-delegator-cover-contract/blob/7aa80de819f5c56135c4c7ef6d261f22b749eb73/contracts/DepositStaking.sol#L246-L251
```
    function _random() private view returns (uint256) {
        uint256 number = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.difficulty))
        ) % 251;
        return number;
    }
```
https://github.com/ioannist/moonriver-delegator-cover-contract/blob/7aa80de819f5c56135c4c7ef6d261f22b749eb73/contracts/DepositStaking.sol#L143-L162
```
    function forceScheduleRevoke() external {
        // There must be a non-paid delegator or member to call this method
        require(
...
        // A random collator with a delegated balance is chosen to undelegate from
        uint256 collatorIndex = _random() % collatorsDelegated.length;
        for (
            uint256 counter = collatorsDelegated.length;
            counter > 0;
            counter--
        ) {
            collatorIndex = (collatorIndex + 1) % collatorsDelegated.length;
            address candidate = collatorsDelegated[collatorIndex];
            if (candidate == address(0) || delegations[candidate].amount == 0) {
                continue;
            }
            _scheduleDelegatorRevoke(candidate);
            InactivityCover(INACTIVITY_COVER).resetNotPaid();
            emit ScheduleRevokeEvent(lastForcedUndelegationEra, candidate);
            break;
        }
```

### Impact

The inadequate randomness in the `_random` function can potentially allow an attacker to predict the output and gain an unfair advantage. This can compromise the integrity of the contract and its intended functionality.

### Recommendation

To address this issue, it is recommended to implement Moonbeam's Randomness pre-compile for more entropy in the `_random` function. This will provide a more secure and unpredictable source of randomness, mitigating the vulnerability. Moonbeam offers both a Local VRF and 

