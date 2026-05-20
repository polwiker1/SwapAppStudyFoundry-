// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}
