// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IV2Router02} from "./interfaces.sol/IV2Router02.sol";

contract SwappApp is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public immutable v2Router02Address;
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

    constructor(
        address _v2Router02Address,
        address _governanceToken,
        address _treasury,
        uint16 _feeBps,
        uint16 _rewardShareBps,
        uint256 _govTokensPerFeeToken
    ) Ownable(msg.sender) {
        require(_v2Router02Address != address(0), "router=0");
        require(_governanceToken != address(0), "gov=0");
        require(_treasury != address(0), "treasury=0");
        require(_feeBps <= BPS_DENOMINATOR, "fee>bsp");
        require(_rewardShareBps <= BPS_DENOMINATOR, "share>bsp");

        v2Router02Address = _v2Router02Address;
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
        external
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
}
