# DAO with a voting token

## How to run
```shell
npm install
npx hardhat test
```

## Test output example
```shell
$ npx hardhat test


  Dao
    ✔ Should not create existing proposal (3655ms)
    ✔ Should accept proposal (117ms)
    ✔ Should reject proposal (118ms)
    ✔ Should forget accepted/rejeced proposals (337ms)
    ✔ Should not affect proposals with not enough votes (86ms)
    ✔ Should be able to change vote side with a lesser vote amount (187ms)
    ✔ Should not be able to increase vote amount (124ms)
    ✔ Should discard expired proposals


  8 passing (5s)
```