// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface ISwappApp {
    struct RemoveLiquidityToUSDCParams {
        address lpToken;
        address usdc;
        address tokenOther;
        uint256 liquidityToBurn;
        uint256 amountUSDCMinRemove;
        uint256 amountTokenMinRemove;
        uint256 amountOutMinSwap;
        address[] pathTokenOtherToUSDC;
        uint256 deadline;
    }

    function getAmountOutMin(uint256 amountIn_, address[] calldata path_) external view returns (uint256);

    function swapTokens(uint256 amountIn_, uint256 amountOutMin_, address[] calldata path_, uint256 deadline_)
        external
        returns (uint256 amountOut);

    function claimPendingGovRewards() external returns (uint256 claimed);

    function addLiquiditySingleTokenUSDC(
        address usdc,
        address tokenOther,
        uint256 amountInUSDC,
        uint256 amountOutMinSwap,
        uint256 amountUSDCMinAdd,
        uint256 amountTokenMinAdd,
        address[] calldata pathUSDCToTokenOther,
        uint256 deadline
    ) external returns (uint256 amountUSDCUsed, uint256 amountTokenUsed, uint256 liquidity);

    function removeLiquidityToUSDC(RemoveLiquidityToUSDCParams calldata p) external returns (uint256 totalUSDCOut);
}
