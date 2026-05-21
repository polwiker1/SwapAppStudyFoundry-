# SwapApp (Foundry)

`SwapApp` es un modulo DeFi educativo/prototipo sobre Foundry. El objetivo es simplificar operaciones de swap y provision de liquidez desde una entrada simple en USDC, con foco en integracion futura dentro de Zum Pay.

## Estado Actual

- Swap ERC-20 con fee de protocolo y rewards en token de gobernanza.
- Liquidez V2 desde un solo token (`USDC -> swap parcial -> add liquidity`).
- Estrategia V3 para crear posiciones de liquidez concentrada desde USDC.
- Helper de quotes V3 para calcular minimos por slippage.
- Helper de rangos V3 para traducir exposicion `Low / Medium / High` a `tickLower / tickUpper`.
- Helper de limite de precio V3 para sugerir `sqrtPriceLimitX96` y evitar usar `0` en produccion.
- Fork test V3 que valida posicion activa y cobro de fees despues de swaps.
- Runbook para prueba real controlada en Arbitrum.

## Idea de Producto

El usuario no deberia tener que entender rutas, ticks, fee tiers o liquidez concentrada para operar.

Flujo buscado:

1. Entra con USDC.
2. Elige V2 simple o V3 concentrada.
3. En V3 elige perfil de exposicion: `Low`, `Medium` o `High`.
4. La app calcula quote, rango, minimos y limite de precio.
5. El usuario firma una operacion con condiciones claras.

## Arquitectura

### Core

- [src/swappApp.sol](/home/pablowiker/foundry-study/swapApp/src/swappApp.sol): swaps, rewards, add/remove liquidity V2.
- [src/GovernanceToken.sol](/home/pablowiker/foundry-study/swapApp/src/GovernanceToken.sol): token GOV usado en rewards.

### V3

- [src/V3LiquidityStrategy.sol](/home/pablowiker/foundry-study/swapApp/src/V3LiquidityStrategy.sol): ejecuta el flujo V3 desde USDC.
- [src/V3QuoteHelper.sol](/home/pablowiker/foundry-study/swapApp/src/V3QuoteHelper.sol): estima salida esperada y minimos por slippage.
- [src/V3RangeHelper.sol](/home/pablowiker/foundry-study/swapApp/src/V3RangeHelper.sol): calcula rangos por perfil de exposicion.
- [src/V3PriceLimitHelper.sol](/home/pablowiker/foundry-study/swapApp/src/V3PriceLimitHelper.sol): calcula `sqrtPriceLimitX96` sugerido.
- [src/libraries/TickMath.sol](/home/pablowiker/foundry-study/swapApp/src/libraries/TickMath.sol): matematica V3 para convertir tick a sqrt price.

### Operacion

- [.env.example](/home/pablowiker/foundry-study/swapApp/.env.example): variables no sensibles y direcciones criticas.
- [script/CheckBalances.s.sol](/home/pablowiker/foundry-study/swapApp/script/CheckBalances.s.sol): consulta balances de ETH/USDC/WETH.
- [ops/REAL_TEST_RUNBOOK.md](/home/pablowiker/foundry-study/swapApp/ops/REAL_TEST_RUNBOOK.md): checklist y bitacora para prueba real.

## Protecciones de Ejecucion

- `amountOutMinSwap`: revierte si el swap recibe menos de lo aceptado.
- `amountUSDCMinMint` / `amountTokenMinMint`: revierte si el mint V3 queda fuera de minimos.
- `sqrtPriceLimitX96`: limita el precio cruzado por el swap V3.
- `deadline`: evita ejecucion tardia.
- `V3QuoteHelper`: sugiere minimos desde quote + slippage.
- `V3RangeHelper`: evita rangos/ticks incoherentes.
- `V3PriceLimitHelper`: sugiere limite de precio para no usar `0` en produccion.

Nota: para ejecucion real sensible, conviene sumar RPC protegido/MEV protection desde la wallet o frontend.

## Comandos

### Setup

```bash
cp .env.example .env
```

Editar `.env` localmente:

```bash
ARBITRUM_RPC_URL=https://arbitrum-one-rpc.publicnode.com
WATCH_WALLET=0xYourWallet
```

`.env` no debe subirse al repo.

### Build

```bash
forge build --sizes
```

### Tests Unitarios

```bash
forge test -vv --match-contract SwapAppTest
forge test -vv --match-contract V3LiquidityStrategyTest
forge test -vv --match-contract V3PriceLimitHelperTest
forge test -vv --match-contract V3QuoteHelperTest
forge test -vv --match-contract V3RangeHelperTest
```

### Tests Fork Arbitrum

```bash
ARBITRUM_RPC_URL=https://arbitrum-one-rpc.publicnode.com forge test -vv --match-contract SwapAppForkArbitrumTest
```

Test puntual de posicion V3 activa + fees:

```bash
ARBITRUM_RPC_URL=https://arbitrum-one-rpc.publicnode.com forge test -vv --match-test test_fork_v3_position_remains_active_and_collects_fees_after_swaps
```

### Balances

```bash
source .env
forge script script/CheckBalances.s.sol:CheckBalances --rpc-url "$ARBITRUM_RPC_URL"
```

### Formato

```bash
forge fmt
forge fmt --check
```

## Prueba Real Controlada

Usar [ops/REAL_TEST_RUNBOOK.md](/home/pablowiker/foundry-study/swapApp/ops/REAL_TEST_RUNBOOK.md).

Primer objetivo:

- monto chico de USDC
- Arbitrum One
- V3 con exposicion `Low`
- slippage definido
- `sqrtPriceLimitX96` sugerido por helper
- registrar balances, tx hashes, gas, refunds y fees

## Proxima Sesion

- Revisar git status y confirmar que no queden cambios sin entender.
- Ejecutar unit tests y fork test principal.
- Si se va a probar real: completar `.env`, correr balances y seguir el runbook.
- Antes de integrar en Zum Pay: decidir si se deploya este modulo como contratos separados o si se empaqueta como modulo interno.

## Seguridad

Este repositorio es educativo/prototipo. Antes de produccion:

- Auditoria externa.
- Ownership seguro (multisig/timelock si aplica).
- RPC protegido para ejecuciones sensibles.
- Politica de slippage/deadline por defecto.
- Monitoreo de balances, posiciones, refunds y fees.
- UX clara: esto no es renta fija ni rendimiento garantizado.

## Repositorio

https://github.com/polwiker1/SwapAppStudyFoundry-
