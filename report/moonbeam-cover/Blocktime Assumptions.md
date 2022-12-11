### Description

https://github.com/ioannist/moonriver-delegator-cover-contract/blob/053dc667750665f915f7a528927c7a7bb2034887/contracts/InactivityCover.sol#L301-L303

```
erasCovered[collatorData.collatorAccount] = erasCov <= 1080
? erasCov
: 1080; // max 3 months
```

### Impact



### Recommendation



