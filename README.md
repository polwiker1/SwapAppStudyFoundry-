# SwapApp (Foundry)

`SwapApp` es un smart contract de intercambio de tokens ERC-20 que se integra con un router tipo Uniswap V2 y agrega un modelo de incentivos con token de gobernanza.

## Que problema resuelve

Permite hacer swaps de tokens mientras:

- Cobra una fee configurable por operacion.
- Envia esa fee a una treasury.
- Recompensa al usuario con un token de gobernanza en base a un porcentaje de la fee.
- Si no hay suficiente liquidez de token de gobernanza, guarda la recompensa pendiente para reclamarla despues.

## Como funciona

1. El usuario llama `swapTokens(...)` con `amountIn`, `path`, `amountOutMin` y `deadline`.
2. El contrato calcula la fee (`feeBps`) y separa:
- `feeAmount` para treasury.
- `amountToSwap` para el router.
3. Ejecuta el swap en el router V2.
4. Calcula recompensa en governance token:
- `% fee para rewards` (`rewardShareBps`).
- `tasa gov por fee` (`govTokensPerFeeToken`).
5. Si hay balance suficiente de token GOV, paga al usuario.
6. Si no alcanza, paga parcial y guarda el resto en `pendingGovRewards`.

## Ventajas del enfoque

- Monetizacion clara del protocolo via treasury.
- Incentivos directos al usuario sin afectar la UX del swap.
- Parametros de negocio configurables por owner:
- `setFeeParams`
- `setTreasury`
- `setGovTokensPerFeeToken`
- Compatible con routers V2 existentes.
- Incluye estrategia de pagos pendientes para no bloquear swaps por falta de liquidez de rewards.

## Arquitectura del proyecto

- Contrato principal: [src/swappApp.sol](/home/pablowiker/foundry-study/swapApp/src/swappApp.sol)
- Token de gobernanza: [src/GovernanceToken.sol](/home/pablowiker/foundry-study/swapApp/src/GovernanceToken.sol)
- Tests unitarios + fork: [test/SwapApp.t.sol](/home/pablowiker/foundry-study/swapApp/test/SwapApp.t.sol)

## Requisitos

- Foundry instalado (`forge`, `cast`, `anvil`).
- Para pruebas de fork: variable `ARBITRUM_RPC_URL`.

## Uso rapido

### Compilar

```bash
forge build
```

### Ejecutar tests unitarios

```bash
forge test -vv
```

### Ejecutar test de integracion con fork de Arbitrum

```bash
export ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
forge test --match-test test_fork_swap_on_arbitrum_router --fork-url arbitrum -vv
```

Router usado en el test de fork (Arbitrum):

- `0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24`

### Coverage

```bash
forge coverage --report summary
```

### Formato

```bash
forge fmt
forge fmt --check
```

## Nota de seguridad

Este repositorio es un proyecto educativo/prototipo. Antes de usar en produccion se recomienda:

- Auditoria externa.
- Manejo seguro de ownership (multisig/timelock).
- Politica operativa para fondeo de rewards.
- Monitoreo de eventos y parametros on-chain.
