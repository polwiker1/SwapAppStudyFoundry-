// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IV3Factory} from "./interfaces.sol/IV3Factory.sol";
import {IV3Pool} from "./interfaces.sol/IV3Pool.sol";

contract V3RangeHelper {
    address public immutable v3FactoryAddress;

    enum ExposureMode {
        Low,
        Medium,
        High
    }

    struct RangePreview {
        address pool;
        int24 currentTick;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint16 widthInSpacings;
    }

    constructor(address _v3FactoryAddress) {
        require(_v3FactoryAddress != address(0), "factory=0");
        v3FactoryAddress = _v3FactoryAddress;
    }

    function previewRange(address tokenA, address tokenB, uint24 fee, ExposureMode mode)
        external
        view
        returns (RangePreview memory preview)
    {
        require(tokenA != address(0) && tokenB != address(0), "token=0");
        require(tokenA != tokenB, "same token");

        preview.pool = IV3Factory(v3FactoryAddress).getPool(tokenA, tokenB, fee);
        require(preview.pool != address(0), "pool not found");

        (, preview.currentTick,,,,,) = IV3Pool(preview.pool).slot0();
        preview.tickSpacing = IV3Pool(preview.pool).tickSpacing();
        require(preview.tickSpacing > 0, "bad spacing");

        preview.widthInSpacings = _widthInSpacings(mode);
        int24 centerTick = _floorToSpacing(preview.currentTick, preview.tickSpacing);
        int24 halfWidth = int24(uint24(preview.widthInSpacings)) * preview.tickSpacing;

        preview.tickLower = centerTick - halfWidth;
        preview.tickUpper = centerTick + halfWidth;
    }

    function _widthInSpacings(ExposureMode mode) internal pure returns (uint16) {
        if (mode == ExposureMode.Low) return 1_000;
        if (mode == ExposureMode.Medium) return 300;
        return 80;
    }

    function _floorToSpacing(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) {
            compressed--;
        }
        return compressed * tickSpacing;
    }
}
