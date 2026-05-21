# SwapApp (Foundry)

`SwapApp` es un modulo DeFi educativo/prototipo sobre Foundry. El objetivo es simplificar operaciones de swap y provision de liquidez desde una entrada simple en USDC, con foco en integracion futura dentro de Zum Pay.

## Estado Actual

- Swap ERC-20 con fee de protocolo y rewards en token de gobernanza.
- Liquidez V2 desde un solo token (`USDC -> swap parcial -> add liquidity`).
- Estrategia V3 para crear posiciones de liquidez concentrada desde USDC.
- Salida V3 guiada para reducir liquidez, colectar tokens y volver a USDC.
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

## Treasury

`SwappApp` y `V3LiquidityStrategy` tienen treasury configurado por separado. Para esta etapa, la regla operativa es deployar ambos usando la misma address de treasury.

Esto mantiene la contabilidad simple:

- `SwappApp.treasury`: fees de swaps y salida guiada V2.
- `V3LiquidityStrategy.treasury`: fee del 1% en salida V3.
- Ambos deben apuntar al mismo destino operativo.

## Protecciones de Ejecucion

- `amountOutMinSwap`: revierte si el swap recibe menos de lo aceptado.
- `amountUSDCMinMint` / `amountTokenMinMint`: revierte si el mint V3 queda fuera de minimos.
- `sqrtPriceLimitX96`: limita el precio cruzado por el swap V3.
- `deadline`: evita ejecucion tardia.
- `V3QuoteHelper`: sugiere minimos desde quote + slippage.
- `V3RangeHelper`: evita rangos/ticks incoherentes.
- `V3PriceLimitHelper`: sugiere limite de precio para no usar `0` en produccion.
- Salida V2 cobra `3.5%` sobre el USDC total de salida y lo envia a `treasury`.
- Salida V3 cobra `1%` sobre el USDC total de salida y lo envia a `treasury`.

Nota: para ejecucion real sensible, conviene sumar RPC protegido/MEV protection desde la wallet o frontend.

## Entrada Y Salida V3

Entrada:

- El usuario aprueba USDC al contrato `V3LiquidityStrategy`.
- El contrato swappea una parte a `tokenOther`.
- El contrato mintea la posicion V3.
- El NFT queda directamente en la wallet del usuario (`recipient = msg.sender`).

Salida guiada:

- El usuario debe aprobar su NFT V3 al contrato `V3LiquidityStrategy`.
- El contrato llama `decreaseLiquidity(...)`.
- El contrato llama `collect(...)` hacia si mismo.
- El contrato swappea `tokenOther` a USDC.
- El contrato cobra `1%` de execution/strategy fee sobre `totalUSDCOut`.
- El contrato envia la fee a `treasury`.
- El contrato devuelve el USDC neto al usuario.
- Si `burnIfEmpty = true` y la liquidez queda en cero, intenta quemar el NFT.

Owner/treasury no pueden retirar liquidez del usuario porque el NFT pertenece al usuario. La estrategia solo puede operar el NFT si el usuario la aprueba.

## Entrada Y Salida V2

Entrada:

- El usuario aprueba USDC al contrato `SwappApp`.
- El contrato swappea una parte a `tokenOther`.
- El contrato agrega liquidez en Uniswap V2.
- Los LP tokens quedan directamente en la wallet del usuario.

Salida guiada:

- El usuario aprueba sus LP tokens V2 al contrato `SwappApp`.
- El contrato retira la liquidez.
- El contrato swappea `tokenOther` a USDC.
- El contrato cobra `3.5%` de strategy fee sobre `totalUSDCOut`.
- El contrato envia la fee a `treasury`.
- El contrato devuelve el USDC neto al usuario.

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
