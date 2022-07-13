# Calyptia BATS

All common Calyptia BATS framework and setup tooling. Intended to simplify and enable reuse of testing by handling all the framework set up, tests themselves are in the product repo.

The intention is to use [`calyptia-bats.sh`](./calyptia-bats.sh) to run all tests, it can be wrapped in a simple launcher that sets additional variables.

TEST_ROOT should be set to the location of the actual BATS tests to run.

`test-helpers.bash` contains common functions to use.

Additional helpers can be provided in TEST_ROOT/helpers.

`install-bats.sh` will install all supporting libraries required.
