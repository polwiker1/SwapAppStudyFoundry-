// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "../lib/forge-std/src/Script.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract CheckBalances is Script {
    address internal constant ARBITRUM_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant ARBITRUM_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function run() external view {
        address wallet = vm.envAddress("WATCH_WALLET");

        console2.log("wallet", wallet);
        console2.log("native balance wei", wallet.balance);
        _logTokenBalance("USDC", ARBITRUM_USDC, wallet);
        _logTokenBalance("WETH", ARBITRUM_WETH, wallet);
    }

    function _logTokenBalance(string memory symbol, address token, address wallet) internal view {
        uint8 decimals = IERC20Metadata(token).decimals();
        uint256 balance = IERC20(token).balanceOf(wallet);

        console2.log(symbol, token);
        console2.log("decimals", decimals);
        console2.log("raw balance", balance);
    }
}
