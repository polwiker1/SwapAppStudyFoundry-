# SwapApp (Foundry)

`SwapApp` es un smart contract DeFi sobre Foundry que integra un router tipo Uniswap V2 para resolver dos flujos:

- Swaps con fee de protocolo y rewards en token de gobernanza.
- Provision de liquidez partiendo de un solo token (USDC) en una sola operacion.

## Propuesta de valor

El objetivo es simplificar una operatoria financiera que suele ser manual:

1. Entrar con USDC.
2. Convertir automaticamente una parte al token par via `path`.
3. Agregar liquidez al pool.
4. Recibir LP tokens y participar proporcionalmente de las comisiones del pool (0.3% por swap en Uniswap V2 estandar).

Esto reduce friccion operativa y errores manuales en procesos DeFi.

## Flujos implementados

### 1) `swapTokens(...)`

- Cobra fee configurable (`feeBps`).
- Envia fee a `treasury`.
- Calcula y paga reward en token GOV segun:
- `rewardShareBps`
- `govTokensPerFeeToken`
- Si no hay GOV suficiente, registra saldo pendiente en `pendingGovRewards`.

### 2) `addLiquiditySingleTokenUSDC(...)`

- Recibe USDC desde el usuario.
- Divide monto 50/50:
- una parte se swapea a `tokenOther`
- la otra queda en USDC
- Agrega liquidez al par `USDC/tokenOther`.
- Aplica protecciones de ejecucion:
- `deadline`
- `amountOutMinSwap`
- `amountUSDCMinAdd` / `amountTokenMinAdd`
- Devuelve excedentes cuando corresponde (refund).

## Contratos y tests

- Contrato principal: [src/swappApp.sol](/home/pablowiker/foundry-study/swapApp/src/swappApp.sol)
- Token de gobernanza: [src/GovernanceToken.sol](/home/pablowiker/foundry-study/swapApp/src/GovernanceToken.sol)
- Interfaces V2: `src/interfaces.sol/`
- Tests: [test/SwapApp.t.sol](/home/pablowiker/foundry-study/swapApp/test/SwapApp.t.sol)

## CI (GitHub Actions)

Workflow: `.github/workflows/test.yml`

- Corre siempre tests unitarios (`SwapAppTest`).
- Corre tests de fork (`SwapAppForkArbitrumTest`) solo si existe el secret `ARBITRUM_RPC_URL`.

Con esto, el pipeline no falla por falta de infraestructura RPC cuando el secret no esta configurado.

## Setup y comandos utiles

### Requisitos

- Foundry instalado (`forge`, `cast`, `anvil`).
- Para tests fork: `ARBITRUM_RPC_URL`.

### Compilar

```bash
forge build
```

### Tests unitarios

```bash
forge test -vv --match-contract SwapAppTest
```

### Tests fork (Arbitrum)

```bash
export ARBITRUM_RPC_URL="https://arb1.arbitrum.io/rpc"
forge test -vv --match-contract SwapAppForkArbitrumTest
```

### Coverage

```bash
forge coverage --report summary
```

### Formato

```bash
forge fmt
forge fmt --check
```

## Repositorio

https://github.com/polwiker1/SwapAppStudyFoundry-

## Nota de seguridad

Proyecto educativo/prototipo. Antes de produccion:

- Auditoria externa.
- Ownership seguro (multisig/timelock).
- Politica de fondeo de rewards.
- Monitoreo on-chain de eventos y parametros.
