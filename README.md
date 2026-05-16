## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Test con fork de Arbitrum

```shell
$ export ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
$ forge test --fork-url arbitrum -vv
```

Opcional: fijar un bloque para tener resultados reproducibles.

```shell
$ forge test --fork-url arbitrum --fork-block-number 320000000 -vv
```

Ejecutar solo el test de integración de Arbitrum:

```shell
$ forge test --match-test test_fork_swap_on_arbitrum_router --fork-url arbitrum -vv
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
