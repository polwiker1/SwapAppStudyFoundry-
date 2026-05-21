// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IV3Factory} from "./interfaces.sol/IV3Factory.sol";
import {IV3Pool} from "./interfaces.sol/IV3Pool.sol";
import {TickMath} from "./libraries/TickMath.sol";

contract V3PriceLimitHelper {
    uint16 public constant MAX_SLIPPAGE_BPS = 10_000;

    address public immutable v3FactoryAddress;

    struct PriceLimitPreview {
        address pool;
        int24 currentTick;
        int24 limitTick;
        bool zeroForOne;
        uint160 sqrtPriceLimitX96;
    }

    constructor(address _v3FactoryAddress) {
        require(_v3FactoryAddress != address(0), "factory=0");
        v3FactoryAddress = _v3FactoryAddress;
    }

    function previewSqrtPriceLimitX96(address tokenIn, address tokenOut, uint24 fee, uint16 slippageBps)
        external
        view
        returns (PriceLimitPreview memory preview)
    {
        require(tokenIn != address(0) && tokenOut != address(0), "token=0");
        require(tokenIn != tokenOut, "same token");
        require(slippageBps <= MAX_SLIPPAGE_BPS, "slippage>bsp");

        preview.pool = IV3Factory(v3FactoryAddress).getPool(tokenIn, tokenOut, fee);
        require(preview.pool != address(0), "pool not found");

        (, preview.currentTick,,,,,) = IV3Pool(preview.pool).slot0();
        preview.zeroForOne = tokenIn < tokenOut;
        preview.limitTick = preview.zeroForOne
            ? preview.currentTick - int24(uint24(slippageBps))
            : preview.currentTick + int24(uint24(slippageBps));
        preview.limitTick = _clampTick(preview.limitTick);
        preview.sqrtPriceLimitX96 = TickMath.getSqrtRatioAtTick(preview.limitTick);
    }

    function _clampTick(int24 tick) internal pure returns (int24) {
        if (tick < TickMath.MIN_TICK) return TickMath.MIN_TICK + 1;
        if (tick > TickMath.MAX_TICK) return TickMath.MAX_TICK - 1;
        return tick;
    }
}
