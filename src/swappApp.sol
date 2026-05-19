// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IV2Router02} from "./interfaces.sol/IV2Router02.sol";
import {IV2Factory} from "./interfaces.sol/IV2Factory.sol";

contract SwappApp is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public immutable v2Router02Address;
    address public immutable v2FactoryAddress;
    IERC20 public immutable governanceToken;
    address public treasury;

    uint16 public feeBps; // e.g. 10 = 0.1%
    uint16 public rewardShareBps; // e.g. 3000 = 30% of fee
    uint256 public govTokensPerFeeToken; // scaled by 1e18

    mapping(address => uint256) public pendingGovRewards;

    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountSwapped,
        uint256 feeAmount
    );

    event RewardClaimed(address indexed user, uint256 amount);
    event FeeParamsUpdated(uint16 feeBps, uint16 rewardShareBps);
    event TreasuryUpdated(address treasury);
    event GovRateUpdated(uint256 govTokensPerFeeToken);
    event LiquidityAdded(address indexed provider, address tokenA, address tokenB, uint256 amountA, uint256 amountB, uint256 liquidity);
    event LiquidityRemovedToSingleToken(
        address indexed provider, address lpToken, address tokenOut, uint256 liquidityBurned, uint256 amountOut
    );

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

    struct AddLiquiditySingleTokenUSDCParams {
        address usdc;
        address tokenOther;
        uint256 amountInUSDC;
        uint256 amountOutMinSwap;
        uint256 amountUSDCMinAdd;
        uint256 amountTokenMinAdd;
        address[] pathUSDCToTokenOther;
        uint256 deadline;
    }

    constructor(
        address _v2Router02Address,
        address _v2FactoryAddress,
        address _governanceToken,
        address _treasury,
        uint16 _feeBps,
        uint16 _rewardShareBps,
        uint256 _govTokensPerFeeToken
    ) Ownable(msg.sender) {
        require(_v2Router02Address != address(0), "router=0");
        require(_v2FactoryAddress != address(0), "factory=0");
        require(_governanceToken != address(0), "gov=0");
        require(_treasury != address(0), "treasury=0");
        require(_feeBps <= BPS_DENOMINATOR, "fee>bsp");
        require(_rewardShareBps <= BPS_DENOMINATOR, "share>bsp");

        v2Router02Address = _v2Router02Address;
        v2FactoryAddress = _v2FactoryAddress;
        governanceToken = IERC20(_governanceToken);
        treasury = _treasury;
        feeBps = _feeBps;
        rewardShareBps = _rewardShareBps;
        govTokensPerFeeToken = _govTokensPerFeeToken;
    }

    function setFeeParams(uint16 _feeBps, uint16 _rewardShareBps) external onlyOwner {
        require(_feeBps <= BPS_DENOMINATOR, "fee>bsp");
        require(_rewardShareBps <= BPS_DENOMINATOR, "share>bsp");
        feeBps = _feeBps;
        rewardShareBps = _rewardShareBps;
        emit FeeParamsUpdated(_feeBps, _rewardShareBps);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "treasury=0");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setGovTokensPerFeeToken(uint256 _govTokensPerFeeToken) external onlyOwner {
        govTokensPerFeeToken = _govTokensPerFeeToken;
        emit GovRateUpdated(_govTokensPerFeeToken);
    }

    function getAmountOutMin(uint256 amountIn_, address[] calldata path_) external view returns (uint256) {
        uint256[] memory amountOutMins = IV2Router02(v2Router02Address).getAmountsOut(amountIn_, path_);
        return amountOutMins[path_.length - 1];
    }

    function swapTokens(uint256 amountIn_, uint256 amountOutMin_, address[] calldata path_, uint256 deadline_)
        public
        returns (uint256 amountOut)
    {
        require(path_.length >= 2, "bad path");

        IERC20 tokenIn = IERC20(path_[0]);
        uint256 feeAmount = (amountIn_ * feeBps) / BPS_DENOMINATOR;
        uint256 amountToSwap = amountIn_ - feeAmount;

        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn_);

        if (feeAmount > 0) {
            tokenIn.safeTransfer(treasury, feeAmount);
        }

        tokenIn.forceApprove(v2Router02Address, amountToSwap);
        uint256[] memory amountsOut = IV2Router02(v2Router02Address)
            .swapExactTokensForTokens(amountToSwap, amountOutMin_, path_, msg.sender, deadline_);

        amountOut = amountsOut[amountsOut.length - 1];

        uint256 rewardValueInFeeToken = (feeAmount * rewardShareBps) / BPS_DENOMINATOR;
        uint256 rewardGovAmount = (rewardValueInFeeToken * govTokensPerFeeToken) / 1e18;

        if (rewardGovAmount > 0) {
            uint256 availableGov = governanceToken.balanceOf(address(this));
            if (availableGov >= rewardGovAmount) {
                governanceToken.safeTransfer(msg.sender, rewardGovAmount);
            } else {
                if (availableGov > 0) {
                    governanceToken.safeTransfer(msg.sender, availableGov);
                }
                pendingGovRewards[msg.sender] += (rewardGovAmount - availableGov);
                rewardGovAmount = availableGov;
            }
        }

        emit SwapExecuted(msg.sender, path_[0], path_[path_.length - 1], amountIn_, amountToSwap, feeAmount);
    }

    function claimPendingGovRewards() external returns (uint256 claimed) {
        uint256 pending = pendingGovRewards[msg.sender];
        require(pending > 0, "no pending");

        uint256 availableGov = governanceToken.balanceOf(address(this));
        require(availableGov > 0, "no gov liquidity");

        claimed = pending <= availableGov ? pending : availableGov;
        pendingGovRewards[msg.sender] = pending - claimed;
        governanceToken.safeTransfer(msg.sender, claimed);

        emit RewardClaimed(msg.sender, claimed);
    }
    function addLiquiditySingleTokenUSDC(AddLiquiditySingleTokenUSDCParams calldata p)
        external
        returns (uint256 amountUSDCUsed, uint256 amountTokenUsed, uint256 liquidity)
    {
        require(block.timestamp <= p.deadline, "expired");
        require(p.usdc != address(0) && p.tokenOther != address(0), "token=0");
        require(p.usdc != p.tokenOther, "same token");
        require(p.amountInUSDC > 1, "amount too low");
        require(p.pathUSDCToTokenOther.length >= 2, "bad path");
        require(p.pathUSDCToTokenOther[0] == p.usdc, "path in");
        require(p.pathUSDCToTokenOther[p.pathUSDCToTokenOther.length - 1] == p.tokenOther, "path out");
        require(IV2Factory(v2FactoryAddress).getPair(p.usdc, p.tokenOther) != address(0), "pair not found");

        IERC20(p.usdc).safeTransferFrom(msg.sender, address(this), p.amountInUSDC);

        uint256 amountToSwap = p.amountInUSDC / 2;
        uint256 usdcForLiquidity = p.amountInUSDC - amountToSwap;

        uint256 tokenOtherReceived =
            _swapExactToContract(p.usdc, amountToSwap, p.amountOutMinSwap, p.pathUSDCToTokenOther, p.deadline);

        (amountUSDCUsed, amountTokenUsed, liquidity) = _addLiquidityAndRefund(
            p.usdc,
            p.tokenOther,
            usdcForLiquidity,
            tokenOtherReceived,
            p.amountUSDCMinAdd,
            p.amountTokenMinAdd,
            p.deadline
        );

        emit LiquidityAdded(msg.sender, p.usdc, p.tokenOther, amountUSDCUsed, amountTokenUsed, liquidity);
    }

    function removeLiquidityToUSDC(RemoveLiquidityToUSDCParams calldata p) external returns (uint256 totalUSDCOut) {
        require(block.timestamp <= p.deadline, "expired");
        require(p.lpToken != address(0) && p.usdc != address(0) && p.tokenOther != address(0), "token=0");
        require(p.usdc != p.tokenOther, "same token");
        require(p.liquidityToBurn > 0, "liquidity=0");
        require(p.pathTokenOtherToUSDC.length >= 2, "bad path");
        require(p.pathTokenOtherToUSDC[0] == p.tokenOther, "path in");
        require(p.pathTokenOtherToUSDC[p.pathTokenOtherToUSDC.length - 1] == p.usdc, "path out");
        require(IV2Factory(v2FactoryAddress).getPair(p.usdc, p.tokenOther) != address(0), "pair not found");

        IERC20(p.lpToken).safeTransferFrom(msg.sender, address(this), p.liquidityToBurn);
        IERC20(p.lpToken).forceApprove(v2Router02Address, p.liquidityToBurn);

        (uint256 amountUSDCRemoved, uint256 amountTokenRemoved) = IV2Router02(v2Router02Address).removeLiquidity(
            p.usdc, p.tokenOther, p.liquidityToBurn, p.amountUSDCMinRemove, p.amountTokenMinRemove, address(this), p.deadline
        );

        IERC20(p.tokenOther).forceApprove(v2Router02Address, amountTokenRemoved);
        uint256[] memory swapOut = IV2Router02(v2Router02Address).swapExactTokensForTokens(
            amountTokenRemoved, p.amountOutMinSwap, p.pathTokenOtherToUSDC, address(this), p.deadline
        );

        uint256 usdcFromSwap = swapOut[swapOut.length - 1];
        totalUSDCOut = amountUSDCRemoved + usdcFromSwap;
        IERC20(p.usdc).safeTransfer(msg.sender, totalUSDCOut);

        emit LiquidityRemovedToSingleToken(msg.sender, p.lpToken, p.usdc, p.liquidityToBurn, totalUSDCOut);
    }

    function _swapExactToContract(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).forceApprove(v2Router02Address, amountIn);
        uint256[] memory swapOut =
            IV2Router02(v2Router02Address).swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), deadline);
        amountOut = swapOut[swapOut.length - 1];
    }

    function _addLiquidityAndRefund(
        address usdc,
        address tokenOther,
        uint256 usdcForLiquidity,
        uint256 tokenOtherForLiquidity,
        uint256 amountUSDCMinAdd,
        uint256 amountTokenMinAdd,
        uint256 deadline
    ) internal returns (uint256 amountUSDCUsed, uint256 amountTokenUsed, uint256 liquidity) {
        IERC20(usdc).forceApprove(v2Router02Address, usdcForLiquidity);
        IERC20(tokenOther).forceApprove(v2Router02Address, tokenOtherForLiquidity);
        (amountUSDCUsed, amountTokenUsed, liquidity) = IV2Router02(v2Router02Address).addLiquidity(
            usdc,
            tokenOther,
            usdcForLiquidity,
            tokenOtherForLiquidity,
            amountUSDCMinAdd,
            amountTokenMinAdd,
            msg.sender,
            deadline
        );

        if (usdcForLiquidity > amountUSDCUsed) {
            IERC20(usdc).safeTransfer(msg.sender, usdcForLiquidity - amountUSDCUsed);
        }
        if (tokenOtherForLiquidity > amountTokenUsed) {
            IERC20(tokenOther).safeTransfer(msg.sender, tokenOtherForLiquidity - amountTokenUsed);
        }
    }
}
