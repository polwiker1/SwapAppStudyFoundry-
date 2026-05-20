// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IV3Factory} from "./interfaces.sol/IV3Factory.sol";
import {ISwapRouter02} from "./interfaces.sol/ISwapRouter02.sol";
import {INonfungiblePositionManager} from "./interfaces.sol/INonfungiblePositionManager.sol";

contract V3LiquidityStrategy {
    using SafeERC20 for IERC20;

    address public immutable v3FactoryAddress;
    address public immutable swapRouter02Address;
    address public immutable nonfungiblePositionManagerAddress;

    event V3LiquidityAdded(
        address indexed provider,
        address indexed usdc,
        address indexed tokenOther,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 tokenId,
        uint128 liquidity,
        uint256 amountUSDCUsed,
        uint256 amountTokenUsed
    );

    struct AddLiquiditySingleTokenUSDCV3Params {
        address usdc;
        address tokenOther;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amountInUSDC;
        uint256 amountOutMinSwap;
        uint256 amountUSDCMinMint;
        uint256 amountTokenMinMint;
        uint160 sqrtPriceLimitX96;
        uint256 deadline;
    }

    constructor(address _v3FactoryAddress, address _swapRouter02Address, address _nonfungiblePositionManagerAddress) {
        require(_v3FactoryAddress != address(0), "factory=0");
        require(_swapRouter02Address != address(0), "router=0");
        require(_nonfungiblePositionManagerAddress != address(0), "positionManager=0");

        v3FactoryAddress = _v3FactoryAddress;
        swapRouter02Address = _swapRouter02Address;
        nonfungiblePositionManagerAddress = _nonfungiblePositionManagerAddress;
    }

    function addLiquiditySingleTokenUSDCV3(AddLiquiditySingleTokenUSDCV3Params calldata p)
        external
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amountUSDCUsed,
            uint256 amountTokenUsed,
            uint256 tokenOtherReceived
        )
    {
        require(block.timestamp <= p.deadline, "expired");
        require(p.usdc != address(0) && p.tokenOther != address(0), "token=0");
        require(p.usdc != p.tokenOther, "same token");
        require(p.amountInUSDC > 1, "amount too low");
        require(p.tickLower < p.tickUpper, "bad ticks");
        require(IV3Factory(v3FactoryAddress).getPool(p.usdc, p.tokenOther, p.fee) != address(0), "pool not found");

        IERC20(p.usdc).safeTransferFrom(msg.sender, address(this), p.amountInUSDC);

        uint256 amountToSwap = p.amountInUSDC / 2;
        uint256 usdcForLiquidity = p.amountInUSDC - amountToSwap;
        tokenOtherReceived = _swapExactUSDCToTokenOther(p, amountToSwap);

        (tokenId, liquidity, amountUSDCUsed, amountTokenUsed) =
            _mintV3PositionAndRefund(p, usdcForLiquidity, tokenOtherReceived);

        emit V3LiquidityAdded(
            msg.sender,
            p.usdc,
            p.tokenOther,
            p.fee,
            p.tickLower,
            p.tickUpper,
            tokenId,
            liquidity,
            amountUSDCUsed,
            amountTokenUsed
        );
    }

    function _swapExactUSDCToTokenOther(AddLiquiditySingleTokenUSDCV3Params calldata p, uint256 amountToSwap)
        internal
        returns (uint256 tokenOtherReceived)
    {
        IERC20(p.usdc).forceApprove(swapRouter02Address, amountToSwap);

        tokenOtherReceived = ISwapRouter02(swapRouter02Address)
            .exactInputSingle(
                ISwapRouter02.ExactInputSingleParams({
                    tokenIn: p.usdc,
                    tokenOut: p.tokenOther,
                    fee: p.fee,
                    recipient: address(this),
                    deadline: p.deadline,
                    amountIn: amountToSwap,
                    amountOutMinimum: p.amountOutMinSwap,
                    sqrtPriceLimitX96: p.sqrtPriceLimitX96
                })
            );
    }

    function _mintV3PositionAndRefund(
        AddLiquiditySingleTokenUSDCV3Params calldata p,
        uint256 usdcForLiquidity,
        uint256 tokenOtherForLiquidity
    ) internal returns (uint256 tokenId, uint128 liquidity, uint256 amountUSDCUsed, uint256 amountTokenUsed) {
        IERC20(p.usdc).forceApprove(nonfungiblePositionManagerAddress, usdcForLiquidity);
        IERC20(p.tokenOther).forceApprove(nonfungiblePositionManagerAddress, tokenOtherForLiquidity);

        bool usdcIsToken0 = p.usdc < p.tokenOther;
        INonfungiblePositionManager.MintParams memory mintParams;
        mintParams.fee = p.fee;
        mintParams.tickLower = p.tickLower;
        mintParams.tickUpper = p.tickUpper;
        mintParams.recipient = msg.sender;
        mintParams.deadline = p.deadline;

        if (usdcIsToken0) {
            mintParams.token0 = p.usdc;
            mintParams.token1 = p.tokenOther;
            mintParams.amount0Desired = usdcForLiquidity;
            mintParams.amount1Desired = tokenOtherForLiquidity;
            mintParams.amount0Min = p.amountUSDCMinMint;
            mintParams.amount1Min = p.amountTokenMinMint;
        } else {
            mintParams.token0 = p.tokenOther;
            mintParams.token1 = p.usdc;
            mintParams.amount0Desired = tokenOtherForLiquidity;
            mintParams.amount1Desired = usdcForLiquidity;
            mintParams.amount0Min = p.amountTokenMinMint;
            mintParams.amount1Min = p.amountUSDCMinMint;
        }

        uint256 amount0Used;
        uint256 amount1Used;
        (tokenId, liquidity, amount0Used, amount1Used) =
            INonfungiblePositionManager(nonfungiblePositionManagerAddress).mint(mintParams);

        (amountUSDCUsed, amountTokenUsed) = usdcIsToken0 ? (amount0Used, amount1Used) : (amount1Used, amount0Used);

        if (usdcForLiquidity > amountUSDCUsed) {
            IERC20(p.usdc).safeTransfer(msg.sender, usdcForLiquidity - amountUSDCUsed);
        }
        if (tokenOtherForLiquidity > amountTokenUsed) {
            IERC20(p.tokenOther).safeTransfer(msg.sender, tokenOtherForLiquidity - amountTokenUsed);
        }
    }
}
