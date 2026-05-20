# SwapApp (Foundry)

`SwapApp` es un smart contract DeFi sobre Foundry que integra routers tipo Uniswap para resolver flujos de entrada, swap y provision de liquidez:

- Swaps con fee de protocolo y rewards en token de gobernanza.
- Provision de liquidez V2 partiendo de un solo token (USDC) en una sola operacion.
- Primera estrategia V3 para crear posiciones de liquidez concentrada desde USDC.
- Helper de quotes V3 para calcular salida esperada y minimos por slippage antes de ejecutar.

## Propuesta de valor

El objetivo es simplificar una operatoria financiera que suele ser manual:

1. Entrar con USDC.
2. Convertir automaticamente una parte al token par via `path`.
3. Agregar liquidez al pool.
4. Recibir LP tokens en V2 o una posicion NFT en V3 para participar proporcionalmente de las comisiones del pool.

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

### 3) `V3LiquidityStrategy.addLiquiditySingleTokenUSDCV3(...)`

- Recibe USDC desde el usuario.
- Valida que exista el pool V3 para `USDC/tokenOther/fee`.
- Swappea una parte por `tokenOther` usando `SwapRouter02`.
- Crea una posicion V3 con `NonfungiblePositionManager`.
- Permite definir `tickLower` y `tickUpper` para liquidez concentrada.
- Devuelve excedentes cuando el mint no usa el 100% de los tokens.

### 4) `V3QuoteHelper.previewSingleTokenUSDCV3(...)`

- Consulta `QuoterV2` para estimar cuanto `tokenOther` se recibe al swapear parte del USDC.
- Calcula `amountOutMinSwap` aplicando `slippageBps`.
- Calcula minimos iniciales para el mint V3 (`amountUSDCMinMint` y `amountTokenMinMint`).
- Devuelve datos utiles para preview: quote esperado, precio posterior, ticks cruzados y gas estimado.

## Contratos y tests

- Contrato principal: [src/swappApp.sol](/home/pablowiker/foundry-study/swapApp/src/swappApp.sol)
- Estrategia V3: [src/V3LiquidityStrategy.sol](/home/pablowiker/foundry-study/swapApp/src/V3LiquidityStrategy.sol)
- Helper de quotes V3: [src/V3QuoteHelper.sol](/home/pablowiker/foundry-study/swapApp/src/V3QuoteHelper.sol)
- Token de gobernanza: [src/GovernanceToken.sol](/home/pablowiker/foundry-study/swapApp/src/GovernanceToken.sol)
- Interfaces V2/V3: `src/interfaces.sol/`
- Tests: [test/SwapApp.t.sol](/home/pablowiker/foundry-study/swapApp/test/SwapApp.t.sol)

## CI (GitHub Actions)

Workflow: `.github/workflows/test.yml`

- Corre siempre tests unitarios (`SwapAppTest`, `V3LiquidityStrategyTest` y `V3QuoteHelperTest`).
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
forge test -vv --match-contract V3LiquidityStrategyTest
forge test -vv --match-contract V3QuoteHelperTest
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
