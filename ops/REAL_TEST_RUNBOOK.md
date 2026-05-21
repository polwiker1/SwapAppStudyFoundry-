# Real Test Runbook

Bitacora publica para pausar y retomar el modulo sin perder contexto. No guardar aca private keys, mnemonics, RPC privados pagos, montos sensibles o datos de wallet que no quieras publicar.

## Estado Del Modulo

Listo:

- Unit tests V2/V3 verdes.
- Fork test V3 de posicion activa + fees probado localmente por el usuario.
- `.env.example` creado.
- `.gitignore` protege `.env`, `.env.*` y bitacoras locales.
- Script de balances disponible.
- Helpers V3 disponibles: quote, rango, limite de precio.

Pendiente antes de integracion Zum Pay:

- prueba real controlada con monto chico
- registrar tx hashes y balances
- decidir arquitectura de deploy/integracion
- preparar ABIs o paquete para frontend

## Objetivo De Prueba Real

Validar con USDC real bajo que el flujo es operable end-to-end en Arbitrum:

- consultar balances
- agregar liquidez V2 desde USDC
- retirar liquidez V2 hacia USDC
- agregar liquidez V3 desde USDC con exposicion `Low`
- confirmar NFT de posicion V3
- colectar fees cuando haya actividad
- registrar gas, refunds, balances y fricciones

## Setup Local

```bash
cp .env.example .env
```

Completar:

```bash
ARBITRUM_RPC_URL=https://arbitrum-one-rpc.publicnode.com
WATCH_WALLET=0xYourWallet
```

Opcional si Zum Pay tiene endpoint protegido:

```bash
ARBITRUM_PROTECTED_RPC_URL=https://...
```

## Balance Check

```bash
source .env
forge script script/CheckBalances.s.sol:CheckBalances --rpc-url "$ARBITRUM_RPC_URL"
```

Registrar balances antes y despues de cada operacion.

## Preflight

- `forge build --sizes` pasa.
- Unit tests pasan.
- Fork test principal pasa.
- Wallet tiene monto chico de USDC.
- Wallet tiene ETH suficiente para gas en Arbitrum.
- Se entiende allowance/approval antes de firmar.
- `amountOutMinSwap` viene de quote.
- `tickLower/tickUpper` vienen de `V3RangeHelper` con `Low`.
- `sqrtPriceLimitX96` viene de `V3PriceLimitHelper`, no `0`.
- Deadline razonable: corto pero usable.
- Si existe RPC protegido, usarlo para ejecucion.

## Comandos De Retome

```bash
git status --short
forge build --sizes
forge test -vv --match-contract SwapAppTest
forge test -vv --match-contract V3LiquidityStrategyTest
forge test -vv --match-contract V3PriceLimitHelperTest
forge test -vv --match-contract V3QuoteHelperTest
forge test -vv --match-contract V3RangeHelperTest
```

Fork V3 principal:

```bash
ARBITRUM_RPC_URL=https://arbitrum-one-rpc.publicnode.com forge test -vv --match-test test_fork_v3_position_remains_active_and_collects_fees_after_swaps
```

## Log Local

Crear logs privados/locales con este formato:

```bash
touch ops/2026-05-21-real-test.local.md
```

Los `*.local.md` estan ignorados por git.

Template:

```md
# Real Test Log - YYYY-MM-DD

Network:
Wallet:
RPC:
Protected RPC:

## Starting Balances

ETH:
USDC:
WETH:

## Parameters

Max USDC:
Slippage bps:
Deadline:
V3 exposure:
V3 fee tier:
tickLower:
tickUpper:
sqrtPriceLimitX96:

## V2 Add Liquidity

Amount USDC in:
Tx hash:
Gas:
USDC used:
Token used:
LP received:
Refund:
Notes:

## V2 Remove Liquidity

LP burned:
Tx hash:
Gas:
USDC returned:
Notes:

## V3 Add Liquidity

Amount USDC in:
Tx hash:
Gas:
tokenId:
Liquidity:
USDC used:
Token used:
Refund:
Notes:

## V3 Collect Fees

Tx hash:
Gas:
amount0 collected:
amount1 collected:
Notes:

## Ending Balances

ETH:
USDC:
WETH:

## Result

What worked:
What failed:
What to improve before Zum Pay integration:
```

## Stop Conditions

- Approval target inesperado.
- Slippage/minimums no entendidos.
- `sqrtPriceLimitX96` en `0` para prueba real sin justificacion.
- Balance cambia de forma no esperada.
- NFT V3 no se puede consultar.
- Simulacion falla.
- Gas o monto excede limite definido.
