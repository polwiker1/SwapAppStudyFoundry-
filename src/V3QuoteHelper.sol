// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IQuoterV2} from "./interfaces.sol/IQuoterV2.sol";

contract V3QuoteHelper {
    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public immutable quoterV2Address;

    struct SingleTokenV3PreviewParams {
        address usdc;
        address tokenOther;
        uint24 fee;
        uint256 amountInUSDC;
        uint16 slippageBps;
        uint160 sqrtPriceLimitX96;
    }

    struct SingleTokenV3Preview {
        uint256 amountToSwap;
        uint256 usdcForLiquidity;
        uint256 expectedTokenOther;
        uint256 amountOutMinSwap;
        uint256 amountUSDCMinMint;
        uint256 amountTokenMinMint;
        uint160 sqrtPriceX96After;
        uint32 initializedTicksCrossed;
        uint256 gasEstimate;
    }

    constructor(address _quoterV2Address) {
        require(_quoterV2Address != address(0), "quoter=0");
        quoterV2Address = _quoterV2Address;
    }

    function previewSingleTokenUSDCV3(SingleTokenV3PreviewParams calldata p)
        external
        returns (SingleTokenV3Preview memory preview)
    {
        require(p.usdc != address(0) && p.tokenOther != address(0), "token=0");
        require(p.usdc != p.tokenOther, "same token");
        require(p.amountInUSDC > 1, "amount too low");
        require(p.slippageBps <= BPS_DENOMINATOR, "slippage>bsp");

        preview.amountToSwap = p.amountInUSDC / 2;
        preview.usdcForLiquidity = p.amountInUSDC - preview.amountToSwap;

        (preview.expectedTokenOther, preview.sqrtPriceX96After, preview.initializedTicksCrossed, preview.gasEstimate) =
            IQuoterV2(quoterV2Address)
                .quoteExactInputSingle(
                    IQuoterV2.QuoteExactInputSingleParams({
                        tokenIn: p.usdc,
                        tokenOut: p.tokenOther,
                        amountIn: preview.amountToSwap,
                        fee: p.fee,
                        sqrtPriceLimitX96: p.sqrtPriceLimitX96
                    })
                );

        preview.amountOutMinSwap = _applySlippage(preview.expectedTokenOther, p.slippageBps);
        preview.amountUSDCMinMint = _applySlippage(preview.usdcForLiquidity, p.slippageBps);
        preview.amountTokenMinMint = _applySlippage(preview.expectedTokenOther, p.slippageBps);
    }

    function _applySlippage(uint256 amount, uint16 slippageBps) internal pure returns (uint256) {
        return (amount * (BPS_DENOMINATOR - slippageBps)) / BPS_DENOMINATOR;
    }
}
